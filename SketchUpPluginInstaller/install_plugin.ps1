param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$ProtocolUrl
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName PresentationFramework

function Fail([string]$Message) {
    [System.Windows.MessageBox]::Show(
        $Message,
        '20-20 Toolbox - instalace pluginu',
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Error
    ) | Out-Null
    exit 1
}

try {
    if ([string]::IsNullOrWhiteSpace($ProtocolUrl) -or $ProtocolUrl -notmatch '^(?i)twentytwentytoolbox:') {
        Fail ('Neplatny instalacni odkaz: ' + $ProtocolUrl)
    }

    # Windows / Chrome mohou custom URL normalizovat např. na
    # twentytwentytoolbox://install/?file=... místo //install?file=...
    $fileMatch = [regex]::Match($ProtocolUrl, '(?i)(?:\?|&)file=([^&]+)')
    if (-not $fileMatch.Success) {
        Fail ('Neplatny instalacni odkaz: ' + $ProtocolUrl)
    }

    $fileName = [Uri]::UnescapeDataString($fileMatch.Groups[1].Value)
    if ($fileName -notmatch '^[A-Za-z0-9._-]+\.rbz$') {
        Fail 'Neplatny nazev RBZ souboru.'
    }

    $sketchupRoot = Join-Path $env:APPDATA 'SketchUp'
    if (-not (Test-Path $sketchupRoot)) {
        Fail 'Nebyla nalezena zadna instalace SketchUp v AppData.'
    }

    $versions = Get-ChildItem $sketchupRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^SketchUp\s+(\d{4})$' } |
        Sort-Object { [int]([regex]::Match($_.Name,'\d{4}').Value) } -Descending

    if (-not $versions -or $versions.Count -eq 0) {
        Fail 'Nebyla nalezena zadna instalace SketchUp.'
    }

    $pluginsDir = Join-Path $versions[0].FullName 'SketchUp\Plugins'
    New-Item -ItemType Directory -Force -Path $pluginsDir | Out-Null

    $indexUrl = 'https://raw.githubusercontent.com/ParanCZe/2020toolbox/main/index.html'
    $indexText = (Invoke-WebRequest -UseBasicParsing -Uri $indexUrl).Content
    $pattern = '"' + [regex]::Escape($fileName) + '":"([^"]+)"'
    $match = [regex]::Match($indexText, $pattern)
    if (-not $match.Success) {
        Fail ('Verze ' + $fileName + ' nebyla v aktualnim Toolboxu nalezena.')
    }

    $bytes = [Convert]::FromBase64String($match.Groups[1].Value)
    $tempRoot = Join-Path $env:TEMP ('2020toolbox_plugin_' + [Guid]::NewGuid().ToString('N'))
    $extractDir = Join-Path $tempRoot 'extract'
    $rbzPath = Join-Path $tempRoot $fileName
    New-Item -ItemType Directory -Force -Path $extractDir | Out-Null
    [IO.File]::WriteAllBytes($rbzPath, $bytes)

    [IO.Compression.ZipFile]::ExtractToDirectory($rbzPath, $extractDir)

    $copied = New-Object System.Collections.Generic.List[string]
    foreach ($item in Get-ChildItem $extractDir -Force) {
        if ($item.Name -eq '__MACOSX') { continue }

        if ($item.PSIsContainer) {
            $target = Join-Path $pluginsDir $item.Name
            if (Test-Path $target) {
                Remove-Item $target -Recurse -Force
            }
            Copy-Item $item.FullName $target -Recurse -Force
            $copied.Add($item.Name)
        }
        elseif ($item.Extension.ToLowerInvariant() -eq '.rb') {
            Copy-Item $item.FullName (Join-Path $pluginsDir $item.Name) -Force
            $copied.Add($item.Name)
        }
    }

    Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue

    if ($copied.Count -eq 0) {
        Fail 'RBZ neobsahuje rozpoznatelny SketchUp plugin.'
    }

    $nl = [Environment]::NewLine
    [System.Windows.MessageBox]::Show(
        ($fileName + ' bylo nainstalovano / aktualizovano do ' + $versions[0].Name + '.' + $nl + $nl + 'Restartuj SketchUp, aby se nacetla nova verze.'),
        '20-20 Toolbox - hotovo',
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Information
    ) | Out-Null
}
catch {
    Fail $_.Exception.Message
}
