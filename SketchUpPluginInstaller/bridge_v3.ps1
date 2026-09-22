$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$port=8092
$prefix="http://127.0.0.1:$port/"
$expires=(Get-Date).ToUniversalTime().AddMinutes(2)

function Get-SketchUp {
  $root=Join-Path $env:APPDATA 'SketchUp'
  if(-not (Test-Path $root)){return $null}
  $dirs=Get-ChildItem $root -Directory -ErrorAction SilentlyContinue |
    Where-Object {$_.Name -match '^SketchUp\s+(\d{4})$'} |
    Sort-Object {[int]([regex]::Match($_.Name,'\d{4}').Value)} -Descending
  if(-not $dirs){return $null}
  $plugins=Join-Path $dirs[0].FullName 'SketchUp\Plugins'
  New-Item -ItemType Directory -Force -Path $plugins | Out-Null
  [pscustomobject]@{Name=$dirs[0].Name;Plugins=$plugins}
}
function Get-Installed($plugins) {
  $names=@(
    'twentytwenty_live_mirror.rb',
    'twentytwenty_nano_banana_exporter.rb',
    'twentytwenty_model_library.rb',
    'twentytwenty_texture_library.rb'
  )
  $out=@{}
  foreach($name in $names){
    $p=Join-Path $plugins $name
    if(Test-Path $p){
      $txt=Get-Content $p -Raw -ErrorAction SilentlyContinue
      $m=[regex]::Match($txt,'(?im)(?:EXTENSION|extension)\.version\s*=\s*[''"]([^''"]+)[''"]')
      if($m.Success){$out[$name]=$m.Groups[1].Value}else{$out[$name]='?'}
    }
  }
  $out
}
function Reply($ctx,$code,$obj){
  $json=$obj|ConvertTo-Json -Depth 8 -Compress
  $bytes=[Text.Encoding]::UTF8.GetBytes($json)
  $ctx.Response.StatusCode=$code
  $ctx.Response.ContentType='application/json; charset=utf-8'
  $ctx.Response.Headers['Access-Control-Allow-Origin']='*'
  $ctx.Response.Headers['Access-Control-Allow-Methods']='GET, POST, OPTIONS'
  $ctx.Response.Headers['Access-Control-Allow-Headers']='Content-Type'
  $ctx.Response.ContentLength64=$bytes.Length
  $ctx.Response.OutputStream.Write($bytes,0,$bytes.Length)
  $ctx.Response.OutputStream.Close()
}

$listener=New-Object Net.HttpListener
$listener.Prefixes.Add($prefix)
try{$listener.Start()}catch{exit 0}

try{
  while($listener.IsListening -and (Get-Date).ToUniversalTime() -lt $expires){
    $task=$listener.GetContextAsync()
    while(-not $task.IsCompleted -and (Get-Date).ToUniversalTime() -lt $expires){Start-Sleep -Milliseconds 100}
    if((Get-Date).ToUniversalTime() -ge $expires){break}
    $ctx=$task.GetAwaiter().GetResult()
    try{
      $req=$ctx.Request
      if($req.HttpMethod -eq 'OPTIONS'){
        $ctx.Response.StatusCode=204
        $ctx.Response.Headers['Access-Control-Allow-Origin']='*'
        $ctx.Response.Headers['Access-Control-Allow-Methods']='GET, POST, OPTIONS'
        $ctx.Response.Headers['Access-Control-Allow-Headers']='Content-Type'
        $ctx.Response.Close();continue
      }
      $su=Get-SketchUp
      if($null -eq $su){Reply $ctx 404 @{ok=$false;error='SketchUp not found'};continue}

      if($req.HttpMethod -eq 'GET' -and $req.Url.AbsolutePath -eq '/status'){
        $left=[Math]::Max(0,[int][Math]::Ceiling(($expires-(Get-Date).ToUniversalTime()).TotalSeconds))
        Reply $ctx 200 @{ok=$true;sketchup=$su.Name;remaining_seconds=$left;installed=(Get-Installed $su.Plugins)}
        continue
      }

      if($req.HttpMethod -eq 'POST' -and $req.Url.AbsolutePath -eq '/install'){
        $file=[IO.Path]::GetFileName($req.QueryString['file'])
        if([string]::IsNullOrWhiteSpace($file) -or -not $file.ToLowerInvariant().EndsWith('.rbz')){
          Reply $ctx 400 @{ok=$false;error='Invalid RBZ'};continue
        }
        $tmp=Join-Path $env:TEMP ('2020toolbox_'+[Guid]::NewGuid().ToString('N'))
        $rbz=Join-Path $tmp $file
        $ext=Join-Path $tmp 'extract'
        New-Item -ItemType Directory -Force -Path $ext|Out-Null
        $fs=[IO.File]::Create($rbz)
        try{$req.InputStream.CopyTo($fs)}finally{$fs.Dispose()}
        [IO.Compression.ZipFile]::ExtractToDirectory($rbz,$ext)
        $copied=@()
        foreach($item in Get-ChildItem $ext -Force){
          if($item.Name -eq '__MACOSX'){continue}
          if($item.PSIsContainer){
            $dst=Join-Path $su.Plugins $item.Name
            if(Test-Path $dst){Remove-Item $dst -Recurse -Force}
            Copy-Item $item.FullName $dst -Recurse -Force
            $copied+=$item.Name
          }elseif($item.Extension.ToLowerInvariant() -eq '.rb'){
            Copy-Item $item.FullName (Join-Path $su.Plugins $item.Name) -Force
            $copied+=$item.Name
          }
        }
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        Reply $ctx 200 @{ok=$true;sketchup=$su.Name;copied=$copied;installed=(Get-Installed $su.Plugins)}
        continue
      }
      Reply $ctx 404 @{ok=$false;error='Unknown endpoint'}
    }catch{
      try{Reply $ctx 500 @{ok=$false;error=$_.Exception.Message}}catch{}
    }
  }
}finally{
  try{$listener.Stop()}catch{}
  try{$listener.Close()}catch{}
}