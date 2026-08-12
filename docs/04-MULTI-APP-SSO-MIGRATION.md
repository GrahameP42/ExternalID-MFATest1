# Multi-App SSO Migration Guide — Adding a Second Application

**Applies to**: Adding a second RP (relying party) to an existing Entra External ID CIAM tenant where passkey MFA is already deployed  
**Last Updated**: 2026-08-12

---

## 1. How CIAM SSO Works

When a user authenticates to App A via CIAM, a **CIAM session cookie** is set in the browser for the CIAM domain (e.g. `petchyentraexternalidtest03.ciamlogin.com` and/or `login.azddns.top`). When the same user navigates to App B (also registered in the same CIAM tenant), CIAM detects the existing session and can issue tokens for App B **without requiring re-authentication**.

```
User authenticates to App A (passkey → amr: fido, mfa):
  ┌──────────┐   authorize   ┌──────────────────────────┐
  │  App A   │ ────────────→ │  CIAM                    │
  │ (SPA)    │ ←──────────── │  Issues token for App A  │
  └──────────┘   token       │  Sets session cookie     │
                             └──────────────────────────┘

User navigates to App B (same CIAM tenant):
  ┌──────────┐   authorize   ┌──────────────────────────┐
  │  App B   │ ────────────→ │  CIAM                    │
  │ (SPA)    │ ←──────────── │  Detects existing session│
  └──────────┘   token       │  Issues token for App B  │
                             │  WITHOUT re-auth         │
                             └──────────────────────────┘
  Token for App B:
  - aud: <App B client_id>
  - amr: [fido, mfa]          ← AMR carries over from App A session
  - sub: <user OID>           ← Same user identity
```

**Key point**: AMR claims from the original authentication **carry through to all subsequent token issuances** in the same CIAM session. If the user authenticated with a passkey (amr: fido, mfa) for App A, App B will also receive amr: fido, mfa without requiring the user to re-authenticate.

---

## 2. SSO Session Lifetime

| Setting | Default | Notes |
|---------|---------|-------|
| CIAM session lifetime | 24 hours | Configurable via CA policy |
| MSAL token cache | sessionStorage | Cleared on tab close |
| Refresh token lifetime | 24 hours | Allows silent token renewal |
| Passkey MFA window (`ngcmfaExpiration`) | 15 minutes | App-enforced window for passkey operations |

**AMR persistence**: The AMR claim is tied to the **CIAM session**, not the MSAL token cache. As long as the CIAM session is valid, subsequent token acquisitions (including silent) carry the original AMR.

---

## 3. Registering a Second Application

### 3.1 App Registration

```powershell
$tenantId = "<ciam-tenant-id>"
$ciamDomain = "<tenant>.ciamlogin.com"
$customDomain = "login.yourdomain.com"  # Same domain, or different subdomain for App B

# Create App B registration
$appB = az ad app create `
  --display-name "AppB-Production" | ConvertFrom-Json

$appBId = $appB.appId
$appBObjectId = $appB.id

# Add SPA redirect URIs for App B
@"
{"spa":{"redirectUris":["https://appb.yourdomain.com/","https://localhost:3000/"]}}
"@ | Out-File "$env:TEMP\appb-spa.json" -Encoding utf8 -NoNewline

az rest --method PATCH `
  --uri "https://graph.microsoft.com/v1.0/applications/$appBObjectId" `
  --headers "Content-Type=application/json" `
  --body "@$env:TEMP\appb-spa.json"

Write-Host "App B Client ID: $appBId"
```

### 3.2 Associate App B with the Existing User Flow

**Critical**: Both App A and App B must be in the **same user flow's `includeApplications`** list. Otherwise, CIAM won't process authentication requests from App B.

```powershell
$flowId = "<existing-susi-flow-id>"

# Add App B to the user flow
az rest --method POST `
  --uri "https://graph.microsoft.com/beta/identity/authenticationEventsFlows/$flowId/conditions/applications/includeApplications" `
  --headers "Content-Type=application/json" `
  --body "{ ""appId"": ""$appBId"" }"

