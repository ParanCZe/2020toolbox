param([string]$ProtocolUrl='')
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$helperDir=Join-Path $env:APPDATA '2020toolbox\SketchUpPluginInstaller'
$log=Join-Path $helperDir 'bridge_v3.log'
New-Item -ItemType Directory -Force -Path $helperDir|Out-Null
function Log([string]$m){try{Add-Content -Path $log -Value ((Get-Date -Format s)+' '+$m) -Encoding UTF8}catch{}}

# Self-update the local BAT. Existing V3 users therefore do NOT need to download the installer again.
$batPath=Join-Path $helperDir '20-20_BRIDGE_V3.bat'
$bat=@'
@echo off
setlocal
set "DIR=%APPDATA%\2020toolbox\SketchUpPluginInstaller"
set "PS1=%DIR%\bridge_v3.ps1"
set "URL=https://raw.githubusercontent.com/ParanCZe/2020toolbox/main/SketchUpPluginInstaller/bridge_v3.ps1"
if not exist "%DIR%" mkdir "%DIR%" >nul 2>&1
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "try { Invoke-WebRequest -UseBasicParsing -Uri '%URL%' -OutFile '%PS1%' } catch {}"
if not exist "%PS1%" exit /b 2
start "" powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%PS1%" "%~1"
exit /b 0
'@
try{Set-Content -Path $batPath -Value $bat -Encoding ASCII}catch{}

# Keep the custom URL protocol completely hidden. Existing V3 installs are migrated here automatically.
function Register-HiddenProtocol {
 try{
  $vbsPath=Join-Path $helperDir 'launch_bridge_v3.vbs'
  $safeBat=$batPath.Replace('"','""')
  $vbs=@"
Set sh = CreateObject("WScript.Shell")
bat = "$safeBat"
arg = ""
If WScript.Arguments.Count > 0 Then arg = WScript.Arguments(0)
cmd = """" & bat & """ """ & arg & """"
sh.Run cmd, 0, False
"@
  Set-Content -Path $vbsPath -Value $vbs -Encoding ASCII
  $key='HKCU:\Software\Classes\twentytwentytoolboxv3'
  New-Item $key -Force|Out-Null
  Set-Item $key -Value 'URL:20-20 Toolbox SketchUp Bridge V3'
  New-ItemProperty $key -Name 'URL Protocol' -Value '' -PropertyType String -Force|Out-Null
  $cmdKey=Join-Path $key 'shell\open\command';New-Item $cmdKey -Force|Out-Null
  $wscript=Join-Path $env:WINDIR 'System32\wscript.exe'
  Set-Item $cmdKey -Value ('"'+$wscript+'" "'+$vbsPath+'" "%1"')
 }catch{Log ('PROTOCOL MIGRATION ERROR '+$_.Exception.Message)}
}
Register-HiddenProtocol

