# Tenant Configuration Reference — Entra External ID

**Applies to**: Microsoft Entra External ID (CIAM)  
**Tenant type**: External tenant (customer-facing, not workforce)  
**Last Updated**: 2026-08-12

---

## 1. Authentication Methods Policy

### 1.1 FIDO2 / Passkeys

FIDO2 is the primary phishing-resistant method for External ID. Configure via Graph or Portal.

**Graph API**: `PATCH https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/fido2`

```json
{
  "@odata.type": "#microsoft.graph.fido2AuthenticationMethodConfiguration",
  "state": "enabled",
  "includeTargets": [
    {
      "targetType": "all_users",
      "id": "all_users"
    }
  ],
  "passkeyProfiles": [
    {
      "displayName": "Default Passkey Profile",
      "isDefault": true,
      "isSelfServiceRegistrationAllowed": true,
      "attestationEnforcementMode": "auditMode",
      "keyRestrictions": {
        "isEnforced": false,
        "enforcementType": "allow",
        "aaGuids": []
      },
      "passkeyTypes": ["deviceBound", "synced"]
    }
  ]
}
```

**PowerShell**:
```powershell
$body = @{
  state = "enabled"
  includeTargets = @(@{ targetType = "all_users"; id = "all_users" })
  passkeyProfiles = @(@{
    displayName = "Default Passkey Profile"
    isDefault = $true
    isSelfServiceRegistrationAllowed = $true
    attestationEnforcementMode = "auditMode"
    passkeyTypes = @("deviceBound", "synced")
    keyRestrictions = @{ isEnforced = $false }
  })
} | ConvertTo-Json -Depth 10

az rest --method PATCH `
  --uri "https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/fido2" `
  --headers "Content-Type=application/json" `
  --body $body
```

**Key settings**:
- `isSelfServiceRegistrationAllowed`: `true` — users register their own passkeys via the app  
- `passkeyTypes`: `["deviceBound", "synced"]` — allow both hardware-bound and synced (phone/iCloud/Google PM)  
- `attestationEnforcementMode`: `"auditMode"` — logs attestation but doesn't enforce (use `"strict"` for FIDO Alliance certified keys only)  
- Specific key allowlisting: add AAGUIDs to `aaGuids` array with `isEnforced: true` and `enforcementType: "allow"`

---

### 1.2 Email OTP

Email OTP is the built-in fallback MFA for External ID.

**Graph API**: `PATCH https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/email`

```json
{
  "@odata.type": "#microsoft.graph.emailAuthenticationMethodConfiguration",
  "state": "enabled",
  "allowExternalIdToUseEmailOtp": "enabled"
}
```

**Values for `allowExternalIdToUseEmailOtp`**:
| Value | Effect |
|-------|--------|
| `enabled` | Email OTP available for all users (guests and local members) |
| `disabled` | Suppresses email OTP for **B2B/guest users only** — local member accounts always retain email OTP (platform limitation — cannot be disabled for local members) |
| `default` | Platform default (same as `enabled`) |

**Critical platform limitation**: `disabled` setting **only affects B2B/external/guest users**. Local member accounts (email+password CIAM accounts) always have email OTP as a hardcoded fallback. This cannot be overridden at the platform level. App-side AMR enforcement is the only mechanism to prevent OTP from satisfying MFA requirements.

**AMR for email OTP**: `["otp", "mfa"]` or `["mfa"]` — **not phishing-resistant**

---

### 1.3 Microsoft Authenticator / TOTP / Phone OTP

**IMPORTANT**: These methods have **limited or no support** in External ID CIAM for local accounts.

| Method | External ID Support | AMR Value | Phishing-Resistant |
|--------|--------------------|-----------|--------------------|
| Microsoft Authenticator (push) | ❌ Not available for local CIAM accounts | N/A | No |
| Microsoft Authenticator (TOTP) | ❌ Not available for local CIAM accounts | N/A | No |
| Google Authenticator / TOTP apps | ❌ No TOTP MFA method in External ID | N/A | No |
| SMS / phone OTP | ⚠️ Limited — returns 500 errors for some local accounts | `otp`, `mfa` | No |
| Voice call OTP | ❌ Not supported in External ID | N/A | No |
| Temporary Access Pass (TAP) | ⚠️ Available via Graph API for initial onboarding only | N/A | No |

**Why Authenticator/TOTP is not available**:
External ID is a consumer-facing CIAM platform. Microsoft Authenticator app integration requires:
- Entra ID P1 or P2 license (workforce tenant feature)
- MDM/Intune device management
- Tenant-level Authenticator policies

These are workforce-only features and are not provisioned in External ID tenants.

**When customers require TOTP-based MFA**: Consider federating External ID with an upstream identity provider (e.g., Entra ID workforce tenant, ZITADEL, Auth0) that supports TOTP. The federation OIDC token can carry phishing-resistant claims if the upstream provider certifies them.

**AMR indistinguishability**: Even if TOTP were available, its AMR value (`otp`) is identical to email OTP — the RP cannot distinguish between them. This means TOTP-based MFA would be classified as non-phishing-resistant by the app's AMR enforcement.

**Phishing-resistant AMR values recognized by this RP**:
```javascript
const PHISHING_RESISTANT_AMR = ['hwk', 'fido', 'ngcmfa', 'swk', 'pop', 'rsa'];
```
Only FIDO2-based passkeys produce these values. Authenticator, TOTP, and SMS all produce `otp` which is explicitly excluded.

---

### 1.4 Social Identity Providers

External ID supports federation with consumer identity providers:

| Provider | Configuration | Auth method in token |
|----------|--------------|----------------------|
| Google | OIDC federation | `amr` from Google |
| Facebook | OAuth 2.0 | varies |
| Apple | OIDC | varies |
| Custom OIDC | Manual OIDC configuration | passes through federated `amr` |

**Graph API** to add Google:
```powershell
az rest --method POST `
  --uri "https://graph.microsoft.com/v1.0/identity/identityProviders" `
  --headers "Content-Type=application/json" `
  --body '{
    "@odata.type": "#microsoft.graph.socialIdentityProvider",
    "displayName": "Google",
    "identityProviderType": "Google",
    "clientId": "<google-client-id>",
    "clientSecret": "<google-client-secret>"
  }'
```