# Verify both apps are listed
az rest --method GET `
  --uri "https://graph.microsoft.com/beta/identity/authenticationEventsFlows/$flowId/conditions/applications/includeApplications" `
  --query "value[].appId"
```

**Important**: The `onAttributeCollection.accessPackages` and `onUserCreateStart.accessPackages` arrays **must match** between the request body PATCH and existing flow configuration, otherwise validation fails. Fetch current state first and include unchanged arrays.

### 3.3 Grant Same API Permissions to App B

App B needs the same Graph permissions if it also manages passkeys:

```powershell
# In Azure Portal: App B → API permissions → Add:
# - UserAuthMethod-Passkey.ReadWrite.All (Application)
# - User.Read.All (Application)
# - GroupMember.ReadWrite.All (Application, if using same MFA group)
# - Policy.ReadWrite.AuthenticationMethod (Application, if managing policies)

az ad app permission admin-consent --id $appBId
```

### 3.4 Extend CA Policy to Cover App B

```powershell
$caPolicyId = "<existing-ca-policy-id>"

# Add App B to the CA policy (or create a separate policy)
$existingPolicy = az rest --method GET `
  --uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies/$caPolicyId" | ConvertFrom-Json

$existingApps = $existingPolicy.conditions.applications.includeApplications
$existingApps += $appBId

@"
{"conditions":{"applications":{"includeApplications":$(ConvertTo-Json $existingApps -Compress)}}}
"@ | Out-File "$env:TEMP\ca-patch.json" -Encoding utf8 -NoNewline

az rest --method PATCH `
  --uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies/$caPolicyId" `
  --headers "Content-Type=application/json" `
  --body "@$env:TEMP\ca-patch.json"
```

---

## 4. Token Flow: What App B Receives

When App B calls `loginRedirect` or `acquireTokenSilent` for a user already authenticated in the same browser session:

```
App B authorization request:
  client_id = <App B client_id>
  scope = email openid profile offline_access
  redirect_uri = https://appb.yourdomain.com/
  code_challenge = <PKCE>

CIAM processes:
  - Detects existing session (from App A cookie)
  - Validates App B is in the user flow's includeApplications
  - Issues authorization code immediately (no re-auth if session valid)
  - Code exchanged for token with:
      aud: <App B client_id>     ← App-specific audience
      sub: <user OID>            ← Same user, app-scoped subject
      amr: [fido, mfa]           ← Original auth method persists
      iss: https://<ciamDomain>/583e0a9e-...  ← Same issuer
```

**Audience is app-specific**: Access tokens for App A CANNOT be used to call App B's APIs and vice versa. Each app gets its own token with its own `aud`.

---

## 5. Token Validation in App B

### 5.1 MSAL.js (React SPA — same as App A)

```javascript
// authConfig.js for App B — only client_id changes
export const msalConfig = {
  auth: {
    clientId: '<APP-B-CLIENT-ID>',             // Different from App A
    authority: 'https://<tenant>.ciamlogin.com/',
    redirectUri: 'https://appb.yourdomain.com/',
  },
  cache: { cacheLocation: 'sessionStorage' }
};
```

App B gets the same MSAL behavior — SSO is transparent. The user won't see a login prompt if their session is still valid.

### 5.2 Backend API (Node.js / .NET / Python)

If App B is a backend API (not a SPA), validate tokens received from clients:

**Node.js (jsonwebtoken)**:
```javascript
const jwksClient = require('jwks-rsa');
const jwt = require('jsonwebtoken');

const TENANT_ID = '<tenant-id>';
const APP_B_CLIENT_ID = '<app-b-client-id>';
const CIAM_DOMAIN = '<tenant>.ciamlogin.com';

const client = jwksClient({
  jwksUri: `https://${CIAM_DOMAIN}/${TENANT_ID}/discovery/v2.0/keys`
});

