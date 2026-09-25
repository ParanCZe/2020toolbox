param(
    [string]$PythonExe,
    [string]$BridgeScript,
    [string]$LogFile
) 

$ErrorActionPreference = 'SilentlyContinue'

# Never kill an arbitrary process merely because it owns port 8094.
# Only stop a listener if it is one of our AuthorizationBridge Python processes.
try {
    $owners = Get-NetTCPConnection -LocalPort 8094 -State Listen -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty OwningProcess -Unique
    foreach ($pidValue in $owners) {
        if (-not $pidValue -or $pidValue -eq $PID) { continue }
        $procInfo = Get-CimInstance Win32_Process -Filter "ProcessId = $pidValue" -ErrorAction SilentlyContinue
        if ($procInfo -and $procInfo.CommandLine -and $procInfo.CommandLine -like '*authorization_bridge.py*') {
            Stop-Process -Id $pidValue -Force -ErrorAction SilentlyContinue
        } else {
            Write-Error "Port 8094 pouziva jiny proces. Z bezpecnostnich duvodu ho AuthorizationBridge nebude ukoncovat."
            exit 1
        }
    }
} catch {
    Write-Error "Nepodarilo se bezpecne overit vlastnika portu 8094."
    exit 1
}

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

# Preflight: catch syntax/import errors before launching the hidden process.
$preflightOut = [System.IO.Path]::ChangeExtension($LogFile, '.preflight.log')
& $PythonExe -c "import runpy; runpy.run_path(r'$BridgeScript', run_name='__bridge_preflight__')" *> $preflightOut
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "CHYBA PRI NACTENI AUTHORIZATION BRIDGE:" -ForegroundColor Red
    if (Test-Path -LiteralPath $preflightOut) {
        Get-Content -LiteralPath $preflightOut -ErrorAction SilentlyContinue | Select-Object -Last 80
    }
    exit 1
}

Start-Process -FilePath $PythonExe -ArgumentList @($BridgeScript) -WorkingDirectory $workDir -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr

# pyHanko + cryptography can take several seconds to import on some PCs.
# Poll the health endpoint instead of assuming the process is ready after 900 ms.
$lastError = $null
for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Seconds 1
    try {
        $r = Invoke-RestMethod -Uri 'http://127.0.0.1:8094/status' -TimeoutSec 2
        if ($r.ok) {
            Write-Output ("AuthorizationBridge " + $r.version + " running")
            exit 0
        }
    } catch {
        $lastError = $_
    }

    # If the Python process already exited, no reason to wait the full 20 s.
    $running = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine -like '*authorization_bridge.py*' }
    if (-not $running) { break }
}

Write-Host ""
Write-Host "AuthorizationBridge se nespustil." -ForegroundColor Red
if (Test-Path -LiteralPath $stderr) {
    $errLines = Get-Content -LiteralPath $stderr -ErrorAction SilentlyContinue
    if ($errLines) {
        Write-Host "---- bridge.error.log ----" -ForegroundColor Yellow
        $errLines | Select-Object -Last 100
    }
}
if (Test-Path -LiteralPath $stdout) {
    $outLines = Get-Content -LiteralPath $stdout -ErrorAction SilentlyContinue
    if ($outLines) {
        Write-Host "---- bridge.log ----" -ForegroundColor Yellow
        $outLines | Select-Object -Last 60
    }
}
if ($lastError) {
    Write-Host ("Health-check: " + $lastError.Exception.Message)
}
Write-Error "AuthorizationBridge did not start correctly."
exit 1
