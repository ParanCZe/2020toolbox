$ErrorActionPreference='Stop'
$installDir=Join-Path $env:APPDATA '2020toolbox\SketchUpPluginInstaller'
$handler=Join-Path $installDir '20-20_PLUGIN_INSTALLER_V2.bat'
if(-not (Test-Path $handler)){throw "Helper V2 nebyl nalezen: $handler"}

$protocol='HKCU:\Software\Classes\twentytwentytoolboxv2'
if(Test-Path $protocol){Remove-Item $protocol -Recurse -Force}
New-Item -Path $protocol -Force | Out-Null
Set-Item -Path $protocol -Value 'URL:20-20 Toolbox Plugin Installer V2'
New-ItemProperty -Path $protocol -Name 'URL Protocol' -Value '' -PropertyType String -Force | Out-Null
$commandKey=Join-Path $protocol 'shell\open\command'
New-Item -Path $commandKey -Force | Out-Null
Set-Item -Path $commandKey -Value ('"' + $handler + '" "%1"')
