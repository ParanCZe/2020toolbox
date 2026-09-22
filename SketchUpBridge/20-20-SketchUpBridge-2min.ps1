$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$port = 8092
$prefix = "http://127.0.0.1:$port/"
$startedAt = [DateTime]::UtcNow
$expiresAt = $startedAt.AddMinutes(2)

function Get-LatestSketchUpPlugins {
    $root = Join-Path $env:APPDATA 'SketchUp'
    if (-not (Test-Path $root)) { return $null }
    $dirs = Get-ChildItem $root -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^SketchUp\s+\d{4}$' } |
        Sort-Object Name -Descending
    foreach ($d in $dirs) {
        $plugins = Join-Path $d.FullName 'SketchUp\Plugins'
        if (-not (Test-Path $plugins)) {
            New-Item -ItemType Directory -Force -Path $plugins | Out-Null
        }
        return [pscustomobject]@{ Name=$d.Name; Plugins=$plugins }
    }
    return $null
}

function Write-JsonResponse($ctx, $code, $obj) {
    $json = $obj | ConvertTo-Json -Depth 8 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    $ctx.Response.StatusCode = $code
    $ctx.Response.ContentType = 'application/json; charset=utf-8'
    $ctx.Response.Headers['Access-Control-Allow-Origin'] = '*'
    $ctx.Response.Headers['Access-Control-Allow-Methods'] = 'GET, POST, OPTIONS'
    $ctx.Response.Headers['Access-Control-Allow-Headers'] = 'Content-Type'
    $ctx.Response.ContentLength64 = $bytes.Length
    $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $ctx.Response.OutputStream.Close()
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($prefix)

try {
    $listener.Start()
} catch {
    exit 1
}

try {
    while ($listener.IsListening -and [DateTime]::UtcNow -lt $expiresAt) {
        $contextTask = $listener.GetContextAsync()

        while (-not $contextTask.IsCompleted -and [DateTime]::UtcNow -lt $expiresAt) {
            Start-Sleep -Milliseconds 150
        }

        if ([DateTime]::UtcNow -ge $expiresAt) { break }

        try {
            $ctx = $contextTask.GetAwaiter().GetResult()
            $req = $ctx.Request
            $path = $req.Url.AbsolutePath.ToLowerInvariant()

            if ($req.HttpMethod -eq 'OPTIONS') {
                $ctx.Response.StatusCode = 204
                $ctx.Response.Headers['Access-Control-Allow-Origin'] = '*'
                $ctx.Response.Headers['Access-Control-Allow-Methods'] = 'GET, POST, OPTIONS'
                $ctx.Response.Headers['Access-Control-Allow-Headers'] = 'Content-Type'
                $ctx.Response.Close()
                continue
            }

            if ($req.HttpMethod -eq 'GET' -and $path -eq '/status') {
                $su = Get-LatestSketchUpPlugins
                $remaining = [Math]::Max(0, [int][Math]::Ceiling(($expiresAt - [DateTime]::UtcNow).TotalSeconds))
                if ($null -eq $su) {
                    Write-JsonResponse $ctx 404 @{
                        ok=$false
                        error='Nebyla nalezena instalace SketchUp v AppData.'
                        remaining_seconds=$remaining
                        expires_at=$expiresAt.ToString('o')
                    }
                } else {
                    Write-JsonResponse $ctx 200 @{
                        ok=$true
                        sketchup=$su.Name
                        plugins=$su.Plugins
                        bridge='20-20 SketchUpBridge'
                        version='1.1'
                        lifetime_seconds=120
                        remaining_seconds=$remaining
                        expires_at=$expiresAt.ToString('o')
                    }
                }
                continue
            }

            if ($req.HttpMethod -eq 'POST' -and $path -eq '/install') {
                $su = Get-LatestSketchUpPlugins
                if ($null -eq $su) {
                    Write-JsonResponse $ctx 404 @{ok=$false;error='SketchUp Plugins složka nebyla nalezena.'}
                    continue
                }

                $fileName = [IO.Path]::GetFileName($req.QueryString['file'])
                if ([string]::IsNullOrWhiteSpace($fileName)) { $fileName = 'plugin.rbz' }
                if (-not $fileName.ToLowerInvariant().EndsWith('.rbz')) {
                    Write-JsonResponse $ctx 400 @{ok=$false;error='Povolen je pouze RBZ balíček.'}
                    continue
                }

                $tmpRoot = Join-Path $env:TEMP ('2020_su_bridge_' + [Guid]::NewGuid().ToString('N'))
                $extract = Join-Path $tmpRoot 'extract'
                New-Item -ItemType Directory -Force -Path $extract | Out-Null
                $rbz = Join-Path $tmpRoot $fileName

                $fs = [IO.File]::Create($rbz)
                try { $req.InputStream.CopyTo($fs) } finally { $fs.Dispose() }

                [IO.Compression.ZipFile]::ExtractToDirectory($rbz, $extract)
                $rootItems = Get-ChildItem $extract -Force
                $copied = @()

                foreach ($item in $rootItems) {
                    if ($item.Name -eq '__MACOSX') { continue }

                    if ($item.PSIsContainer) {
                        $target = Join-Path $su.Plugins $item.Name
                        if (Test-Path $target) { Remove-Item $target -Recurse -Force }
                        Copy-Item $item.FullName $target -Recurse -Force
                        $copied += $item.Name
                    } elseif ($item.Extension.ToLowerInvariant() -eq '.rb') {
                        Copy-Item $item.FullName (Join-Path $su.Plugins $item.Name) -Force
                        $copied += $item.Name
                    }
                }

                Remove-Item $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue

                if ($copied.Count -eq 0) {
                    Write-JsonResponse $ctx 400 @{ok=$false;error='RBZ neobsahuje SketchUp plugin (.rb + složka).'}
                    continue
                }

                Write-JsonResponse $ctx 200 @{
                    ok=$true
                    sketchup=$su.Name
                    plugins=$su.Plugins
                    file=$fileName
                    copied=$copied
                    remaining_seconds=[Math]::Max(0, [int][Math]::Ceiling(($expiresAt - [DateTime]::UtcNow).TotalSeconds))
                }
                continue
            }

            Write-JsonResponse $ctx 404 @{ ok=$false; error='Neznámý endpoint.' }
        } catch {
            try { Write-JsonResponse $ctx 500 @{ ok=$false; error=$_.Exception.Message } } catch {}
        }
    }
} finally {
    try { $listener.Stop() } catch {}
    try { $listener.Close() } catch {}
}
