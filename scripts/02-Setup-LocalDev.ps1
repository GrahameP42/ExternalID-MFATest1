<#
.SYNOPSIS
    Set up local development environment for the passkey sample app.

.DESCRIPTION
    Performs local machine setup required before running the app:
      1. Adds auth.<tenant>.ciamlogin.com → 127.0.0.1 to the hosts file
      2. Generates a self-signed TLS certificate for that domain
      3. Exports auth-cert.pem + auth-key.pem to the project root
      4. Installs the certificate in the Trusted Root store (avoids browser warnings)
      5. Writes the .env file from supplied values

    Must be run as Administrator (needed for hosts file and certificate store).

.PARAMETER TenantSubdomain
    The subdomain of the CIAM tenant (e.g. "passkeytest2").

.PARAMETER TenantId
    GUID of the External ID tenant.

.PARAMETER ClientId
    Application (client) ID from the app registration.

.PARAMETER ClientSecret
    Client secret from the app registration.

.PARAMETER ProjectRoot
    Path to the ExternalID-Passkey-FreshTest2 folder. Defaults to the parent of this script.

.PARAMETER CertPassword
    Password used when exporting the PFX certificate (does not need to be remembered).

.EXAMPLE
    # Run as Administrator:
    .\02-Setup-LocalDev.ps1 `
        -TenantSubdomain "passkeytest2" `
        -TenantId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
        -ClientId "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy" `
        -ClientSecret "your-secret-here"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$TenantSubdomain,

    [Parameter(Mandatory)]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [string]$ClientId,

    [Parameter(Mandatory)]
    [string]$ClientSecret,

    [Parameter()]
    [string]$ProjectRoot = (Split-Path $PSScriptRoot -Parent),

    [Parameter()]
    [string]$CertPassword = 'DevCert@LocalPasskeyTest1'
)

$ErrorActionPreference = 'Stop'

# Validate running as admin
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "This script must be run as Administrator. Right-click PowerShell → 'Run as administrator'."
}

$CiamDomain    = "${TenantSubdomain}.ciamlogin.com"
$AuthDomain    = "auth.${CiamDomain}"
$Port          = 3000
$HostsFile     = "C:\Windows\System32\drivers\etc\hosts"
$CertStorePath = "cert:\LocalMachine\My"
$RootStorePath = "cert:\LocalMachine\Root"
$PfxPath       = Join-Path $ProjectRoot "auth-cert.pfx"
$PemCertPath   = Join-Path $ProjectRoot "auth-cert.pem"
$PemKeyPath    = Join-Path $ProjectRoot "auth-key.pem"

function Write-Step { param([string]$Msg) Write-Host "`n$Msg" -ForegroundColor Yellow }
function Write-OK   { param([string]$Msg) Write-Host "  $Msg" -ForegroundColor Green }
function Write-Skip { param([string]$Msg) Write-Host "  $Msg" -ForegroundColor Gray }

Write-Host "=== Local Dev Setup for Passkey Sample ===" -ForegroundColor Cyan
Write-Host "Auth domain : $AuthDomain" -ForegroundColor Gray
Write-Host "Project root: $ProjectRoot" -ForegroundColor Gray

# -------------------------------------------------------------------------
# 1. Hosts file entry
# -------------------------------------------------------------------------
Write-Step "[1/5] Updating Windows hosts file..."

$hostsContent = Get-Content $HostsFile -Raw
if ($hostsContent -match [regex]::Escape($AuthDomain)) {
    Write-Skip "Entry already present: 127.0.0.1  $AuthDomain"
} else {
    Add-Content -Path $HostsFile -Value "`n127.0.0.1    $AuthDomain" -Encoding ASCII
    Write-OK "Added: 127.0.0.1  $AuthDomain"
}

# -------------------------------------------------------------------------
# 2. Generate self-signed certificate
# -------------------------------------------------------------------------
Write-Step "[2/5] Generating self-signed TLS certificate for $AuthDomain..."

# Remove old certificate if present
Get-ChildItem $CertStorePath | Where-Object { $_.Subject -eq "CN=$AuthDomain" } | Remove-Item -Force
Get-ChildItem $RootStorePath | Where-Object { $_.Subject -eq "CN=$AuthDomain" } | Remove-Item -Force

$cert = New-SelfSignedCertificate `
    -DnsName $AuthDomain `
    -CertStoreLocation $CertStorePath `
    -NotAfter (Get-Date).AddYears(1) `
    -FriendlyName "PasskeyFreshTest2-DevCert" `
    -KeyUsage DigitalSignature, KeyEncipherment `
    -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.1")