**Then add to user flow**: `POST /identity/authenticationEventsFlows/{flowId}/conditions/applications/includeApplications`

---

## 2. User Flow (SUSI) Configuration

### 2.1 Create Sign-Up/Sign-In User Flow

```powershell
$body = @{
  "@odata.type" = "#microsoft.graph.externalUsersSelfServiceSignUpEventsFlow"
  "displayName" = "MyApp-SignUpSignIn"
  "priority" = 500
  "onInteractiveAuthFlowStart" = @{
    "@odata.type" = "#microsoft.graph.onInteractiveAuthFlowStartExternalUsersSelfServiceSignUp"
    "isSignUpAllowed" = $true   # Allow new user registration
  }
  "onAuthenticationMethodLoadStart" = @{
    "@odata.type" = "#microsoft.graph.onAuthenticationMethodLoadStartExternalUsersSelfServiceSignUp"
    "identityProviders" = @(
      @{
        "@odata.type" = "#microsoft.graph.builtInIdentityProvider"
        "id" = "EmailPassword-OAUTH"   # Email + Password local accounts
      }
    )
  }
  "onAttributeCollection" = @{
    "@odata.type" = "#microsoft.graph.onAttributeCollectionExternalUsersSelfServiceSignUp"
    "accessPackages" = @()
    "attributes" = @(
      @{ "id" = "email" }
      @{ "id" = "displayName" }
    )
    "attributeCollectionPage" = @{
      "views" = @(
        @{
          "inputs" = @(
            @{ "attribute" = "email"; "editable" = $false; "hidden" = $true; "required" = $true; "writeToDirectory" = $true }
            @{ "attribute" = "displayName"; "editable" = $true; "hidden" = $false; "required" = $true; "writeToDirectory" = $true }
          )
        }
      )
    }
  }
  "onUserCreateStart" = @{
    "@odata.type" = "#microsoft.graph.onUserCreateStartExternalUsersSelfServiceSignUp"
    "userTypeToCreate" = "member"   # member = local account (not guest)
    "accessPackages" = @()
  }
} | ConvertTo-Json -Depth 15

$flow = az rest --method POST `
  --uri "https://graph.microsoft.com/beta/identity/authenticationEventsFlows" `
  --headers "Content-Type=application/json" `
  --body $body | ConvertFrom-Json

