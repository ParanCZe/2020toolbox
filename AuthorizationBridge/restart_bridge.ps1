$ErrorActionPreference = 'SilentlyContinue'
param(
    [string]$PythonExe,
    [string]$BridgeScript,
    [string]$LogFile
)

# Kill any process that currently owns port 8094.
try {
    $owners = Get-NetTCPConnection -LocalPort 8094 -State Listen -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty OwningProcess -Unique
    foreach ($pidValue in $owners) {
        if ($pidValue -and $pidValue -ne $PID) {
            Stop-Process -Id $pidValue -Force -ErrorAction SilentlyContinue
        }
    }
} catch {}

# Also kill stale AuthorizationBridge python processes that may not currently be listening.
try {
    $procs = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine -like '*authorization_bridge.py*' }
    foreach ($proc in $procs) {
        if ($proc.ProcessId -and $proc.ProcessId -ne $PID) {
            Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
        }
    }
} catch {}

Start-Sleep -Milliseconds 700

if (-not (Test-Path -LiteralPath $PythonExe)) {
    Write-Error "Python executable not found: $PythonExe"
    exit 1
}
if (-not (Test-Path -LiteralPath $BridgeScript)) {
    Write-Error "Bridge script not found: $BridgeScript"
    exit 1
}

$workDir = Split-Path -Parent $BridgeScript
$stdout = $LogFile
$stderr = [System.IO.Path]::ChangeExtension($LogFile, '.error.log')

Start-Process -FilePath $PythonExe -ArgumentList @($BridgeScript) -WorkingDirectory $workDir -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
Start-Sleep -Milliseconds 900

try {
    $r = Invoke-RestMethod -Uri 'http://127.0.0.1:8094/status' -TimeoutSec 4
    if (-not $r.ok) { throw 'Bridge status returned not-ok' }
    Write-Output ("AuthorizationBridge " + $r.version + " running")
    exit 0
} catch {
    Write-Error "AuthorizationBridge did not start correctly. Check logs in $workDir"
    exit 1
}
