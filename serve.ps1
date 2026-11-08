param([switch]$NoOpen)

# Minimal static file server for the teleprompter (loopback only, no admin needed).
# Serving over http://127.0.0.1 makes the browser REMEMBER the microphone permission,
# which is impossible with file:// (that is why Chrome keeps asking during reading).

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$port = 8765

$page = ''
$best = $null; $bestv = -1
foreach ($f in (Get-ChildItem -Path $root -Filter 'index-v*.html' -ErrorAction SilentlyContinue)) {
  if ($f.Name -match 'index-v(\d+)\.(\d+)\.html') {
    $v = [int]$Matches[1] * 1000 + [int]$Matches[2]
    if ($v -gt $bestv) { $bestv = $v; $best = $f.Name }
  }
}
if ($best) { $page = $best }
elseif (Test-Path (Join-Path $root 'index.html')) { $page = 'index.html' }
if ($page -eq '') { Write-Host 'index.html not found next to this script.'; Read-Host; exit 1 }

$url = "http://127.0.0.1:$port/$page"
$listener = $null
try {
  $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $port)
  $listener.Start()
} catch {
  # Port already taken -> most likely our own server is already running, just open it.
  Write-Host "Port $port is already in use, opening $url"
  if (-not $NoOpen) { Start-Process $url }
  Start-Sleep -Seconds 2
  exit 0
}

Write-Host "======================================================"
Write-Host " Teleprompter is running:  $url"
Write-Host " First time: click Allow for the microphone."
Write-Host " The browser will remember it - no more popups later."
Write-Host " Keep this window open while reading. Close it to stop."
Write-Host "======================================================"
if (-not $NoOpen) { Start-Process $url }

$mime = @{ '.html'='text/html; charset=utf-8'; '.htm'='text/html; charset=utf-8';
           '.js'='application/javascript; charset=utf-8'; '.css'='text/css; charset=utf-8';
           '.png'='image/png'; '.jpg'='image/jpeg'; '.jpeg'='image/jpeg'; '.svg'='image/svg+xml';
           '.json'='application/json; charset=utf-8'; '.txt'='text/plain; charset=utf-8' }

while ($true) {
  $client = $null
  try {
    $client = $listener.AcceptTcpClient()
    $stream = $client.GetStream()
    $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::ASCII, $false, 8192, $true)
    $reqLine = $reader.ReadLine()
    if (!$reqLine) { $client.Close(); continue }
    while ($true) { $h = $reader.ReadLine(); if ($null -eq $h -or $h -eq '') { break } }

    $parts = $reqLine.Split(' ')
    $path = if ($parts.Length -ge 2) { $parts[1] } else { '/' }
    $path = $path.Split('?')[0]
    if ($path -eq '/') { $path = '/' + $page }
    $rel = [System.Uri]::UnescapeDataString($path).TrimStart('/')
    $file = Join-Path $root $rel
    $full = [System.IO.Path]::GetFullPath($file)
    $okPath = $full.StartsWith([System.IO.Path]::GetFullPath($root), [System.StringComparison]::OrdinalIgnoreCase)

    if ($okPath -and (Test-Path $full -PathType Leaf)) {
      $bytes = [System.IO.File]::ReadAllBytes($full)
      $ext = [System.IO.Path]::GetExtension($full).ToLower()
      $ct = if ($mime.ContainsKey($ext)) { $mime[$ext] } else { 'application/octet-stream' }
      $head = "HTTP/1.1 200 OK`r`nContent-Type: $ct`r`nContent-Length: $($bytes.Length)`r`nCache-Control: no-store`r`nConnection: close`r`n`r`n"
      $hb = [System.Text.Encoding]::ASCII.GetBytes($head)
      $stream.Write($hb, 0, $hb.Length)
      $stream.Write($bytes, 0, $bytes.Length)
    } else {
      $body = [System.Text.Encoding]::UTF8.GetBytes('not found')
      $head = "HTTP/1.1 404 Not Found`r`nContent-Type: text/plain; charset=utf-8`r`nContent-Length: $($body.Length)`r`nConnection: close`r`n`r`n"
      $hb = [System.Text.Encoding]::ASCII.GetBytes($head)
      $stream.Write($hb, 0, $hb.Length)
      $stream.Write($body, 0, $body.Length)
    }
    $stream.Flush()
    $client.Close()
  } catch {
    if ($client) { try { $client.Close() } catch {} }
  }
}
