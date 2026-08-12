# Production Deployment Guide — Entra External ID Passkey App

**Template for deploying to a new client tenant**  
**Last Updated**: 2026-08-12

---

## 1. Prerequisites Checklist

### Azure Subscription
- [ ] Azure subscription linked to (or transferred to) the External ID tenant
- [ ] Contributor or Owner role on the subscription
- [ ] Resource providers registered: `Microsoft.Web`, `Microsoft.Network`, `Microsoft.Cdn`
- [ ] Static Web Apps standard SKU quota available in target region

### Domain
- [ ] Custom domain registered with a registrar (e.g. `yourdomain.com`)
- [ ] Ability to update nameserver (NS) and CNAME/TXT records at registrar
- [ ] Recommended: delegate DNS zone to Azure DNS for full automation

### Identity (CIAM Tenant)
- [ ] Microsoft Entra External ID tenant created
- [ ] Global Administrator role in the tenant
- [ ] Subscription transferred to / associated with the External ID tenant

### Tools
```powershell
az --version          # Azure CLI 2.50+
az extension add --name staticwebapp
az extension add --name front-door
node --version        # Node.js 18+
npm --version         # npm 9+
```

---

## 2. Resource Deployment Order

```
1. Azure DNS Zone (azddns.top or yourdomain.com)
   ↓
2. CIAM Tenant Configuration (domains, FIDO2 policy, CA policy)
   ↓
3. App Registration (client ID, SPA URIs, permissions)
   ↓
4. Azure Static Web Apps (Standard tier)
   ↓
5. Build + Deploy app (with env vars)
   ↓
6. Azure Front Door (Standard_AzureFrontDoor)
   ↓
7. DNS Records (CNAME + TXT for Front Door validation)
   ↓
8. Verify custom domain + SSL certificate
   ↓
9. Update app registration redirect URIs with production domain
   ↓
10. Set SWA API function environment variables
```

---

## 3. Azure DNS Zone

```powershell
$rg = "rg-passkey-production"
$location = "eastus2"
$domain = "yourdomain.com"
$loginSubdomain = "login"  # → login.yourdomain.com

# Create resource group
az group create --name $rg --location $location

# Create DNS zone
az network dns zone create --resource-group $rg --name $domain

# Get name servers (add these to your domain registrar):
az network dns zone show --resource-group $rg --name $domain `
  --query "nameServers" --output table
```

**Registrar action required**: Add the 4 Azure nameservers to your domain registrar's NS records. Propagation: 15 minutes to 48 hours.

---

## 4. CIAM Tenant: Domain + FIDO2 Configuration

```powershell
$tenantId = "<your-external-id-tenant-id>"

# Authenticate to External ID tenant
az login --tenant $tenantId

# 1. Register base domain with tenant
az rest --method POST `
  --uri "https://graph.microsoft.com/v1.0/domains" `
  --headers "Content-Type=application/json" `
  --body "{ ""id"": ""$domain"" }"

# 2. Get verification DNS records
$records = az rest --method GET `
  --uri "https://graph.microsoft.com/v1.0/domains/$domain/verificationDnsRecords" | ConvertFrom-Json

# Add TXT records from $records.value to DNS zone, then verify:
$records.value | Where-Object { $_.recordType -eq "Txt" } | ForEach-Object {
  az network dns record-set txt add-record `
    --resource-group $rg `
    --zone-name $domain `
    --record-set-name "@" `
    --value $_.additionalProperties.text 2>&1
}

# 3. Verify domain ownership
az rest --method POST `
  --uri "https://graph.microsoft.com/v1.0/domains/$domain/verify"

# 4. Register login subdomain as Custom URL Domain
az rest --method POST `
  --uri "https://graph.microsoft.com/beta/directory/customDomainFederationSettings" `
  --headers "Content-Type=application/json" `
  --body "{ ""domain"": ""$loginSubdomain.$domain"" }"

