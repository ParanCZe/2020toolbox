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
 $json=$obj|ConvertTo-Json -Depth 8 -Compress;$body=[Text.Encoding]::UTF8.GetBytes($json);$status=if($code -eq 200){'OK'}elseif($code -eq 204){'No Content'}else{'Error'}
 $head="HTTP/1.1 $code $status`r`nContent-Type: application/json; charset=utf-8`r`nAccess-Control-Allow-Origin: *`r`nAccess-Control-Allow-Private-Network: true`r`nAccess-Control-Allow-Methods: GET, POST, OPTIONS`r`nAccess-Control-Allow-Headers: Content-Type`r`nCache-Control: no-store`r`nContent-Length: $($body.Length)`r`nConnection: close`r`n`r`n"
 $hb=[Text.Encoding]::ASCII.GetBytes($head);$s.Write($hb,0,$hb.Length);if($body.Length){$s.Write($body,0,$body.Length)};$s.Flush()
}
while([DateTime]::UtcNow -lt $expires){
 if(-not $listener.Pending()){Start-Sleep -Milliseconds 80;continue};$client=$listener.AcceptTcpClient();$s=$client.GetStream()
 try{
  $reader=New-Object IO.StreamReader($s,[Text.Encoding]::ASCII,$false,1024,$true);$first=$reader.ReadLine();if(-not $first){continue};$parts=$first.Split(' ');$method=$parts[0];$path=$parts[1];$len=0
  while($true){$h=$reader.ReadLine();if([string]::IsNullOrEmpty($h)){break};if($h -match '^(?i)Content-Length:\s*(\d+)'){$len=[int]$Matches[1]}}
  if($method -eq 'OPTIONS'){Reply $s 204 @{};continue}
  if($method -eq 'GET' -and $path.StartsWith('/status')){$left=[Math]::Max(0,[int][Math]::Ceiling(($expires-[DateTime]::UtcNow).TotalSeconds));Reply $s 200 @{ok=$true;sketchup=$su.Name;remaining_seconds=$left;installed=(Get-Installed $su.Plugins)};continue}
  if($method -eq 'POST' -and $path.StartsWith('/install')){
   $file='plugin.rbz';if($path -match '[?&]file=([^&]+)'){$file=[Uri]::UnescapeDataString($Matches[1])};if($file -notmatch '^[A-Za-z0-9._-]+\.rbz$'){Reply $s 400 @{ok=$false;error='Invalid RBZ'};continue}
   $body=New-Object byte[] $len;$off=0;while($off -lt $len){$n=$s.Read($body,$off,$len-$off);if($n -le 0){break};$off+=$n}
   $tmp=Join-Path $env:TEMP ('2020toolbox_post_'+[Guid]::NewGuid().ToString('N'));$rbz=Join-Path $tmp $file;$ext=Join-Path $tmp 'extract';New-Item -ItemType Directory -Force -Path $ext|Out-Null;[IO.File]::WriteAllBytes($rbz,$body);[IO.Compression.ZipFile]::ExtractToDirectory($rbz,$ext)
   foreach($item in Get-ChildItem $ext -Force){if($item.Name -eq '__MACOSX'){continue};if($item.PSIsContainer){$dst=Join-Path $su.Plugins $item.Name;if(Test-Path $dst){Remove-Item $dst -Recurse -Force};Copy-Item $item.FullName $dst -Recurse -Force}elseif($item.Extension.ToLowerInvariant() -eq '.rb'){Copy-Item $item.FullName (Join-Path $su.Plugins $item.Name) -Force}}
   Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue;Reply $s 200 @{ok=$true;sketchup=$su.Name;installed=(Get-Installed $su.Plugins)};continue
  }
  Reply $s 404 @{ok=$false;error='Unknown endpoint'}
 }catch{Log ('SERVER ERROR '+$_.Exception.Message);try{Reply $s 500 @{ok=$false;error=$_.Exception.Message}}catch{}}finally{$s.Close();$client.Close()}
}
$listener.Stop();Log 'BRIDGE STOP'