function validateToken(token) {
  return new Promise((resolve, reject) => {
    jwt.verify(
      token,
      (header, callback) => {
        client.getSigningKey(header.kid, (err, key) => {
          callback(err, key?.getPublicKey());
        });
      },
      {
        audience: APP_B_CLIENT_ID,        // Must match App B client_id
        issuer: `https://${CIAM_DOMAIN}/${TENANT_ID}/v2.0`,
        algorithms: ['RS256']
      },
      (err, decoded) => err ? reject(err) : resolve(decoded)
    );
  });
}

// Check phishing-resistant MFA:
function isPhishingResistant(decoded) {
  const PHISHING_RESISTANT_AMR = ['hwk', 'fido', 'ngcmfa', 'swk', 'pop', 'rsa'];
  return decoded?.amr?.some(v => PHISHING_RESISTANT_AMR.includes(v));
}
```

**.NET (Microsoft.Identity.Web)**:
```csharp
// Program.cs
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddMicrosoftIdentityWebApi(options => {
        options.Audience = "<app-b-client-id>";
    },
    options => {
        options.TenantId = "<tenant-id>";
        options.Instance = "https://<tenant>.ciamlogin.com/";
        options.ClientId = "<app-b-client-id>";
    });

// In controller — check AMR:
[Authorize]
[HttpGet("protected")]
public IActionResult Protected() {
    var amr = User.FindAll("amr").Select(c => c.Value).ToList();
    var phishingResistant = new[] { "hwk", "fido", "ngcmfa", "swk", "pop", "rsa" }
        .Any(v => amr.Contains(v));
    if (!phishingResistant) return Forbid();
    return Ok(new { message = "Phishing-resistant session verified" });
}
```

### 5.3 Third-Party / SaaS Application (OIDC)

If App B is an off-the-shelf SaaS product (e.g. Salesforce, ServiceNow, Zendesk) that supports OIDC federation:

**Required configuration in App B's OIDC settings**:

| Field | Value |
|-------|-------|
| Issuer URL | `https://<tenant>.ciamlogin.com/<tenantId>/v2.0` |
| Client ID | `<App B client_id>` |
| Client Secret | From app registration |
| Authorization endpoint | `https://<tenant>.ciamlogin.com/<tenantId>/oauth2/v2.0/authorize` |
| Token endpoint | `https://<tenant>.ciamlogin.com/<tenantId>/oauth2/v2.0/token` |
| JWKS URI | `https://<tenant>.ciamlogin.com/<tenantId>/discovery/v2.0/keys` |
| Scopes | `openid profile email offline_access` |
| Response type | `code` (PKCE for SPAs) |
| Redirect URI | Must match SPA redirect URI in CIAM app registration |

**OIDC discovery document**:
```
https://<tenant>.ciamlogin.com/<tenantId>/v2.0/.well-known/openid-configuration
```

**Claim mapping** (may require configuration in the SaaS product):

| CIAM Claim | Standard OIDC | Typical SaaS mapping |
|-----------|---------------|---------------------|
| `oid` | `sub` | User ID |
| `email` | `email` | User email (may need optional claim) |
| `name` | `name` | Display name |
| `given_name` | `given_name` | First name |
| `family_name` | `family_name` | Last name |
| `amr` | `amr` | Authentication method (custom attribute) |

**MFA enforcement in SaaS**: Most SaaS products cannot inspect `amr` claim for phishing-resistant enforcement. Options:
1. Configure SaaS to require MFA via its own CA — CIAM's SSO session still carries amr, but SaaS doesn't verify it
2. Use CIAM CA policy to enforce MFA before issuing tokens — this guarantees MFA was performed but SaaS doesn't see the specific method
3. **Custom claims**: Use a custom attribute mapped to a boolean `is_phishing_resistant` claim (requires External ID P2 or custom policy — not available in standard External ID)

---

## 6. Authenticator App / TOTP in Multi-App Context

**Reminder**: Microsoft Authenticator and TOTP are NOT available as MFA methods in External ID CIAM for local accounts.

