$ErrorActionPreference = 'SilentlyContinue'

function Test-PythonExe([string]$Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    # Ignore Microsoft Store execution aliases; they are not usable runtimes for venv/pip.
    if ($Path -match '\\Microsoft\\WindowsApps\\python(3)?\.exe$') { return $null }
    try {
        $out = & $Path -c "import sys; print(sys.executable if sys.version_info.major == 3 else '')" 2>$null
        if ($LASTEXITCODE -eq 0 -and $out) {
            $resolved = ($out | Select-Object -First 1).Trim()
            if ($resolved -and $resolved -notmatch '\\Microsoft\\WindowsApps\\python(3)?\.exe$') { return $resolved }
        }
    } catch {}
    return $null
}

function Test-CommandPython([string]$Command, [string[]]$Args) {
    try {
        $out = & $Command @Args 2>$null
        if ($LASTEXITCODE -eq 0 -and $out) {
            $candidate = ($out | Select-Object -First 1).Trim()
            return Test-PythonExe $candidate
        }
    } catch {}
    return $null
}

# 1) Python launcher / PATH
$valid = Test-CommandPython 'py' @('-3','-c','import sys; print(sys.executable)')
if ($valid) { $valid; exit 0 }
$valid = Test-CommandPython 'python' @('-c','import sys; print(sys.executable)')
if ($valid) { $valid; exit 0 }

# 2) Python Launcher installed outside PATH
$launcher = Join-Path $env:LOCALAPPDATA 'Programs\Python\Launcher\py.exe'
if (Test-Path -LiteralPath $launcher) {
    $valid = Test-CommandPython $launcher @('-3','-c','import sys; print(sys.executable)')
    if ($valid) { $valid; exit 0 }
}

# 3) Registry installations
$registryRoots = @(
    'Registry::HKEY_CURRENT_USER\Software\Python\PythonCore',
    'Registry::HKEY_LOCAL_MACHINE\Software\Python\PythonCore',
    'Registry::HKEY_LOCAL_MACHINE\Software\WOW6432Node\Python\PythonCore'
)
foreach ($root in $registryRoots) {
    if (-not (Test-Path -LiteralPath $root)) { continue }
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

# 4) Common user/system locations
$roots = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\Python'),
    $env:ProgramFiles,
    ([Environment]::GetFolderPath('ProgramFilesX86'))
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

$candidates = @()
foreach ($root in $roots) {
    $candidates += Get-ChildItem -Path (Join-Path $root 'Python*\python.exe') -File -ErrorAction SilentlyContinue
}
$candidates += Get-Item -LiteralPath (Join-Path $env:USERPROFILE 'miniconda3\python.exe') -ErrorAction SilentlyContinue
$candidates += Get-Item -LiteralPath (Join-Path $env:USERPROFILE 'anaconda3\python.exe') -ErrorAction SilentlyContinue

foreach ($candidate in ($candidates | Where-Object { $_ } | Sort-Object FullName -Descending -Unique)) {
    $valid = Test-PythonExe $candidate.FullName
    if ($valid) { $valid; exit 0 }
}

exit 1