# 5. Enable FIDO2
@'
{
  "state": "enabled",
  "includeTargets": [{ "targetType": "all_users", "id": "all_users" }],
  "passkeyProfiles": [{
    "displayName": "Default",
    "isDefault": true,
    "isSelfServiceRegistrationAllowed": true,
    "attestationEnforcementMode": "auditMode",
    "passkeyTypes": ["deviceBound", "synced"],
    "keyRestrictions": { "isEnforced": false }
  }]
}
'@ | Out-File "$env:TEMP\fido2.json" -Encoding utf8 -NoNewline

az rest --method PATCH `
  --uri "https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/fido2" `
  --headers "Content-Type=application/json" `
  --body "@$env:TEMP\fido2.json"
```

---

## 5. App Registration

```powershell
$appName = "passkey-app-production"

# Create app
$app = az ad app create --display-name $appName | ConvertFrom-Json
$appId = $app.appId
$objectId = $app.id

Write-Host "Client ID: $appId"
Write-Host "Object ID: $objectId"

# Add optional claims
@'
{"optionalClaims":{"idToken":[{"name":"email","essential":false},{"name":"given_name","essential":false},{"name":"family_name","essential":false}],"accessToken":[{"name":"email","essential":false}],"saml2Token":[]}}
'@ | Out-File "$env:TEMP\claims.json" -Encoding utf8 -NoNewline

az rest --method PATCH `
  --uri "https://graph.microsoft.com/v1.0/applications/$objectId" `
  --headers "Content-Type=application/json" `
  --body "@$env:TEMP\claims.json"

# Create client secret
$secret = az ad app credential reset `
  --id $appId `
  --append `
  --display-name "swa-production" `
  --years 1 `
  --query password -o tsv

Write-Host "Client Secret: $secret"
Write-Warning "Store this secret securely — it won't be shown again"

# Grant admin consent for API permissions
# (configure permissions in Portal first: User.Read.All, UserAuthMethod-Passkey.ReadWrite.All, 
#  GroupMember.ReadWrite.All, Policy.ReadWrite.AuthenticationMethod)
az ad app permission admin-consent --id $appId

# Create User Flow and associate app (see 03-TENANT-CONFIGURATION-REFERENCE.md §2)
```

---

## 6. Azure Static Web Apps

```powershell
$swaName = "app-passkey-$appName"

az staticwebapp create `
  --name $swaName `
  --resource-group $rg `
  --sku Standard `
  --location eastus2

# Get deployment token
$deployToken = az staticwebapp secrets list `
  --name $swaName `
  --resource-group $rg `
  --query "properties.apiKey" -o tsv
```

### 6.1 Configure Environment Variables (server-side)

```powershell
az staticwebapp appsettings set `
  --name $swaName `
  --resource-group $rg `
  --setting-names `
    "CLIENT_ID=$appId" `
    "CLIENT_SECRET=$secret" `
    "TENANT_ID=$tenantId" `
    "CIAM_DOMAIN=<tenant-name>.ciamlogin.com"
```

### 6.2 Build and Deploy

```powershell
# Create .env.local (gitignored — for VITE build-time vars only)
@"
VITE_CLIENT_ID=$appId
VITE_TENANT_ID=$tenantId
VITE_CIAM_DOMAIN=<tenant-name>.ciamlogin.com
VITE_CUSTOM_DOMAIN=login.$domain
VITE_PASSKEY_ORIGIN=https://login.$domain
"@ | Out-File ".env.local" -Encoding utf8 -NoNewline

# Build
npm run build

# Install API dependencies
npm install --prefix ./api

# Deploy SPA + API function
npx @azure/static-web-apps-cli deploy ./build `
  --api-location ./api `
  --deployment-token $deployToken `
  --env production

$swaHostname = az staticwebapp list -g $rg --query "[0].defaultHostname" -o tsv
Write-Host "SWA URL: https://$swaHostname"
```

---

## 7. Azure Front Door

```powershell
$fdProfile = "fd-passkey-prod"
$fdEndpoint = "auth-endpoint"
$customDomain = "$loginSubdomain.$domain"  # login.yourdomain.com

