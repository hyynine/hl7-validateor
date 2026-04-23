param(
  [int]$Port = 8080
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$rootPath = [System.IO.Path]::GetFullPath($PSScriptRoot)

function Get-ContentType {
  param(
    [string]$Extension
  )

  $map = @{
    '.css'  = 'text/css; charset=utf-8'
    '.gif'  = 'image/gif'
    '.htm'  = 'text/html; charset=utf-8'
    '.html' = 'text/html; charset=utf-8'
    '.ico'  = 'image/x-icon'
    '.jpeg' = 'image/jpeg'
    '.jpg'  = 'image/jpeg'
    '.js'   = 'application/javascript; charset=utf-8'
    '.json' = 'application/json; charset=utf-8'
    '.map'  = 'application/json; charset=utf-8'
    '.png'  = 'image/png'
    '.svg'  = 'image/svg+xml'
    '.txt'  = 'text/plain; charset=utf-8'
    '.webp' = 'image/webp'
  }

  if ($map.ContainsKey($Extension)) {
    return $map[$Extension]
  }

  return 'application/octet-stream'
}

function Send-Response {
  param(
    [System.Net.Sockets.NetworkStream]$Stream,
    [int]$StatusCode,
    [string]$StatusText,
    [string]$ContentType,
    [byte[]]$Body = @(),
    [bool]$HeadOnly = $false
  )

  $headerText = @(
    ('HTTP/1.1 {0} {1}' -f $StatusCode, $StatusText)
    ('Content-Type: {0}' -f $ContentType)
    ('Content-Length: {0}' -f $Body.Length)
    'Connection: close'
    'Cache-Control: no-store'
    ''
    ''
  ) -join "`r`n"

  $headerBytes = [System.Text.Encoding]::UTF8.GetBytes($headerText)
  $Stream.Write($headerBytes, 0, $headerBytes.Length)

  if (-not $HeadOnly -and $Body.Length -gt 0) {
    $Stream.Write($Body, 0, $Body.Length)
  }
}

function Resolve-RequestPath {
  param(
    [string]$RawPath
  )

  $pathOnly = $RawPath.Split('?')[0]
  $decoded = [System.Uri]::UnescapeDataString($pathOnly)
  $trimmed = $decoded.TrimStart('/')

  if ([string]::IsNullOrWhiteSpace($trimmed)) {
    $trimmed = 'index.html'
  }

  $relativePath = $trimmed.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
  $fullPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($rootPath, $relativePath))

  if (-not $fullPath.StartsWith($rootPath, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Path traversal rejected.'
  }

  if (Test-Path -LiteralPath $fullPath -PathType Container) {
    $fullPath = [System.IO.Path]::Combine($fullPath, 'index.html')
  }

  return $fullPath
}

function Get-LanUrls {
  param(
    [int]$PortNumber
  )

  $urls = New-Object 'System.Collections.Generic.List[string]'
  [void]$urls.Add(('http://localhost:{0}/' -f $PortNumber))
  $addresses = @()

  try {
    $addresses = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
      Where-Object {
        $_.IPAddress -ne '127.0.0.1' -and
        -not $_.IPAddress.StartsWith('169.254.') -and
        $_.PrefixOrigin -ne 'WellKnown'
      } |
      Select-Object -ExpandProperty IPAddress -Unique)
  } catch {
  }

  if ($addresses.Count -eq 0) {
    $addresses = @(ipconfig |
      Select-String -Pattern 'IPv4[^:]*:\s*([0-9.]+)' |
      ForEach-Object { $_.Matches[0].Groups[1].Value } |
      Where-Object {
        $_ -ne '127.0.0.1' -and
        -not $_.StartsWith('169.254.')
      } |
      Select-Object -Unique)
  }

  if ($addresses.Count -eq 0) {
    Write-Warning 'Could not read LAN IP addresses automatically. Run ipconfig if needed.'
  } else {
    foreach ($address in $addresses) {
      [void]$urls.Add(('http://{0}:{1}/' -f $address, $PortNumber))
    }
  }

  return $urls
}

