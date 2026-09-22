$ErrorActionPreference = 'Stop'
$installDir = Join-Path $env:APPDATA '2020toolbox\SketchUpPluginInstaller'
$handlerBat = Join-Path $installDir '20-20_PLUGIN_INSTALLER.bat'
if (-not (Test-Path $handlerBat)) { throw "Instalační pomocník nebyl nalezen: $handlerBat" }

$protocol = 'HKCU:\Software\Classes\twentytwentytoolbox'
New-Item -Path $protocol -Force | Out-Null
Set-Item -Path $protocol -Value 'URL:20-20 Toolbox Plugin Installer'
New-ItemProperty -Path $protocol -Name 'URL Protocol' -Value '' -PropertyType String -Force | Out-Null

$commandKey = Join-Path $protocol 'shell\open\command'
New-Item -Path $commandKey -Force | Out-Null
Set-Item -Path $commandKey -Value ('"' + $handlerBat + '" "%1"')
