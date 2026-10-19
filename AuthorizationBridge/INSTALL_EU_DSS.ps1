# 20-20 TOOLBOX: explicit one-click LOCAL EU DSS 6.5 installation.
# Downloads the original Windows demo bundle from the European Commission.
# No user files or certificate private keys are accessed or uploaded.
param()
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$version = '6.5'
$url = 'https://ec.europa.eu/digital-building-blocks/artifact/repository/esignaturedss/eu/europa/ec/joinup/sd-dss/dss-demo-bundle/6.5/dss-demo-bundle-6.5.zip'
$base = Join-Path $env:LOCALAPPDATA '20-20-TOOLBOX\EU-DSS'
$target = Join-Path $base $version
$stage = Join-Path $base '6.5-staging'
$archive = Join-Path $base 'dss-demo-bundle-6.5.zip'
$log = Join-Path $base 'install.log'
New-Item -ItemType Directory -Path $base -Force | Out-Null

function Log([string]$message) {
    ("[{0}] {1}" -f (Get-Date -Format s), $message) |
        Out-File -FilePath $log -Encoding UTF8 -Append
}
function Fail([string]$message) {
    Log ("ERROR: " + $message)
    throw $message
}

try {
    Log 'Starting official EU DSS 6.5 installation (approx. 630 MB).'
    if (Test-Path (Join-Path $target 'Webapp-Startup.bat')) {
        Log 'Already installed; not downloading again.'
        exit 0
    }
    if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
    if (-not (Test-Path $archive)) {
        Log ("Downloading bundle from " + $url)
        Invoke-WebRequest -Uri $url -UseBasicParsing -OutFile $archive -TimeoutSec 1800
    }

    # Repository publishes a digest alongside the downloaded artifact.
    # SHA-1 here is a transport integrity check, not a signature/trust anchor.
    # It must never be used to grant trust to PDF signatures or EU trust lists.
    $shaResponse = (Invoke-WebRequest -Uri ($url + '.sha1') -UseBasicParsing -TimeoutSec 45).Content
    $expected = ([regex]::Match([string]$shaResponse, '(?i)\b[a-f0-9]{40}\b')).Value.ToLowerInvariant()
    if ($expected.Length -ne 40) { Fail 'Cannot read official DSS archive checksum.' }
    $actual = (Get-FileHash -Algorithm SHA1 -Path $archive).Hash.ToLowerInvariant()
    if ($actual -ne $expected) {
        Remove-Item -Path $archive -Force -ErrorAction SilentlyContinue
        Fail 'DSS package digest mismatch. Removed downloaded archive.'
    }
    Log 'Archive digest verified against official artifact manifest.'

    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    Expand-Archive -LiteralPath $archive -DestinationPath $stage -Force
    # Maven archives may have one enclosing directory. Normalize its root.
    $start = Get-ChildItem -Path $stage -Filter 'Webapp-Startup.bat' -File -Recurse |
        Where-Object {
            $_.FullName.Substring($stage.Length).TrimStart([char]'\').Split([char]'\').Count -le 3
        } | Select-Object -First 1
    if (-not $start) { Fail 'DSS bundle does not contain Webapp-Startup.bat.' }
    $appRoot = $start.Directory.FullName
    $tomcat = Get-ChildItem $appRoot -Directory | Where-Object { $_.Name -like 'apache-tomcat-*' } | Select-Object -First 1
    if (-not $tomcat) { Fail 'Tomcat folder is missing in downloaded official DSS bundle.' }
    $serverXml = Join-Path $tomcat.FullName 'conf\server.xml'
    if (-not (Test-Path $serverXml)) { Fail 'Tomcat server.xml is missing.' }

    # Parse XML as XML. Never inject a new address attribute after '/>'
    # (the old installer generated an invalid <Connector ... / address=...>).
    # Keep the validation API bound to loopback and avoid collisions with 8080.
    $config = New-Object System.Xml.XmlDocument
    $config.PreserveWhitespace = $true
    $config.XmlResolver = $null
    $config.Load($serverXml)
    $matches = $config.SelectNodes('/Server/Service/Connector[@port="8080"]')
    if ($matches.Count -ne 1) { Fail 'Expected exactly one Tomcat HTTP Connector on port 8080.' }
    $matches.Item(0).SetAttribute('port', '18080')
    $matches.Item(0).SetAttribute('address', '127.0.0.1')
    $config.Save($serverXml)

    $verified = New-Object System.Xml.XmlDocument
    $verified.XmlResolver = $null
    $verified.Load($serverXml)
    $bound = $verified.SelectNodes('/Server/Service/Connector[@port="18080" and @address="127.0.0.1"]')
    if ($bound.Count -ne 1) { Fail 'Tomcat Connector did not retain localhost binding.' }
    Log 'Validated Tomcat server.xml and localhost-only Connector on port 18080.'

    # Move completed, verified, locally-restricted installation into place.
    if (Test-Path $target) { Remove-Item $target -Recurse -Force }
    if ($appRoot -eq $stage) {
        Move-Item -LiteralPath $stage -Destination $target
    } else {
        Move-Item -LiteralPath $appRoot -Destination $target
        Remove-Item -Path $stage -Recurse -Force
    }
    Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue
    Log 'SUCCESS: EU DSS installed. Starts on demand on loopback port 18080.'
    exit 0
}
catch {
    Log ("INSTALL FAILED: " + $_.Exception.Message)
    exit 1
}
