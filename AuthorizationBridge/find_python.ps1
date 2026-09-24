$ErrorActionPreference = 'SilentlyContinue'

function Test-PythonExe([string]$Path) {
    if (-not $Path) { return $null }
    if ($Path -match '\\Microsoft\\WindowsApps\\python(3)?\.exe$') { return $null }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $Path
        $psi.Arguments = '-c "import sys; print(sys.executable)"'
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $psi
        [void]$p.Start()
        if (-not $p.WaitForExit(4000)) {
            try { $p.Kill() } catch {}
            return $null
        }
        if ($p.ExitCode -ne 0) { return $null }
        $resolved = $p.StandardOutput.ReadToEnd().Trim()
        if (-not $resolved) { return $null }
        if ($resolved -match '\\Microsoft\\WindowsApps\\python(3)?\.exe$') { return $null }
        return $resolved
    } catch {
        return $null
    }
}

# IMPORTANT:
# Never execute the generic "python" command here. On Windows it can be the
# Microsoft Store execution alias and can hang/open the Store.
$candidates = New-Object System.Collections.Generic.List[string]

# Known per-user Python.org / winget locations, newest first.
foreach ($ver in @('314','313','312','311','310')) {
    if ($env:LOCALAPPDATA) {
        $candidates.Add((Join-Path $env:LOCALAPPDATA ("Programs\Python\Python{0}\python.exe" -f $ver)))
    }
}

# Common system installs.
foreach ($root in @($env:ProgramFiles, [Environment]::GetFolderPath('ProgramFilesX86'))) {
    if ($root) {
        foreach ($ver in @('314','313','312','311','310')) {
            $candidates.Add((Join-Path $root ("Python{0}\python.exe" -f $ver)))
        }
    }
}

# Conda, if present.
if ($env:USERPROFILE) {
    $candidates.Add((Join-Path $env:USERPROFILE 'miniconda3\python.exe'))
    $candidates.Add((Join-Path $env:USERPROFILE 'anaconda3\python.exe'))
}

# Registry installs.
$registryRoots = @(
    'Registry::HKEY_CURRENT_USER\Software\Python\PythonCore',
    'Registry::HKEY_LOCAL_MACHINE\Software\Python\PythonCore',
    'Registry::HKEY_LOCAL_MACHINE\Software\WOW6432Node\Python\PythonCore'
)
foreach ($root in $registryRoots) {
    if (-not (Test-Path -LiteralPath $root)) { continue }
    foreach ($versionKey in (Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue | Sort-Object PSChildName -Descending)) {
        try {
            $installKey = Join-Path $versionKey.PSPath 'InstallPath'
            $item = Get-Item -LiteralPath $installKey -ErrorAction SilentlyContinue
            if ($item) {
                $installDir = $item.GetValue('')
                if ($installDir) { $candidates.Add((Join-Path $installDir 'python.exe')) }
            }
        } catch {}
    }
}

# Last fallback: enumerate only the immediate Python folders under LocalAppData.
if ($env:LOCALAPPDATA) {
    $pythonRoot = Join-Path $env:LOCALAPPDATA 'Programs\Python'
    if (Test-Path -LiteralPath $pythonRoot) {
        Get-ChildItem -LiteralPath $pythonRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like 'Python*' } |
            Sort-Object Name -Descending |
            ForEach-Object { $candidates.Add((Join-Path $_.FullName 'python.exe')) }
    }
}

$seen = @{}
foreach ($candidate in $candidates) {
    if (-not $candidate) { continue }
    $key = $candidate.ToLowerInvariant()
    if ($seen.ContainsKey($key)) { continue }
    $seen[$key] = $true
    $valid = Test-PythonExe $candidate
    if ($valid) {
        Write-Output $valid
        exit 0
    }
}

exit 1