# Create Front Door profile (Consumption billing)
az afd profile create `
  --resource-group $rg `
  --profile-name $fdProfile `
  --sku Standard_AzureFrontDoor

# Create endpoint
$fd = az afd endpoint create `
  --resource-group $rg `
  --profile-name $fdProfile `
  --endpoint-name $fdEndpoint `
  --enabled-state Enabled | ConvertFrom-Json

$fdFqdn = $fd.hostName
Write-Host "Front Door FQDN: $fdFqdn"

# Create origin group
az afd origin-group create `
  --resource-group $rg `
  --profile-name $fdProfile `
  --origin-group-name "swa-backends" `
  --probe-protocol Https `
  --probe-request-type GET `
  --probe-path "/" `
  --probe-interval-in-seconds 100 `
  --sample-size 4 `
  --successful-samples-required 3 `
  --additional-latency-in-milliseconds 50

# Create origin (Static Web Apps)
az afd origin create `
  --resource-group $rg `
  --profile-name $fdProfile `
  --origin-group-name "swa-backends" `
  --name "swa-origin" `
  --origin-host-header $swaHostname `
  --host-name $swaHostname `
  --https-port 443 `
  --http-port 80 `
  --priority 1 `
  --weight 1000 `
  --enabled-state Enabled

# Create route
az afd route create `
  --resource-group $rg `
  --profile-name $fdProfile `
  --endpoint-name $fdEndpoint `
  --route-name "swa-route" `
  --origin-group "swa-backends" `
  --patterns-to-match "/*" `
  --supported-protocols Http Https `
  --https-redirect Enabled `
  --forwarding-protocol HttpsOnly `
  --link-to-default-domain Enabled

# Add custom domain
$domainValidation = az afd custom-domain create `
  --resource-group $rg `
  --profile-name $fdProfile `
  --custom-domain-name "login-$($domain.Replace('.', '-'))" `
  --host-name $customDomain `
  --certificate-type ManagedCertificate `
  --minimum-tls-version TLS12 | ConvertFrom-Json

$validationToken = $domainValidation.validationProperties.validationToken
Write-Host "Front Door validation token: $validationToken"
Write-Host "Expires: $($domainValidation.validationProperties.expirationDate)"

# Associate custom domain with route
az afd route update `
  --resource-group $rg `
  --profile-name $fdProfile `
  --endpoint-name $fdEndpoint `
  --route-name "swa-route" `
  --custom-domains "login-$($domain.Replace('.', '-'))"
```

---

## 8. DNS Records

```powershell
# CNAME: login.yourdomain.com → Front Door
az network dns record-set cname set-record `
  --resource-group $rg `
  --zone-name $domain `
  --record-set-name $loginSubdomain `
  --cname $fdFqdn

# TXT: Front Door domain validation
az network dns record-set txt add-record `
  --resource-group $rg `
  --zone-name $domain `
  --record-set-name "_dnsauth.$loginSubdomain" `
  --value $validationToken

# Verify DNS propagation
nslookup -type=CNAME "$loginSubdomain.$domain" 8.8.8.8
nslookup -type=TXT "_dnsauth.$loginSubdomain.$domain" 8.8.8.8
```

---

## 9. Wait for Certificate Provisioning

```powershell
$domainName = "login-$($domain.Replace('.', '-'))"

# Poll until Succeeded (typically 10-30 minutes)
do {
  $status = az afd custom-domain show `
    -g $rg --profile-name $fdProfile `
    --custom-domain-name $domainName `
    --query "{state:domainValidationState,deploy:deploymentStatus}" | ConvertFrom-Json

  Write-Host "$(Get-Date -Format 'HH:mm:ss') state=$($status.state) deploy=$($status.deploy)"
  if ($status.deploy -eq "Succeeded") { break }
  Start-Sleep 30
} while ($true)
```

---

## 10. Update App Registration Redirect URIs

```powershell
$productionUri = "https://$customDomain/"
$localDevUri = "https://auth.<tenant>.ciamlogin.com:3000/"