Write-OK "Certificate created: thumbprint=$($cert.Thumbprint)"

# -------------------------------------------------------------------------
# 3. Export PFX
# -------------------------------------------------------------------------
Write-Step "[3/5] Exporting certificate to PFX..."

$secPwd = ConvertTo-SecureString -String $CertPassword -Force -AsPlainText
Export-PfxCertificate -Cert $cert -FilePath $PfxPath -Password $secPwd | Out-Null
Write-OK "Exported: $PfxPath"

# -------------------------------------------------------------------------
# 4. Convert PFX → PEM using OpenSSL
# -------------------------------------------------------------------------
Write-Step "[4/5] Converting PFX to PEM format..."

$openssl = Get-Command openssl -ErrorAction SilentlyContinue
if ($null -eq $openssl) {
    # Try common Git-bundled OpenSSL locations
    $candidates = @(
        "C:\Program Files\Git\usr\bin\openssl.exe"
        "C:\Program Files (x86)\Git\usr\bin\openssl.exe"
        "$env:LOCALAPPDATA\Programs\Git\usr\bin\openssl.exe"
    )
    $openssl = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($null -eq $openssl) {
        throw "openssl not found. Install Git for Windows (includes OpenSSL) or add OpenSSL to PATH."
    }
    $opensslExe = $openssl
} else {
    $opensslExe = $openssl.Source
}

Write-Skip "Using OpenSSL: $opensslExe"

# Extract certificate (no private key)
& $opensslExe pkcs12 -in $PfxPath -out $PemCertPath -clcerts -nokeys -password "pass:$CertPassword" 2>$null
if ($LASTEXITCODE -ne 0) { throw "OpenSSL failed to extract certificate PEM" }
Write-OK "Certificate PEM: $PemCertPath"

# Extract private key (no certificate)
& $opensslExe pkcs12 -in $PfxPath -out $PemKeyPath -nocerts -nodes -password "pass:$CertPassword" 2>$null
if ($LASTEXITCODE -ne 0) { throw "OpenSSL failed to extract private key PEM" }
Write-OK "Private key PEM: $PemKeyPath"

# -------------------------------------------------------------------------
# 5. Install certificate in Trusted Root store
# -------------------------------------------------------------------------
Write-Step "[5/5] Installing certificate in Trusted Root store..."

Import-PfxCertificate -FilePath $PfxPath -CertStoreLocation $RootStorePath -Password $secPwd | Out-Null
Write-OK "Certificate installed — browsers will trust $AuthDomain"

# -------------------------------------------------------------------------
# Write .env file
# -------------------------------------------------------------------------
Write-Step "Writing .env file..."

$envPath = Join-Path $ProjectRoot ".env"
$envContent = @"
# Local dev hostname — matches the auth.<tenant>.ciamlogin.com entry in your hosts file
VITE_HOST=${AuthDomain}
VITE_PORT=${Port}

# Tenant / app registration values (from 01-Setup-Entra.ps1 output)
VITE_TENANT_ID=${TenantId}
VITE_CIAM_DOMAIN=${CiamDomain}
VITE_CLIENT_ID=${ClientId}

# SSL certificate filenames (generated by this script, placed at project root)
VITE_SSL_CERT=auth-cert.pem
VITE_SSL_KEY=auth-key.pem

# Client secret from the app registration (DO NOT COMMIT)
VITE_APP_SECRET=${ClientSecret}

# Optional: custom URL domain (leave empty to use ciamlogin.com rp.id)
VITE_CUSTOM_DOMAIN=
"@

Set-Content -Path $envPath -Value $envContent -Encoding UTF8
Write-OK "Wrote: $envPath"

# -------------------------------------------------------------------------
# Final summary
# -------------------------------------------------------------------------
Write-Host "`n`n========================================" -ForegroundColor Cyan
Write-Host "  Local dev setup complete!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "`nTo start the app:" -ForegroundColor Yellow
Write-Host "  1. Open a terminal in $ProjectRoot" -ForegroundColor White
Write-Host "  2. npm install" -ForegroundColor White
Write-Host "  3. npm run cors         (CORS proxy on port 3001)" -ForegroundColor White
Write-Host "  4. npm start            (Vite dev server on https://${AuthDomain}:${Port})" -ForegroundColor White
Write-Host "`nOpen: https://${AuthDomain}:${Port}" -ForegroundColor Cyan
