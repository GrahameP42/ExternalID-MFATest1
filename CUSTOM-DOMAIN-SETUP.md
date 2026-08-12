# Custom Domain Setup for Passkey Registration

**Status**: 🔄 In Progress  
**Objective**: Enable passkey registration by routing a custom domain through Azure Front Door to Static Web Apps  
**Timeline**: ~30 minutes to deploy

---

## Problem Statement

**Current State**: 
- App deployed to: `orange-coast-0407c830f.7.azurestaticapps.net`
- Passkey registration fails with WebAuthn RP ID mismatch
- Browser rejects `PetchyEntraExternalIDTest03.ciamlogin.com` as RP when request originates from Static Web Apps domain

**Solution**: 
Route requests through a custom domain recognized by both browser and CIAM, enabling passkey ceremony to work end-to-end.

---

## Architecture

```
User Browser on PC
    ↓
https://auth.petchyentraexternalidtest03.ciamlogin.com/
    ↓
Azure Front Door (Consumption tier: $0.30/GB)
    ├─ Custom domain: auth.petchyentraexternalidtest03.ciamlogin.com
    ├─ SSL/TLS: Free managed certificate
    ├─ Routes:
    │   ├─ / → Static Web Apps (app.com → orange-coast-0407c830f.7.azurestaticapps.net)
    │   └─ /api/* → [Optional: backend API]
    │
Azure Static Web Apps
    └─ Origin: orange-coast-0407c830f.7.azurestaticapps.net
```

**WebAuthn RP ID Logic**:
- CIAM Graph returns: `rp.id = petchyentraexternalidtest03.ciamlogin.com`
- Browser checks: Is origin domain a suffix of RP ID? ✅ YES (auth.petchyentraexternalidtest03.ciamlogin.com is subdomain)
- Registration proceeds ✓

---

## Prerequisites

### Existing Infrastructure (Deployed)
- ✅ Azure Front Door (Consumption tier): `fd-passkey-auth` in `rg-external-id-passkey-poc`
- ✅ Static Web Apps origin: `orange-coast-0407c830f.7.azurestaticapps.net`
- ✅ CIAM app registration: `passkey-fresh-test-2` (SPA URIs updated)

### Needed
- Custom domain to assign (options below):
  1. **Recommended**: `auth.petchyentraexternalidtest03.ciamlogin.com` (CIAM-branded)
  2. **Alternative**: `login.azddns.top` (from previous deployment)
  3. **Generic**: Any domain you own (requires DNS management)

---

## Setup Steps

### Step 1: Choose Custom Domain

Select one:
- Option A: **CIAM-branded domain** (easier, no DNS management needed if using managed certificate)
  - Domain: `auth.petchyentraexternalidtest03.ciamlogin.com`
  - Pros: Clearly tied to CIAM tenant; uses CIAM's domain infrastructure
  - Cons: Requires CIAM custom URL domain setup

- Option B: **Custom registered domain** (e.g., from azddns.top if available)
  - Domain: `auth.azddns.top` or `login.azddns.top`
  - Pros: Standard DNS management; known approach
  - Cons: Requires DNS zone and A/CNAME records

### Step 2: Create Front Door Endpoint

```powershell
$profileName = "fd-passkey-auth"
$rgName = "rg-external-id-passkey-poc"
$customDomain = "auth.petchyentraexternalidtest03.ciamlogin.com"  # CHOOSE DOMAIN

# Create endpoint (DNS name = FQDN or Front Door will assign subdomain)
az afd endpoint create `
  --resource-group $rgName `
  --profile-name $profileName `
  --endpoint-name "auth-endpoint" `
  --enabled-state Enabled 2>&1

# Get Front Door FQDN
$fdFqdn = az afd endpoint list -g $rgName --profile-name $profileName `
  --query "[0].hostName" -o tsv

Write-Host "Front Door FQDN: $fdFqdn"
```

### Step 3: Create Front Door Origin Group and Origin

```powershell
$swaHostname = "orange-coast-0407c830f.7.azurestaticapps.net"

# Create origin group (load balancing + health checks)
az afd origin-group create `
  --resource-group $rgName `
  --profile-name $profileName `
  --origin-group-name "swa-backends" `
  --probe-protocol https `
  --probe-request-type GET `
  --probe-path "/" `
  --probe-interval-in-seconds 100 2>&1

# Create origin (Static Web Apps)
az afd origin create `
  --resource-group $rgName `
  --profile-name $profileName `
  --origin-group-name "swa-backends" `
  --name "swa-origin" `
  --origin-host-header $swaHostname `
  --origin $swaHostname `
  --https-port 443 `
  --http-port 80 2>&1
```

### Step 4: Create Routing Rule

```powershell
# Create route from endpoint to origin group
az afd route create `
  --resource-group $rgName `
  --profile-name $profileName `
  --endpoint-name "auth-endpoint" `
  --route-name "swa-route" `
  --origin-group "swa-backends" `
  --patterns "/*" `
  --supported-protocols Http Https `
  --link-to-default-domain Enabled 2>&1
```