@"
{"spa":{"redirectUris":["$productionUri","$localDevUri"]}}
"@ | Out-File "$env:TEMP\spa.json" -Encoding utf8 -NoNewline

az rest --method PATCH `
  --uri "https://graph.microsoft.com/v1.0/applications/$objectId" `
  --headers "Content-Type=application/json" `
  --body "@$env:TEMP\spa.json"

# Verify
az ad app show --id $appId --query spa.redirectUris
```

---

## 11. MFA Group + CA Policy

```powershell
# Create MFA enforcement group
$group = az rest --method POST `
  --uri "https://graph.microsoft.com/v1.0/groups" `
  --headers "Content-Type=application/json" `
  --body '{
    "displayName": "grp-passkey-mfa-required",
    "mailEnabled": false,
    "mailNickname": "grp-passkey-mfa-required",
    "securityEnabled": true
  }' | ConvertFrom-Json

$groupId = $group.id
Write-Host "MFA Group ID: $groupId"

# Update authConfig.js with $groupId
# const MFA_GROUP_ID = '$groupId';

# Create CA policy
$caBody = @{
  displayName = "Require MFA - Passkey App"
  state = "enabled"
  conditions = @{
    clientAppTypes = @("browser")
    users = @{ includeUsers = @("all"); excludeUsers = @() }
    applications = @{ includeApplications = @($appId) }
  }
  grantControls = @{
    operator = "OR"
    builtInControls = @("mfa")
  }
} | ConvertTo-Json -Depth 8

az rest --method POST `
  --uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies" `
  --headers "Content-Type=application/json" `
  --body $caBody
```

---

## 12. Post-Deployment Verification

```powershell
# 1. App loads on custom domain
Invoke-WebRequest -Uri "https://$customDomain/" -UseBasicParsing | Select-Object StatusCode

# 2. API function responds
Invoke-WebRequest -Uri "https://$customDomain/api/oauth2/v2.0/token" `
  -Method POST -ContentType "application/x-www-form-urlencoded" `
  -Body "grant_type=client_credentials&scope=https://graph.microsoft.com/.default" `
  | Select-Object StatusCode  # Expects 400 (no client_id/secret) - confirms function is live

# 3. SPA redirect URIs
az ad app show --id $appId --query spa.redirectUris

# 4. FIDO2 policy enabled
az rest --method GET `
  --uri "https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/fido2" `
  --query "state"

# 5. DNS resolution
nslookup "$customDomain" 8.8.8.8
nslookup "_dnsauth.$loginSubdomain.$domain" 8.8.8.8
```

---

## 13. Cost Estimate (Production)

| Resource | SKU | Estimated Monthly |
|---------|-----|-------------------|
| Azure Static Web Apps | Standard | $9.00 USD |
| Azure Front Door | Standard (Consumption) | ~$25-50 (5GB transfer) |
| Azure DNS Zone | Standard | ~$0.90 (10M queries) |
| CIAM Tenant | Free up to 50,000 MAU | $0 |
| Graph API | Included | $0 |
| **Total (5K MAU)** | | **~$35-60/month** |

Scale estimate: 50K MAU → add ~$150/month for additional Front Door traffic.

---

## 14. Security Hardening Checklist

- [ ] Client secret in SWA app settings (not in code or VITE build)
- [ ] `.env.local` in `.gitignore`, never committed
- [ ] SPA redirect URIs locked to production domain only (no localhost in prod)
- [ ] HTTPS-only: Front Door enforces redirect HTTP→HTTPS
- [ ] Certificate: Front Door managed certificate (auto-renews)
- [ ] API function: anonymous auth level (protected by secret in app settings)
- [ ] Consider: Key Vault for client secret rotation
- [ ] Consider: Front Door WAF policy for DDoS and rate limiting
- [ ] Consider: Application Insights for telemetry
- [ ] Rotate client secret before expiry (1-year default)
- [ ] Review FIDO2 attestation mode (`auditMode` → `strict` if FIDO Alliance certification required)