**If App B requires Authenticator/TOTP MFA**: The recommended architecture is to federate App B's authentication through a **Workforce Entra ID tenant** that supports Microsoft Authenticator.

### 6.1 Federated Authentication Architecture

```
User (Browser)
    ↓
App B (External ID CIAM - consumer-facing)
    ↓ OIDC federation
Workforce Entra ID Tenant
    ↓ Can use: MS Authenticator, TOTP, Phone OTP, Passwordless
Passkey ← Bridges back to consumer token
```

**How to implement**:

```powershell
# In External ID tenant: Add workforce Entra ID as federated identity provider
az rest --method POST `
  --uri "https://graph.microsoft.com/v1.0/identity/identityProviders" `
  --headers "Content-Type=application/json" `
  --body '{
    "@odata.type": "#microsoft.graph.oidcIdentityProvider",
    "displayName": "Corporate Entra ID",
    "clientId": "<workforce-app-registration-client-id>",
    "clientSecret": "<workforce-app-registration-secret>",
    "issuerUri": "https://login.microsoftonline.com/<workforce-tenant-id>/v2.0",
    "scope": "openid profile email",
    "claimsMapping": {
      "userId": "oid",
      "displayName": "name",
      "email": "email"
    },
    "responseType": "code"
  }'
```

**Token bridge**:
- User signs in via Workforce Entra ID (gets Authenticator MFA → `amr: mfa` from workforce)
- External ID wraps this in a CIAM token
- CIAM token `amr` depends on what claims the workforce IdP passes through
- The workforce token's `amr` is NOT automatically bridged to CIAM's `amr`
- Result: CIAM `amr` may not reflect the specific MFA method used in workforce — app-side enforcement must rely on the CIAM token's claims

**Recommendation**: For organisations requiring Authenticator/TOTP + phishing-resistant passkeys, consider deploying **Entra External ID + Entra ID (workforce)** federation rather than relying on External ID alone. This is covered in the [WORKFORCE-TENANT-POC-PROPOSAL.md](../WORKFORCE-TENANT-POC-PROPOSAL.md).

---

## 7. User Account Migration to External ID

When migrating users from an existing identity store to CIAM External ID:

### 7.1 Bulk User Creation

```powershell
$users = Import-Csv "users.csv"  # email, displayName, tempPassword

foreach ($u in $users) {
  az rest --method POST `
    --uri "https://graph.microsoft.com/v1.0/users" `
    --headers "Content-Type=application/json" `
    --body @"
{
  "displayName": "$($u.displayName)",
  "identities": [{
    "signInType": "emailAddress",
    "issuer": "<tenant>.onmicrosoft.com",
    "issuerAssignedId": "$($u.email)"
  }],
  "passwordProfile": {
    "password": "$($u.tempPassword)",
    "forceChangePasswordNextSignIn": true
  },
  "passwordPolicies": "DisablePasswordExpiration"
}
"@
}
```

**Note**: Graph-created users have OID-based UPNs. The `email` optional claim won't populate — use Graph `/users/{oid}?$select=mail,identities` to resolve the friendly email.

### 7.2 First Sign-In Flow for Migrated Users

```
Migrated user first sign-in:
1. User enters email on App landing page
2. resolveLoginHint finds user (Graph lookup) → loginHint = friendly email
3. CIAM password page: user enters temp password
4. CIAM: forceChangePasswordNextSignIn = true → prompts password change
5. User sets new password → signed in
6. App: YELLOW banner (password only, no MFA)
   → User clicks "Sign in with passkey" (step-up) OR
   → Bootstrap: passkeyCount = 0 → BLUE banner → register passkey
7. User registers passkey → next sign-in with passkey → GREEN banner
```

### 7.3 Admin-Set Temporary Password for Initial Onboarding

For users who need an initial credential without going through self-service sign-up:

```powershell
$userId = "<migrated-user-oid>"

# Set temporary password — user must change on first sign-in
az rest --method PATCH `
  --uri "https://graph.microsoft.com/v1.0/users/$userId" `
  --headers "Content-Type=application/json" `
  --body '{
    "passwordProfile": {
      "password": "<secure-temp-password>",
      "forceChangePasswordNextSignIn": true
    }
  }'

