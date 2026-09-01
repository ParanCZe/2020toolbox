@echo off
cd /d "%~dp0"
echo Spoustim lokalni server na portu 8090...
start http://localhost:8090/index.html
powershell -Command "$listener = New-Object System.Net.HttpListener; $listener.Prefixes.Add('http://localhost:8090/'); $listener.Start(); while ($listener.IsListening) { $context = $listener.GetContext(); $path = Join-Path (Get-Location) $context.Request.Url.LocalPath.TrimStart('/'); if (Test-Path -PathType Leaf $path) { $bytes = [System.IO.File]::ReadAllBytes($path); if ($path.EndsWith('.html')) { $context.Response.ContentType = 'text/html' } elseif ($path.EndsWith('.js')) { $context.Response.ContentType = 'application/javascript' } elseif ($path.EndsWith('.wasm')) { $context.Response.ContentType = 'application/wasm' } $context.Response.ContentLength64 = $bytes.Length; $context.Response.OutputStream.Write($bytes, 0, $bytes.Length); } else { $context.Response.StatusCode = 404 }; $context.Response.OutputStream.Close() }"
pause