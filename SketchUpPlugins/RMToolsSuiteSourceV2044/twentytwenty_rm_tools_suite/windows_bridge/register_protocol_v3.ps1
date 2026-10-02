$ErrorActionPreference='Stop'
$dir=Join-Path $env:APPDATA '2020toolbox\SketchUpPluginInstaller'
$bat=Join-Path $dir '20-20_BRIDGE_V3.bat'
if(-not (Test-Path $bat)){throw "20-20_BRIDGE_V3.bat not found"}

# Use a tiny WScript launcher so custom-protocol clicks never leave a console window open.
$vbs=Join-Path $dir 'launch_bridge_v3.vbs'
$safeBat=$bat.Replace('"','""')
$vbsText=@"
Set sh = CreateObject("WScript.Shell")
bat = "$safeBat"
arg = ""
If WScript.Arguments.Count > 0 Then arg = WScript.Arguments(0)
cmd = """" & bat & """ """ & arg & """"
sh.Run cmd, 0, False
"@
Set-Content -Path $vbs -Value $vbsText -Encoding ASCII

$key='HKCU:\Software\Classes\twentytwentytoolboxv3'
if(Test-Path $key){Remove-Item $key -Recurse -Force}
New-Item $key -Force|Out-Null
Set-Item $key -Value 'URL:20-20 Toolbox SketchUp Bridge V3'
New-ItemProperty $key -Name 'URL Protocol' -Value '' -PropertyType String -Force|Out-Null
$cmd=Join-Path $key 'shell\open\command'
New-Item $cmd -Force|Out-Null
$wscript=Join-Path $env:WINDIR 'System32\wscript.exe'
Set-Item $cmd -Value ('"'+$wscript+'" "'+$vbs+'" "%1"')
