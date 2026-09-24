$ErrorActionPreference = 'SilentlyContinue'

function Test-PythonExe([string]$Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try {
        $out = & $Path -c "import sys; print(sys.executable if sys.version_info.major == 3 else '')" 2>$null
        if ($LASTEXITCODE -eq 0 -and $out) {
            return ($out | Select-Object -First 1).Trim()
        }
    } catch {}
    return $null
}

# 1) Python Launcher / PATH
try {
    $out = & py -3 -c "import sys; print(sys.executable)" 2>$null
    if ($LASTEXITCODE -eq 0 -and $out) {
        ($out | Select-Object -First 1).Trim()
        exit 0
    }
} catch {}

try {
    $out = & python -c "import sys; print(sys.executable if sys.version_info.major == 3 else '')" 2>$null
    if ($LASTEXITCODE -eq 0 -and $out) {
        ($out | Select-Object -First 1).Trim()
        exit 0
    }
} catch {}

# 2) Python Launcher installed, but not on PATH
$launcher = Join-Path $env:LOCALAPPDATA 'Programs\Python\Launcher\py.exe'
if (Test-Path -LiteralPath $launcher) {
    try {
        $out = & $launcher -3 -c "import sys; print(sys.executable)" 2>$null
        if ($LASTEXITCODE -eq 0 -and $out) {
            ($out | Select-Object -First 1).Trim()
            exit 0
        }
    } catch {}
}

# 3) Registry installations
$registryRoots = @(
    'Registry::HKEY_CURRENT_USER\Software\Python\PythonCore',
    'Registry::HKEY_LOCAL_MACHINE\Software\Python\PythonCore',
    'Registry::HKEY_LOCAL_MACHINE\Software\WOW6432Node\Python\PythonCore'
)
foreach ($root in $registryRoots) {
    foreach ($versionKey in (Get-ChildItem -LiteralPath $root | Sort-Object PSChildName -Descending)) {
        try {
            $installKey = Join-Path $versionKey.PSPath 'InstallPath'
            $installDir = (Get-Item -LiteralPath $installKey).GetValue('')
            if ($installDir) {
                $candidate = Join-Path $installDir 'python.exe'
                $valid = Test-PythonExe $candidate
                if ($valid) { $valid; exit 0 }
            }
        } catch {}
    }
}

# 4) Common per-user / system locations
$patterns = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python*\python.exe'),
    (Join-Path $env:ProgramFiles 'Python*\python.exe'),
    (Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) 'Python*\python.exe'),
    (Join-Path $env:USERPROFILE 'miniconda3\python.exe'),
    (Join-Path $env:USERPROFILE 'anaconda3\python.exe')
)

$candidates = @()
foreach ($pattern in $patterns) {
    if ($pattern) {
        $candidates += Get-ChildItem -Path $pattern -File
    }
}

foreach ($candidate in ($candidates | Sort-Object FullName -Descending -Unique)) {
    $valid = Test-PythonExe $candidate.FullName
    if ($valid) { $valid; exit 0 }
}

exit 1
