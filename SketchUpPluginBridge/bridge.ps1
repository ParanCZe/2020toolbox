$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$port=8092
$listener=[System.Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,$port)
try{$listener.Start()}catch{exit 0}
$expires=[DateTime]::UtcNow.AddMinutes(2)
function Latest-SketchUp {
  $root=Join-Path $env:APPDATA 'SketchUp'
  if(-not(Test-Path $root)){return $null}
  $dirs=Get-ChildItem $root -Directory -ErrorAction SilentlyContinue | Where-Object {$_.Name -match '^SketchUp\s+(\d{4})$'} | Sort-Object {[int]([regex]::Match($_.Name,'\d{4}').Value)} -Descending
  foreach($d in $dirs){$p=Join-Path $d.FullName 'SketchUp\Plugins';if(-not(Test-Path $p)){New-Item -ItemType Directory -Force -Path $p|Out-Null};return [pscustomobject]@{Name=$d.Name;Plugins=$p}}
  return $null
}
function Resp($stream,$code,$obj){
  $json=$obj|ConvertTo-Json -Depth 6 -Compress;$body=[Text.Encoding]::UTF8.GetBytes($json);$status=if($code -eq 200){'OK'}elseif($code -eq 204){'No Content'}else{'Error'}
  $h="HTTP/1.1 $code $status`r`nContent-Type: application/json; charset=utf-8`r`nAccess-Control-Allow-Origin: *`r`nAccess-Control-Allow-Methods: GET, POST, OPTIONS`r`nAccess-Control-Allow-Headers: Content-Type`r`nContent-Length: $($body.Length)`r`nConnection: close`r`n`r`n"
  $hb=[Text.Encoding]::ASCII.GetBytes($h);$stream.Write($hb,0,$hb.Length);if($body.Length){$stream.Write($body,0,$body.Length)};$stream.Flush()
}
while([DateTime]::UtcNow -lt $expires){
 if(-not $listener.Pending()){Start-Sleep -Milliseconds 80;continue}
 $client=$listener.AcceptTcpClient();$s=$client.GetStream()
 try{
  $reader=New-Object IO.StreamReader($s,[Text.Encoding]::ASCII,$false,1024,$true)
  $line=$reader.ReadLine();if(-not $line){continue};$parts=$line.Split(' ');$method=$parts[0];$path=$parts[1];$len=0
  while($true){$h=$reader.ReadLine();if([string]::IsNullOrEmpty($h)){break};if($h -match '^(?i)Content-Length:\s*(\d+)'){$len=[int]$Matches[1]}}
  if($method -eq 'OPTIONS'){Resp $s 204 @{};continue}
  $su=Latest-SketchUp
  if($method -eq 'GET' -and $path.StartsWith('/status')){if($null -eq $su){Resp $s 404 @{ok=$false;error='SketchUp not found'}}else{Resp $s 200 @{ok=$true;sketchup=$su.Name;remaining_seconds=[math]::Max(0,[int][math]::Ceiling(($expires-[DateTime]::UtcNow).TotalSeconds))}};continue}
  if($method -eq 'POST' -and $path.StartsWith('/install')){
   if($null -eq $su){Resp $s 404 @{ok=$false;error='SketchUp not found'};continue}
   $file='plugin.rbz';if($path -match '[?&]file=([^&]+)'){$file=[Uri]::UnescapeDataString($Matches[1])}
   if($file -notmatch '^[A-Za-z0-9._-]+\.rbz$'){Resp $s 400 @{ok=$false;error='Invalid RBZ'};continue}
   $body=New-Object byte[] $len;$off=0;while($off -lt $len){$n=$s.Read($body,$off,$len-$off);if($n -le 0){break};$off+=$n}
   $tmp=Join-Path $env:TEMP ('2020tb_'+[Guid]::NewGuid().ToString('N'));$ex=Join-Path $tmp 'x';New-Item -ItemType Directory -Force -Path $ex|Out-Null;$rbz=Join-Path $tmp $file;[IO.File]::WriteAllBytes($rbz,$body);[IO.Compression.ZipFile]::ExtractToDirectory($rbz,$ex)
   foreach($it in Get-ChildItem $ex -Force){if($it.Name -eq '__MACOSX'){continue};$target=Join-Path $su.Plugins $it.Name;if($it.PSIsContainer){if(Test-Path $target){Remove-Item $target -Recurse -Force};Copy-Item $it.FullName $target -Recurse -Force}elseif($it.Extension.ToLowerInvariant() -eq '.rb'){Copy-Item $it.FullName $target -Force}}
   Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue;Resp $s 200 @{ok=$true;sketchup=$su.Name};continue
  }
  Resp $s 404 @{ok=$false;error='Not found'}
 }catch{try{Resp $s 500 @{ok=$false;error=$_.Exception.Message}}catch{}}finally{$s.Close();$client.Close()}
}
$listener.Stop()