# Deliver the temp password to the user via a secure out-of-band channel
# (e.g. encrypted email, secure messaging, in-person)
# User signs in at CIAM → enters temp password → CIAM prompts password change
# → user sets permanent password → app shows bootstrap banner → registers passkey
```

> **Note**: Temporary Access Pass (TAP) is **not available** in External ID CIAM. TAP is a workforce Entra ID feature only — the CIAM SUSI flow has no TAP input step. Use temporary passwords (`forceChangePasswordNextSignIn: true`) instead.

---

## 8. Modifications Required in App B for Passkey/Token Compatibility

| Change | Required | Reason |
|--------|----------|--------|
| Register App B with user flow (`includeApplications`) | ✅ REQUIRED | CIAM won't process auth requests otherwise |
| Update CA policy to include App B | ✅ REQUIRED | MFA enforcement won't apply |
| Add SPA redirect URIs for App B domain | ✅ REQUIRED | Token exchange fails (AADSTS9002326) |
| Set App B `clientId` in MSAL config | ✅ REQUIRED | Each app must use its own client_id |
| Grant API permissions + admin consent | ✅ REQUIRED (if managing passkeys) | Graph calls fail with 403 |
| Validate `aud` claim = App B client_id | ✅ REQUIRED (backend APIs) | Security — reject tokens for other apps |
| Inspect `amr` for phishing-resistant values | ✅ RECOMMENDED | Same enforcement pattern as App A |
| Add CIAM custom domain to App B | ✅ IF passkey registration needed | RP ID must match serving domain |
| Deploy SWA API function for App B | ✅ IF using SWA (app token proxy) | client_credentials CORS blocked from browser |
| Configure email optional claim | ⚠️ OPTIONAL | Friendly email display; fallback to Graph |
| Secret rotation process | ✅ REQUIRED | Rotate before expiry (1 year default) |
| CORS configuration (backend APIs) | ✅ IF SPA → API calls | Allow App B's origin in API CORS headers |

---

## 9. Shared vs. Separate User Flows

| Scenario | Same User Flow | Separate User Flow |
|----------|---------------|-------------------|
| Same UX for both apps | ✅ Recommended | N/A |
| Different sign-up attributes per app | ❌ Not possible | ✅ Use separate flows |
| Different IDPs per app (e.g. Google in App A, LinkedIn in App B) | ❌ | ✅ |
| Same MFA requirements | ✅ | ✅ |
| Isolated user populations | ❌ (all users share tenant) | ✅ Separate flows, same tenant |
| Performance | Single flow → faster | Multiple flows → more management |

---

## 10. Quick Reference: App B Onboarding Checklist

```
CIAM Tenant:
□ App B app registration created
□ SPA redirect URIs configured (App B domain + localhost)
□ Optional claims configured (email, given_name, family_name)
□ Client secret created and stored securely
□ API permissions granted + admin consent
□ App B added to user flow (includeApplications)
□ CA policy updated to include App B client_id

Infrastructure (if new domain for App B):
□ Front Door endpoint added for App B domain
□ DNS CNAME record created
□ Custom domain added to Front Door
□ SSL certificate provisioned

Application Code:
□ MSAL config: clientId = App B client_id
□ MSAL config: redirectUri = App B production URL
□ Token validation: aud = App B client_id
□ AMR check implemented: PHISHING_RESISTANT_AMR list
□ SWA API function deployed (if SWA hosting)
□ SWA app settings: CLIENT_ID, CLIENT_SECRET, TENANT_ID, CIAM_DOMAIN

Testing:
□ Sign in to App A with passkey → amr: fido,mfa
□ Navigate to App B → no re-authentication prompt (SSO)
□ App B token aud = App B client_id
□ App B token amr = fido,mfa (inherited from session)
□ App B GREEN banner shows (if same AMR enforcement)
□ Sign out from App A → confirm App B session also cleared
```