function Get-SketchUp {
 $root=Join-Path $env:APPDATA 'SketchUp';if(-not(Test-Path $root)){return $null}
 $dirs=Get-ChildItem $root -Directory -ErrorAction SilentlyContinue | Where-Object {$_.Name -match '^SketchUp\s+(\d{4})$'} | Sort-Object {[int]([regex]::Match($_.Name,'\d{4}').Value)} -Descending
 if(-not $dirs){return $null};$plugins=Join-Path $dirs[0].FullName 'SketchUp\Plugins';New-Item -ItemType Directory -Force -Path $plugins|Out-Null
 [pscustomobject]@{Name=$dirs[0].Name;Plugins=$plugins}
}
function Get-Installed($plugins){
 $names=@('twentytwenty_live_mirror.rb','twentytwenty_nano_banana_exporter.rb','twentytwenty_model_library.rb','twentytwenty_texture_library.rb');$out=@{}
 foreach($name in $names){$p=Join-Path $plugins $name;if(Test-Path $p){$txt=Get-Content $p -Raw -ErrorAction SilentlyContinue;$m=[regex]::Match($txt,'(?im)(?:EXTENSION|extension)\.version\s*=\s*[''\"]([^''\"]+)[''\"]');if($m.Success){$out[$name]=$m.Groups[1].Value}else{$out[$name]='?'}}};$out
}
function Install-Rbz([string]$file,$su){
 Log ('INSTALL '+$file+' -> '+$su.Plugins)
 $index=(Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/ParanCZe/2020toolbox/main/index.html' -Headers @{'Cache-Control'='no-cache'}).Content
 $pattern='"'+[regex]::Escape($file)+'":"([^"]+)"';$m=[regex]::Match($index,$pattern)
 if(-not $m.Success){throw ('RBZ '+$file+' nebylo v Toolboxu nalezeno.')}
 $bytes=[Convert]::FromBase64String($m.Groups[1].Value)
 $tmp=Join-Path $env:TEMP ('2020toolbox_'+[Guid]::NewGuid().ToString('N'));$rbz=Join-Path $tmp $file;$ext=Join-Path $tmp 'extract';New-Item -ItemType Directory -Force -Path $ext|Out-Null;[IO.File]::WriteAllBytes($rbz,$bytes);[IO.Compression.ZipFile]::ExtractToDirectory($rbz,$ext)
 foreach($item in Get-ChildItem $ext -Force){if($item.Name -eq '__MACOSX'){continue};if($item.PSIsContainer){$dst=Join-Path $su.Plugins $item.Name;if(Test-Path $dst){Remove-Item $dst -Recurse -Force};Copy-Item $item.FullName $dst -Recurse -Force}elseif($item.Extension.ToLowerInvariant() -eq '.rb'){Copy-Item $item.FullName (Join-Path $su.Plugins $item.Name) -Force}}
 Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue;Log ('INSTALLED '+$file)
}

$su=Get-SketchUp
if($null -eq $su){Log 'SketchUp not found';exit 3}
$requested=$null
if($ProtocolUrl){$decoded=[Uri]::UnescapeDataString($ProtocolUrl);$m=[regex]::Match($decoded,'(?i)([A-Za-z0-9._-]+\.rbz)');if($m.Success){$requested=$m.Groups[1].Value}}
if($requested){try{Install-Rbz $requested $su}catch{Log ('DIRECT INSTALL ERROR '+$_.Exception.Message)}}

$port=8092;$listener=[System.Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,$port)
try{$listener.Start()}catch{Log 'Port 8092 already in use';exit 0}
$expires=[DateTime]::UtcNow.AddMinutes(2);Log ('BRIDGE START '+$ProtocolUrl)
function Reply($s,$code,$obj){
 $json=if($code -eq 204){''}else{$obj|ConvertTo-Json -Depth 8 -Compress};$body=[Text.Encoding]::UTF8.GetBytes($json);$status=if($code -eq 200){'OK'}elseif($code -eq 204){'No Content'}else{'Error'}
 $head="HTTP/1.1 $code $status`r`nContent-Type: application/json; charset=utf-8`r`nAccess-Control-Allow-Origin: *`r`nAccess-Control-Allow-Private-Network: true`r`nAccess-Control-Allow-Methods: GET, POST, OPTIONS`r`nAccess-Control-Allow-Headers: Content-Type`r`nCache-Control: no-store`r`nContent-Length: $($body.Length)`r`nConnection: close`r`n`r`n"
 $hb=[Text.Encoding]::ASCII.GetBytes($head);$s.Write($hb,0,$hb.Length);if($body.Length){$s.Write($body,0,$body.Length)};$s.Flush()
}
function Read-RequestHead($s){
 # Read only through CRLFCRLF directly from the NetworkStream. Do NOT mix StreamReader
 # with raw stream reads: StreamReader can pre-buffer part of the RBZ body and make POST hang forever.
 $bytes=New-Object System.Collections.Generic.List[byte]
 while($bytes.Count -lt 65536){
  $b=$s.ReadByte();if($b -lt 0){break};$bytes.Add([byte]$b)
  $n=$bytes.Count
  if($n -ge 4 -and $bytes[$n-4] -eq 13 -and $bytes[$n-3] -eq 10 -and $bytes[$n-2] -eq 13 -and $bytes[$n-1] -eq 10){break}
 }
 if($bytes.Count -lt 4){return $null}
 $txt=[Text.Encoding]::ASCII.GetString($bytes.ToArray());$lines=$txt -split "`r`n";$first=$lines[0]
 if([string]::IsNullOrWhiteSpace($first)){return $null};$parts=$first.Split(' ');if($parts.Count -lt 2){return $null}
 $len=0;foreach($h in $lines){if($h -match '^(?i)Content-Length:\s*(\d+)'){$len=[int]$Matches[1]}}
 [pscustomobject]@{Method=$parts[0];Path=$parts[1];ContentLength=$len}
}
while([DateTime]::UtcNow -lt $expires){
 if(-not $listener.Pending()){Start-Sleep -Milliseconds 80;continue};$client=$listener.AcceptTcpClient();$s=$client.GetStream();$s.ReadTimeout=15000;$s.WriteTimeout=15000
 try{
  $req=Read-RequestHead $s;if($null -eq $req){continue};$method=$req.Method;$path=$req.Path;$len=$req.ContentLength
  if($method -eq 'OPTIONS'){Reply $s 204 @{};continue}
  if($method -eq 'GET' -and $path.StartsWith('/status')){$left=[Math]::Max(0,[int][Math]::Ceiling(($expires-[DateTime]::UtcNow).TotalSeconds));Reply $s 200 @{ok=$true;sketchup=$su.Name;remaining_seconds=$left;installed=(Get-Installed $su.Plugins)};continue}
  if($method -eq 'POST' -and $path.StartsWith('/install')){
   $file='plugin.rbz';if($path -match '[?&]file=([^&]+)'){$file=[Uri]::UnescapeDataString($Matches[1])};if($file -notmatch '^[A-Za-z0-9._-]+\.rbz$'){Reply $s 400 @{ok=$false;error='Invalid RBZ'};continue}
   if($len -le 0){Reply $s 400 @{ok=$false;error='Empty RBZ body'};continue}
   $body=New-Object byte[] $len;$off=0;while($off -lt $len){$n=$s.Read($body,$off,$len-$off);if($n -le 0){break};$off+=$n}
   if($off -ne $len){Reply $s 400 @{ok=$false;error=('Incomplete RBZ body '+$off+'/'+$len)};continue}
   $tmp=Join-Path $env:TEMP ('2020toolbox_post_'+[Guid]::NewGuid().ToString('N'));$rbz=Join-Path $tmp $file;$ext=Join-Path $tmp 'extract';New-Item -ItemType Directory -Force -Path $ext|Out-Null;[IO.File]::WriteAllBytes($rbz,$body);[IO.Compression.ZipFile]::ExtractToDirectory($rbz,$ext)
   foreach($item in Get-ChildItem $ext -Force){if($item.Name -eq '__MACOSX'){continue};if($item.PSIsContainer){$dst=Join-Path $su.Plugins $item.Name;if(Test-Path $dst){Remove-Item $dst -Recurse -Force};Copy-Item $item.FullName $dst -Recurse -Force}elseif($item.Extension.ToLowerInvariant() -eq '.rb'){Copy-Item $item.FullName (Join-Path $su.Plugins $item.Name) -Force}}
   Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue;Log ('POST INSTALLED '+$file);Reply $s 200 @{ok=$true;sketchup=$su.Name;installed=(Get-Installed $su.Plugins)};continue
  }
  Reply $s 404 @{ok=$false;error='Unknown endpoint'}
 }catch{Log ('SERVER ERROR '+$_.Exception.Message);try{Reply $s 500 @{ok=$false;error=$_.Exception.Message}}catch{}}finally{try{$s.Close()}catch{};try{$client.Close()}catch{}}
}
$listener.Stop();Log 'BRIDGE STOP'