$flowId = $flow.id
Write-Host "Flow ID: $flowId"
```

**Identity Provider ID values**:
| IDP | ID string |
|-----|-----------|
| Email + Password | `EmailPassword-OAUTH` |
| Email OTP only | `EmailOTP-OAUTH` |
| Google | `Google-OAUTH` |
| Facebook | `Facebook-OAUTH` |

**WRONG**: Using `EmailPassword-OAUTH2-ROPC` causes AADB2C validation error.

### 2.2 Associate App with User Flow

```powershell
az rest --method POST `
  --uri "https://graph.microsoft.com/beta/identity/authenticationEventsFlows/$flowId/conditions/applications/includeApplications" `
  --headers "Content-Type=application/json" `
  --body "{ ""appId"": ""<your-client-id>"" }"
```

**Verify association persisted**:
```powershell
az rest --method GET `
  --uri "https://graph.microsoft.com/beta/identity/authenticationEventsFlows/$flowId/conditions/applications/includeApplications"
```

---

## 3. App Registration

### 3.1 Create App Registration

```powershell
# Create app
$app = az ad app create `
  --display-name "MyPasskeyApp" `
  --web-redirect-uris "https://login.yourdomain.com/" `
  --query "{id:id, appId:appId}" | ConvertFrom-Json

$appId = $app.appId
$objectId = $app.id

# Add SPA redirect URIs (required for PKCE/SPA token redemption)
$spaBody = @{
  spa = @{
    redirectUris = @(
      "https://login.yourdomain.com/"
      "https://auth.<tenant>.ciamlogin.com:3000/"   # Local dev
    )
  }
} | ConvertTo-Json -Depth 5

az rest --method PATCH `
  --uri "https://graph.microsoft.com/v1.0/applications/$objectId" `
  --headers "Content-Type=application/json" `
  --body $spaBody
```

**Critical**: SPA redirect URIs MUST be registered — not just Web redirect URIs. Token exchange from JavaScript (PKCE) requires SPA type. Without it: `AADSTS9002326` error ("Cross-origin token redemption only permitted for SPA client-type").

### 3.2 Required API Permissions

```powershell
# Get service principal object ID
$sp = az ad sp show --id $appId | ConvertFrom-Json
$spId = $sp.id

# Permission IDs for Microsoft Graph (00000003-0000-0000-c000-000000000000)
$graphSpId = "00000003-0000-0000-c000-000000000000"

# Required app roles (application permissions, not delegated):
# UserAuthMethod-Passkey.ReadWrite.All  = 0400e371-...
# User.Read.All                          = df021288-...
# GroupMember.ReadWrite.All              = dbaae8cf-...
# Policy.ReadWrite.AuthenticationMethod  = 29c18626-...

# Add via Portal: App registration → API permissions → Add permission
# → Microsoft Graph → Application permissions → search for each above

# Grant admin consent (required for app permissions):
az ad app permission admin-consent --id $appId
```

**Permission purposes**:
| Permission | Used for |
|-----------|---------|
| `UserAuthMethod-Passkey.ReadWrite.All` | Create/list/delete FIDO2 methods for users |
| `User.Read.All` | Resolve email → OID via identities filter |
| `GroupMember.ReadWrite.All` | Auto-enroll users to MFA enforcement group |
| `Policy.ReadWrite.AuthenticationMethod` | Manage email OTP policy |

### 3.3 Optional Claims Configuration

```powershell
$claimsBody = @{
  optionalClaims = @{
    idToken = @(
      @{ name = "email"; essential = $false }
      @{ name = "given_name"; essential = $false }
      @{ name = "family_name"; essential = $false }
    )
    accessToken = @(
      @{ name = "email"; essential = $false }
    )
    saml2Token = @()
  }
} | ConvertTo-Json -Depth 10

az rest --method PATCH `
  --uri "https://graph.microsoft.com/v1.0/applications/$objectId" `
  --headers "Content-Type=application/json" `
  --body $claimsBody
```

**Note**: Even with optional claims configured, External ID CIAM may not populate `email` for local accounts. Use Graph API fallback: `GET /users/{oid}?$select=mail,identities`.

### 3.4 Create Client Secret

```powershell
$secret = az ad app credential reset `
  --id $appId `
  --append `
  --display-name "swa-production-$(Get-Date -Format 'yyyy-MM')" `
  --years 1 `
  --query password -o tsv

# Store in SWA app settings (NEVER in code or build artifacts):
az staticwebapp appsettings set `
  --name "<your-swa-name>" `
  --resource-group "<rg>" `
  --setting-names "CLIENT_SECRET=$secret"

Write-Warning "Secret is shown once. Store in Key Vault for production."
```