$listener = New-Object System.Net.Sockets.TcpListener ([System.Net.IPAddress]::Any, $Port)
$listener.Start()

Write-Host ''
Write-Host 'HL7 mobile access server started.' -ForegroundColor Green
Write-Host ('Root: {0}' -f $rootPath)
Write-Host ('Port: {0}' -f $Port)
Write-Host ''
Write-Host 'Open one of these URLs on your computer or phone:' -ForegroundColor Cyan
Get-LanUrls -PortNumber $Port | ForEach-Object {
  Write-Host ('  {0}' -f $_)
}
Write-Host ''
Write-Host 'Keep your phone and computer on the same Wi-Fi network.' -ForegroundColor Yellow
Write-Host 'If Windows Firewall prompts you, allow Private network access.' -ForegroundColor Yellow
Write-Host 'Press Ctrl + C to stop the server.' -ForegroundColor DarkGray
Write-Host ''

try {
  while ($true) {
    $client = $listener.AcceptTcpClient()

    try {
      $client.ReceiveTimeout = 5000
      $client.SendTimeout = 5000

      $stream = $client.GetStream()
      $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::ASCII, $false, 1024, $true)

      $requestLine = $reader.ReadLine()
      if ([string]::IsNullOrWhiteSpace($requestLine)) {
        continue
      }

      while ($true) {
        $headerLine = $reader.ReadLine()
        if ([string]::IsNullOrEmpty($headerLine)) {
          break
        }
      }

      $parts = $requestLine.Split(' ')
      if ($parts.Length -lt 2) {
        $body = [System.Text.Encoding]::UTF8.GetBytes('Bad Request')
        Send-Response -Stream $stream -StatusCode 400 -StatusText 'Bad Request' -ContentType 'text/plain; charset=utf-8' -Body $body
        continue
      }

      $method = $parts[0].ToUpperInvariant()
      $rawPath = $parts[1]
      $headOnly = ($method -eq 'HEAD')

      if ($method -ne 'GET' -and $method -ne 'HEAD') {
        $body = [System.Text.Encoding]::UTF8.GetBytes('Method Not Allowed')
        Send-Response -Stream $stream -StatusCode 405 -StatusText 'Method Not Allowed' -ContentType 'text/plain; charset=utf-8' -Body $body -HeadOnly $headOnly
        continue
      }

      try {
        $targetPath = Resolve-RequestPath -RawPath $rawPath
      } catch {
        $body = [System.Text.Encoding]::UTF8.GetBytes('Forbidden')
        Send-Response -Stream $stream -StatusCode 403 -StatusText 'Forbidden' -ContentType 'text/plain; charset=utf-8' -Body $body -HeadOnly $headOnly
        continue
      }

      if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
        $body = [System.Text.Encoding]::UTF8.GetBytes('Not Found')
        Send-Response -Stream $stream -StatusCode 404 -StatusText 'Not Found' -ContentType 'text/plain; charset=utf-8' -Body $body -HeadOnly $headOnly
        continue
      }

      $extension = [System.IO.Path]::GetExtension($targetPath).ToLowerInvariant()
      $contentType = Get-ContentType -Extension $extension
      $body = [System.IO.File]::ReadAllBytes($targetPath)

      Write-Host ('[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $rawPath)
      Send-Response -Stream $stream -StatusCode 200 -StatusText 'OK' -ContentType $contentType -Body $body -HeadOnly $headOnly
    } catch {
      try {
        $fallbackStream = $client.GetStream()
        $body = [System.Text.Encoding]::UTF8.GetBytes('Internal Server Error')
        Send-Response -Stream $fallbackStream -StatusCode 500 -StatusText 'Internal Server Error' -ContentType 'text/plain; charset=utf-8' -Body $body
      } catch {
      }
    } finally {
      $client.Dispose()
    }
  }
} finally {
  $listener.Stop()
}
