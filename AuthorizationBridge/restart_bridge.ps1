param(
    [string]$PythonExe,
    [string]$BridgeScript,
    [string]$LogFile,
    [string]$ExpectedVersion = "2.1.8"
)

$ErrorActionPreference = 'Stop'

function Get-Port8094Owner {
    try {
        return @(Get-NetTCPConnection -LocalPort 8094 -State Listen -ErrorAction Stop |
            Select-Object -ExpandProperty OwningProcess -Unique)
    } catch {
        return @()
    }
}

function Get-ProcessInfoSafe([int]$ProcessId) {
    try {
        return Get-CimInstance Win32_Process -Filter "ProcessId = $ProcessId" -ErrorAction Stop
    } catch {
        return $null
    }
}

# Stop only an existing AuthorizationBridge that actually owns port 8094.
$owners = @(Get-Port8094Owner)
foreach ($pidValue in $owners) {
    if (-not $pidValue -or $pidValue -eq $PID) { continue }
    $procInfo = Get-ProcessInfoSafe $pidValue
    if ($procInfo -and $procInfo.CommandLine -and $procInfo.CommandLine -like '*authorization_bridge.py*') {
        Stop-Process -Id $pidValue -Force -ErrorAction Stop
    } else {
        Write-Error "Port 8094 pouziva jiny proces (PID $pidValue). Z bezpecnostnich duvodu ho neukoncim."
        exit 1
    }
}

# Stop any stale AuthorizationBridge python process left from an older version.
$stale = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object {
        $_.ProcessId -ne $PID -and
        $_.CommandLine -and
        $_.CommandLine -like '*authorization_bridge.py*'
    })
foreach ($proc in $stale) {
    try { Stop-Process -Id $proc.ProcessId -Force -ErrorAction Stop } catch {}
}

# Wait until the port is really free. Never start a second bridge on top of an old one.
$portFree = $false
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Milliseconds 250
    $owners = @(Get-Port8094Owner)
    if ($owners.Count -eq 0) {
        $portFree = $true
        break
    }
}
if (-not $portFree) {
    $owners = @(Get-Port8094Owner)
    Write-Error ("Port 8094 se neuvolnil. PID: " + ($owners -join ', '))
    exit 1
}

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
$preflightOut = [System.IO.Path]::ChangeExtension($LogFile, '.preflight.log')

Remove-Item -LiteralPath $stdout,$stderr,$preflightOut -Force -ErrorAction SilentlyContinue

# Syntax/import preflight. Use a temporary .py file instead of Python -c.
# This avoids PowerShell/Start-Process quoting ambiguities completely.
$preflightErr = [System.IO.Path]::ChangeExtension($LogFile, '.preflight.error.log')
$preflightScript = Join-Path $workDir '__bridge_preflight__.py'
Remove-Item -LiteralPath $preflightErr,$preflightScript -Force -ErrorAction SilentlyContinue

$escapedBridge = $BridgeScript.Replace("'", "''")
$preflightCode = @"
import runpy
runpy.run_path(r'''$escapedBridge''', run_name='__bridge_preflight__')
"@
[System.IO.File]::WriteAllText(
    $preflightScript,
    $preflightCode,
    [System.Text.UTF8Encoding]::new($false)
)

try {
    $preflightProc = Start-Process -FilePath $PythonExe -ArgumentList @(
        $preflightScript
    ) -WorkingDirectory $workDir -WindowStyle Hidden -RedirectStandardOutput $preflightOut -RedirectStandardError $preflightErr -Wait -PassThru

    if ($preflightProc.ExitCode -ne 0) {
        Write-Host ""
        Write-Host "CHYBA PRI NACTENI AUTHORIZATION BRIDGE:" -ForegroundColor Red
        if (Test-Path -LiteralPath $preflightErr) {
            Get-Content -LiteralPath $preflightErr -ErrorAction SilentlyContinue | Select-Object -Last 120
        }
        if (Test-Path -LiteralPath $preflightOut) {
            Get-Content -LiteralPath $preflightOut -ErrorAction SilentlyContinue | Select-Object -Last 80
        }
        exit 1
    }
} finally {
    Remove-Item -LiteralPath $preflightScript -Force -ErrorAction SilentlyContinue
}

$newProc = Start-Process -FilePath $PythonExe -ArgumentList @($BridgeScript) -WorkingDirectory $workDir -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru

$lastError = $null
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 1

    if ($newProc.HasExited) {
        break
    }

    try {
        $r = Invoke-RestMethod -Uri 'http://127.0.0.1:8094/status' -TimeoutSec 2
        if ($r.ok -and [string]$r.version -eq [string]$ExpectedVersion) {
            Write-Output ("AuthorizationBridge " + $r.version + " running")
            exit 0
        }
        if ($r.ok -and [string]$r.version -ne [string]$ExpectedVersion) {
            $lastError = "Na portu 8094 odpovida neocekavana verze " + $r.version + ", ocekavana je " + $ExpectedVersion
        }
    } catch {
        $lastError = $_.Exception.Message
    }
}

Write-Host ""
Write-Host "AuthorizationBridge se nespustil ve verzi $ExpectedVersion." -ForegroundColor Red
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
        $outLines | Select-Object -Last 80
    }
}
if ($lastError) {
    Write-Host ("Health-check: " + $lastError)
}
try {
    if (-not $newProc.HasExited) {
        Stop-Process -Id $newProc.Id -Force -ErrorAction SilentlyContinue
    }
} catch {}
exit 1
