$ErrorActionPreference='Stop'
$dir=Join-Path $env:APPDATA '2020toolbox\SketchUpPluginInstaller'
$bat=Join-Path $dir '20-20_BRIDGE_V3.bat'
if(-not (Test-Path $bat)){throw "20-20_BRIDGE_V3.bat not found"}
$key='HKCU:\Software\Classes\twentytwentytoolboxv3'
if(Test-Path $key){Remove-Item $key -Recurse -Force}
New-Item $key -Force|Out-Null
Set-Item $key -Value 'URL:20-20 Toolbox SketchUp Bridge V3'
New-ItemProperty $key -Name 'URL Protocol' -Value '' -PropertyType String -Force|Out-Null
$cmd=Join-Path $key 'shell\open\command'
New-Item $cmd -Force|Out-Null
Set-Item $cmd -Value ('"'+$bat+'" "%1"')