### Step 5: Add Custom Domain to Front Door

```powershell
$customDomain = "auth.petchyentraexternalidtest03.ciamlogin.com"

# Add custom domain (requires DNS verification TXT record)
az afd custom-domain create `
  --resource-group $rgName `
  --profile-name $profileName `
  --custom-domain-name "auth-domain" `
  --hostname $customDomain `
  --certificate-type ManagedCertificate 2>&1

# Get DNS verification requirement
$verificationToken = az afd custom-domain list -g $rgName --profile-name $profileName `
  --query "[0].validationProperties.validationToken" -o tsv

Write-Host "Add TXT record to DNS:"
Write-Host "_acm-challenge.$customDomain = $verificationToken"
```

### Step 6: Map Custom Domain to Route

```powershell
# Associate custom domain with route
az afd route update `
  --resource-group $rgName `
  --profile-name $profileName `
  --endpoint-name "auth-endpoint" `
  --route-name "swa-route" `
  --custom-domains "auth-domain" `
  --certificate-type "ManagedCertificate" 2>&1
```

### Step 7: Update CIAM App Registration

Add the custom domain to SPA redirect URIs:

```powershell
$customDomain = "auth.petchyentraexternalidtest03.ciamlogin.com"

az rest --method PATCH `
  --uri "https://graph.microsoft.com/v1.0/applications/98566591-b49b-4ecc-995f-8a109d61d1bd" `
  --headers "Content-Type=application/json" `
  --body "{
    \"spa\": {
      \"redirectUris\": [
        \"https://$customDomain/\",
        \"https://orange-coast-0407c830f.7.azurestaticapps.net/\",
        \"https://auth.petchyentraexternalidtest03.ciamlogin.com:3000/\"
      ]
    }
  }" 2>&1
```

### Step 8: Update App Configuration

Update `src/authConfig.js` to use the custom domain as PASSKEY_PUBLIC_ORIGIN:

```javascript
export const appConfig = {
    proxyDomain: 'http://localhost:3001/api',
    appId: _clientId,
    tenantId: _tenantId,
    appSecret: env.VITE_APP_SECRET || '',
    customDomain: env.VITE_CUSTOM_DOMAIN || 'auth.petchyentraexternalidtest03.ciamlogin.com',  // ← NEW
};
```

---

## Validation Checklist

- [ ] Front Door endpoint created and provisioned
- [ ] Origin group and origin configured
- [ ] Route created and linked to endpoint
- [ ] Custom domain added to Front Door
- [ ] DNS TXT record added (if required for validation)
- [ ] Managed certificate provisioned (check Front Door → Custom domains)
- [ ] CIAM app registration SPA URIs updated with custom domain
- [ ] App config updated with custom domain
- [ ] **Test**: Access app via `https://auth.petchyentraexternalidtest03.ciamlogin.com/`
  - Should see "Passkey Management" page (redirects to CIAM if not logged in)
  - Should NOT get WebAuthn RP ID mismatch error on passkey registration

---

## Cost Implications

| Component | SKU | Cost |
|-----------|-----|------|
| Azure Front Door | Consumption | $0.30/GB data transfer (~$0-2/month for PoC) |
| Static Web Apps | Standard | ~$4.70/month (14 days prorated) |
| **Total PoC** | | ~$7/month |

No additional charges for managed certificates or DNS.

---

## Troubleshooting

### Issue: "The relying party ID is not a registrable domain suffix of..."
**Cause**: RP ID returned by Graph is not a suffix of current domain
**Check**:
```powershell
# Verify your custom domain matches CIAM expectations
# Graph returns: petchyentraexternalidtest03.ciamlogin.com
# Your domain must be: auth.petchyentraexternalidtest03.ciamlogin.com
```

### Issue: Custom domain not validated
**Cause**: DNS TXT record not added or propagated
**Fix**:
```powershell
# Check DNS propagation
nslookup _acm-challenge.auth.petchyentraexternalidtest03.ciamlogin.com
```

### Issue: Front Door returning 502 Bad Gateway
**Cause**: Origin health check failing
**Check**:
1. Verify Static Web Apps is online: `curl https://orange-coast-0407c830f.7.azurestaticapps.net/`
2. Verify origin group probe settings (path, protocol)
3. Check Front Door diagnostic logs

---

## Next Steps

1. **If using CIAM-branded domain**: Register custom URL domain with CIAM first
   ```powershell
   az rest --method POST `
     --uri "https://graph.microsoft.com/beta/directory/customDomainFederationSettings" `
     --body "{ \"domain\": \"auth.petchyentraexternalidtest03.ciamlogin.com\" }"
   ```

2. **If using registered domain**: Ensure DNS zone is available in Azure

3. **Execute setup steps** above in sequence

4. **Test end-to-end**:
   - Sign in via custom domain
   - Attempt passkey registration
   - Verify no WebAuthn RP ID errors

5. **Update app configuration** and deploy

---

**Status**: Ready for execution  
**Estimated Time**: 30-45 minutes  
**Estimated Cost**: $0-2 for PoC phase  