---

## 4. Conditional Access Policy

### 4.1 MFA Enforcement Policy

External ID **does not support** authentication strengths (phishing-resistant CA). Use `builtInControls: ["mfa"]` only.

```powershell
$caPolicy = @{
  displayName = "Require MFA for <AppName>"
  state = "enabled"
  conditions = @{
    clientAppTypes = @("browser", "mobileAppsAndDesktopClients")
    users = @{
      includeUsers = @("all")
      excludeUsers = @()
    }
    applications = @{
      includeApplications = @($appId)   # Scope to specific app
    }
  }
  grantControls = @{
    operator = "OR"
    builtInControls = @("mfa")   # Accepts any MFA — app enforces phishing-resistant via AMR
    # DO NOT use authenticationStrength — causes infinite OTP loop in External ID
  }
} | ConvertTo-Json -Depth 10

az rest --method POST `
  --uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies" `
  --headers "Content-Type=application/json" `
  --body $caPolicy
```

**Why NOT authentication strength**: External ID CA authentication strengths cause an **infinite email-OTP loop** — CIAM keeps presenting email OTP to satisfy phishing-resistant requirement, OTP is never phishing-resistant, loop never ends. Use plain `mfa` grant + app-side AMR enforcement.

**To remove authentication strength** (if mistakenly set):
```powershell
az rest --method PATCH `
  --uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies/<policyId>" `
  --headers "Content-Type=application/json" `
  --body '{ "grantControls": { "authenticationStrength": null, "builtInControls": ["mfa"] } }'
# MUST use v1.0 — beta silently no-ops the authenticationStrength null
```

### 4.2 MFA Enforcement Group

Used for scoping MFA enforcement and tracking enrolled users:

```powershell
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

# Update app config (authConfig.js) with this group ID:
# const MFA_GROUP_ID = '$groupId';
```

---

## 5. Custom URL Domain

**Required for passkey registration** (WebAuthn RP ID must match serving domain).

### 5.1 Register Domain with CIAM

```powershell
# Step 1: Add domain to Entra External ID tenant
az rest --method POST `
  --uri "https://graph.microsoft.com/v1.0/domains" `
  --headers "Content-Type=application/json" `
  --body '{ "id": "yourdomain.com" }'

# Step 2: Get DNS verification records
az rest --method GET `
  --uri "https://graph.microsoft.com/v1.0/domains/yourdomain.com/verificationDnsRecords"

# Add returned TXT records to DNS zone, then verify:
az rest --method POST `
  --uri "https://graph.microsoft.com/v1.0/domains/yourdomain.com/verify"

# Step 3: Set as Custom URL Domain type
az rest --method POST `
  --uri "https://graph.microsoft.com/beta/directory/customDomainFederationSettings" `
  --headers "Content-Type=application/json" `
  --body '{ "domain": "login.yourdomain.com" }'
```

### 5.2 Subdomain for Login (login.yourdomain.com)

The signing endpoint for passkeys must be a **subdomain** that is a valid suffix of your base domain:
- Base domain: `yourdomain.com` → registered and verified in CIAM
- Login subdomain: `login.yourdomain.com` → used as RP ID for passkey registration
- Both must be registered and verified in the CIAM tenant

---

## 6. Email OTP Policy Management

```powershell
# Disable email OTP for guest/B2B users (keeps working for local members):
az rest --method PATCH `
  --uri "https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/email" `
  --headers "Content-Type=application/json" `
  --body '{ "allowExternalIdToUseEmailOtp": "disabled" }'

# Re-enable if needed:
az rest --method PATCH `
  --uri "https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/email" `
  --headers "Content-Type=application/json" `
  --body '{ "allowExternalIdToUseEmailOtp": "enabled" }'

# Check current state:
az rest --method GET `
  --uri "https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/email" `
  --query "allowExternalIdToUseEmailOtp"
```

---

## 7. Passkey Self-Service Management

### 7.1 List User Passkeys

```powershell
$userId = "<oid>"
az rest --method GET `
  --uri "https://graph.microsoft.com/beta/users/$userId/authentication/fido2Methods"
