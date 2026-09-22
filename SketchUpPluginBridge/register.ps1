$ErrorActionPreference='Stop'
$dir=Join-Path $env:APPDATA '2020toolbox\SketchUpPluginBridge'
$bat=Join-Path $dir 'START_BRIDGE.bat'
$p='HKCU:\Software\Classes\twentytwentybridge'
if(Test-Path $p){Remove-Item $p -Recurse -Force}
New-Item $p -Force|Out-Null
Set-Item $p -Value 'URL:20-20 Toolbox SketchUp Bridge'
New-ItemProperty $p -Name 'URL Protocol' -Value '' -PropertyType String -Force|Out-Null
$c=Join-Path $p 'shell\open\command';New-Item $c -Force|Out-Null
Set-Item $c -Value ('"'+$bat+'" "%1"')