```

### 7.2 Register Passkey for User (Admin / App-Only)

External ID does NOT support delegated self-service passkey registration (`405 methodNotAllowed` on `/me`). Only app-only (admin) token can provision passkeys.

```powershell
# Step 1: Get creation options
$options = az rest --method POST `
  --uri "https://graph.microsoft.com/beta/users/$userId/authentication/fido2Methods/creationOptions" `
  --headers "Content-Type=application/json" `
  --body '{ "challengeTimeoutInMinutes": 5 }' | ConvertFrom-Json

# Step 2: App performs WebAuthn ceremony using options
# (browser-side: navigator.credentials.create())

# Step 3: Register the credential
az rest --method POST `
  --uri "https://graph.microsoft.com/beta/users/$userId/authentication/fido2Methods" `
  --headers "Content-Type=application/json" `
  --body $attestationResponse  # WebAuthn attestation from browser
```

**CRITICAL `creationOptions` gotchas**:
- `rp.id` is returned in mixed case: `PetchyEntraExternalIDTest03.ciamlogin.com` — must `.toLowerCase()` before passing to browser
- Remove `extensions.credProtect` (userVerificationOptional) — causes "Requested protection policy is inconsistent" on Windows
- `excludeCredentials` key IDs end with 0/1/2 digit = base64 padding count, must be decoded before passing to WebAuthn

### 7.3 Delete Passkey

```powershell
$passkeyId = "<fido2MethodId>"
az rest --method DELETE `
  --uri "https://graph.microsoft.com/beta/users/$userId/authentication/fido2Methods/$passkeyId"
```

---

## 8. Authentication Methods Policy: Full State Overview

| Authentication Method | Local Members | B2B Guests | Social IdP | Notes |
|----------------------|:-------------:|:----------:|:----------:|-------|
| **Email + Password** | ✅ Primary | ❌ | ❌ | UserFlow: `EmailPassword-OAUTH` |
| **FIDO2 Passkeys (device-bound)** | ✅ Primary | ✅ | ❌ | Registers against custom URL domain as RP |
| **FIDO2 Passkeys (synced)** | ✅ Primary | ✅ | ❌ | Phone passkeys: iCloud Keychain, Google PM |
| **Email OTP (MFA second factor)** | ✅ Always on¹ | ⚠️ Suppressible² | ❌ | `allowExternalIdToUseEmailOtp` |
| **SMS / Phone OTP** | ⚠️ Limited³ | ❌ | ❌ | 500 errors in some tenant configurations |
| **Microsoft Authenticator (push)** | ❌ Not available | ❌ | ❌ | Requires Entra ID P1/P2 — workforce only |
| **Microsoft Authenticator (TOTP)** | ❌ Not available | ❌ | ❌ | Requires Entra ID P1/P2 — workforce only |
| **TOTP apps (Google Auth, Authy)** | ❌ Not available | ❌ | ❌ | No TOTP method type in External ID |
| **Temporary Access Pass (TAP)** | ✅ Via Graph API | ✅ | ❌ | Time-limited; onboarding / account recovery only |
| **Google Sign-In** | ❌ | ❌ | ✅ | UserFlow: `Google-OAUTH` |
| **Facebook / Apple Sign-In** | ❌ | ❌ | ✅ | UserFlow: `Facebook-OAUTH` / Apple OIDC |
| **Custom SAML / OIDC federation** | ❌ | ❌ | ✅ | Enterprise IdP or upstream workforce Entra ID |

**Notes**:

¹ **Email OTP for local members cannot be disabled** — it is a hardcoded platform fallback for email+password local accounts regardless of the `allowExternalIdToUseEmailOtp` policy value. App-side AMR enforcement is the only mechanism to reject OTP-based sessions.

² **B2B/guest OTP suppression** — setting `allowExternalIdToUseEmailOtp: disabled` suppresses email OTP only for B2B invited guest users, not for local members.

³ **SMS OTP** — availability varies by tenant region and configuration. Returns HTTP 500 in some External ID tenants; not a reliable fallback.

> **For organisations requiring Microsoft Authenticator or TOTP**:
> These methods are not available in External ID CIAM. The recommended architecture is to federate External ID with an upstream **Entra ID workforce tenant** that supports the full Authenticator feature set. Users authenticate to the workforce tenant (Authenticator/TOTP/phone), and the resulting token flows to External ID via OIDC federation. See [04-MULTI-APP-SSO-MIGRATION.md](./04-MULTI-APP-SSO-MIGRATION.md) §6 for implementation details.
