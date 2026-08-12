# Passkey Journey Guide — Microsoft Entra External ID

**Scope**: Entra External ID (CIAM) with phishing-resistant MFA enforcement  
**App**: React SPA + Azure Static Web Apps + Front Door  
**RP Domain**: `login.azddns.top` (custom URL domain over CIAM ciamlogin.com)  
**Last Updated**: 2026-08-12

---

## 1. Overview: How Passkeys Work in Entra External ID

Passkeys in External ID act as **primary authentication** (first factor), not as an MFA second factor. When a user authenticates with a passkey, CIAM issues a token with `amr: [fido, mfa]` or `amr: [hwk, mfa]` — satisfying both authentication and MFA requirements in a single gesture.

This is different from workforce Entra ID, where passkeys can be offered at the MFA prompt. In External ID, the MFA picker **only offers Email OTP** — passkeys are never surfaced there. The passkey must be used as the **first factor** via the email field autofill mechanism.

```
CIAM Authentication Model:
┌─────────────────────────────────────────────────────────────────┐
│  Email Field (autocomplete="username webauthn")                  │
│  ↑ This is where passkey autofill appears                        │
│  ↓ If user enters email + clicks Next → password step           │
│     ↓ Password step: "Use your face/fingerprint/PIN/security     │
│       key instead" link → passkey assertion (primary factor)    │
│     ↓ MFA step (if CA policy requires MFA):                     │
│       ONLY Email OTP offered here — passkeys NOT offered        │
└─────────────────────────────────────────────────────────────────┘
```

### AMR Values Issued by CIAM

| Authentication Method | AMR Values | Phishing-Resistant? | Banner State |
|----------------------|------------|---------------------|--------------|
| Windows Hello (VBS device-bound) | `hwk`, `mfa` | ✅ YES | GREEN |
| FIDO2 hardware key | `fido`, `mfa` | ✅ YES | GREEN |
| Synced passkey (Google PM, iCloud) | `fido`, `mfa` (or `swk`) | ✅ YES | GREEN |
| Password + Email OTP | `otp`, `mfa` | ❌ NO | ORANGE |
| Password only | `pwd` or absent | ❌ NO | YELLOW |
| No MFA (new session) | absent | ❌ NO | BLUE (bootstrap) |

---

## 2. Flow 1: Windows Hello Device-Bound Passkey (Same Device)

**Best for**: Corporate/managed devices, desktop users, highest security  
**AMR**: `hwk`, `mfa`  
**Prerequisites**: Windows 10/11 + TPM, Edge/Chrome 90+, passkey registered on this device

### User Journey

```
1. User navigates to https://login.azddns.top/
2. Landing page: [optional email field] + [Continue button]
   ├─ User leaves email blank → no login_hint
   └─ User types email → resolveLoginHint → login_hint = typed email

3. MSAL loginRedirect → CIAM /oauth2/v2.0/authorize
   redirect_uri: https://login.azddns.top/

4. CIAM email field appears (autocomplete="username webauthn")
   ↓ Browser OS passkey UI surfaces automatically (or on field click)
   ↓ Device shows Windows Hello biometric prompt (face/fingerprint/PIN)
   ↓ User authenticates via Windows Hello
   ↓ Passkey assertion sent to CIAM

5. CIAM validates assertion → issues authorization code
6. MSAL receives code → POST /api/oauth2/v2.0/token (SWA API proxy)
   → App token issued with: amr: [hwk, mfa]

7. App decodes token:
   - accessToken.amr includes 'hwk' → hasPhishingResistantMfa() = true
   - setPhishingResistant(true)

8. SecurityPage renders:
   ┌─────────────────────────────────────────────────────────────┐
   │ 🛡 MFA verified — passkey operations are unlocked          │  ← GREEN
   │                              amr: hwk, mfa               │
   └─────────────────────────────────────────────────────────────┘
   [Passkeys (N/10)]  [+ Add Passkey]
```

### RP Decision Logic

```javascript
PHISHING_RESISTANT_AMR = ['hwk', 'fido', 'ngcmfa', 'swk', 'pop', 'rsa']

hasPhishingResistantMfa(token) = token.amr.some(v => PHISHING_RESISTANT_AMR.includes(v))
// Windows Hello: amr = ['hwk', 'mfa'] → hasPhishingResistantMfa = true
// ngcmfaExpiry = token.iat + 15 minutes (passkey operations window)
```

### Key Constraint

Passkey autofill only works when the CIAM email field is **blank** (no `login_hint`). If `login_hint` is passed, CIAM skips the email field and goes directly to the password step, bypassing autofill.

**Workaround**: If user enters email on landing page, RP passes it as `login_hint` → user lands on password page → clicks "Use your face, fingerprint, PIN, or security key instead" → Windows Hello autofill still available at this step.

---

## 3. Flow 2: FIDO2 Hardware Security Key (Cross-Platform)

**Best for**: High-security users, shared workstations, cross-device flexibility  
**AMR**: `fido`, `mfa`  
**Prerequisites**: FIDO2-compliant key (e.g. Hyper FIDO Pro, YubiKey), USB-A/C or NFC, WebAuthn-capable browser

### User Journey

```
1. Landing page → Continue (blank email recommended for passkey autofill)
2. CIAM email field appears
   ├─ Option A: User clicks into email field → browser shows "Security key" in autofill
   └─ Option B: User enters email → password page → clicks "Use your face..."

3. Browser WebAuthn prompt: "Insert and tap your security key"
   ↓ User inserts USB key, touches capacitive button
   ↓ CTAP2 assertion flows from authenticator → browser → CIAM

4. CIAM issues: amr = ['fido', 'mfa']
5. RP: hasPhishingResistantMfa() = true → GREEN banner
```

### RP Registration Flow (+ Add Passkey)

When user clicks "+ Add Passkey" with active GREEN/BLUE session:

```
1. PasskeyService.getCreationOptions(appToken, userId)
   → GET /users/{oid}/authentication/fido2Methods/creationOptions
   Response: { challenge, rp: { id: "login.azddns.top", name: "..." }, user: {...} }

2. CRITICAL: rp.id normalisation
   Graph returns: "PetchyEntraExternalIDTest03.ciamlogin.com" (mixed case)
   BUT app is served from: "login.azddns.top" (custom domain)
   
   PasskeyService OVERRIDE:
   rp.id = (appConfig.customDomain || creationOptions.rp.id).toLowerCase()
         = "login.azddns.top"
   
   WebAuthn check: Is "login.azddns.top" a registrable suffix of "login.azddns.top"? YES ✅

3. navigator.credentials.create({ publicKey: { ...creationOptions, rp: { id: "login.azddns.top" } } })
   Browser: "Touch your security key"
   User taps key → attestation object created

4. PasskeyService.registerCredential(appToken, userId, attestation)
   → POST /users/{oid}/authentication/fido2Methods
   Graph stores passkey against user account, rp.id = login.azddns.top

5. UI updates: Passkeys (N+1/10)
```

### Key Constraint

`excludeCredentials` from Graph may contain base64-padded key IDs (trailing 0/1/2 characters = padding indicator). Must be decoded via `decodeGraphCredentialId()` before passing to `navigator.credentials.create()`.

---

## 4. Flow 3: Synced Passkey (Phone / iCloud / Google Password Manager)

**Best for**: Mobile-first users, cross-device scenarios  
**AMR**: `fido`, `mfa` (or `swk` / `pop`)  
**Prerequisites**: iPhone (iOS 16+) or Android (9+) with iCloud Keychain or Google Password Manager, Bluetooth enabled on both devices, FIDO2 cross-device authentication

### User Journey

```
1. Landing page → Continue (blank email recommended)
2. CIAM email field appears
   → User clicks into email field
   → Browser shows "Use a passkey from a different device" / QR code option
   OR edge autofill shows synced passkey from saved accounts

3. QR Code flow (cross-device):
   ↓ Browser shows QR code
   ↓ User scans with phone camera
   ↓ Phone BLE handshake with desktop → FIDO2 hybrid transport
   ↓ Phone biometric (FaceID/TouchID/fingerprint) verifies identity
   ↓ Passkey assertion from phone → desktop browser → CIAM

4. CIAM issues: amr = ['fido', 'mfa'] or ['swk', 'mfa']
5. RP: hasPhishingResistantMfa() = true → GREEN banner
```

### Platform Limitation

Synced passkeys registered via the phone are registered against `login.azddns.top`. The `.well-known/webauthn` endpoint at `login.azddns.top` must be reachable for cross-device assertion. Currently CIAM's `.well-known/webauthn` at `ciamlogin.com` lists only `login.live.com` and `login.microsoftonline.com` — **not** `login.azddns.top`. The custom domain avoids this constraint because the browser's RP ID check is a direct equality match (`login.azddns.top == login.azddns.top`), not a related-origins lookup.

---

## 5. Flow 4: New User Bootstrap (Zero Passkeys)

**Best for**: First-time user onboarding  
**Trigger**: `passkeyCount === 0` (from Graph or fallback)  
**Banner State**: BLUE "Welcome! Register a passkey"

### User Journey

```
1. Landing page: User enters NEW email → Continue
   → resolveLoginHint(email) returns null (user not in directory)
   → No login_hint sent to CIAM
   → CIAM shows blank email field with "No account? Create one" link

2. CIAM SUSI sign-up flow:
   a. User enters email → CIAM sends OTP to email
   b. User verifies OTP code
   c. User sets display name
   d. User sets password
   e. CIAM creates local account → issues sign-in token

3. App receives token: amr = ['pwd'] or similar (password-only sign-up)
   passkeyCount loaded from Graph: 0

4. Banner: BLUE bootstrap mode
   ┌─────────────────────────────────────────────────────────────┐
   │ 🛡 Welcome! You must register a passkey before you can     │  ← BLUE
   │   use this app. Use + Add Passkey to set one up.          │
   └─────────────────────────────────────────────────────────────┘

5. User clicks "+ Add Passkey"
   → PasskeyService.getCreationOptions() — ngcmfaExpiry allows ops
     (bootstrap exception: passkeyCount === 0 → ops unlocked)
   → WebAuthn ceremony on login.azddns.top
   → Passkey registered → passkeyCount = 1

6. Next sign-in:
   → User authenticates via passkey → amr: fido,mfa → GREEN banner ✅
```

### RP Bootstrap Exception Logic

```javascript
// ngcmfaExpiry = passkey operations window
// Normally requires phishingResistant = true
// Bootstrap exception: passkeyCount === 0, any auth level grants ops window

const ngcmfaExpiry = phishingResistant || passkeyCount === 0
    ? calculateNgcmfaExpiration(accessToken, 15, 60)
    : null;

// PasskeysSection receives ngcmfaExpiry:
// - non-null → + Add Passkey enabled
// - null → + Add Passkey disabled (requires step-up)
```

### Why OTP Step-Up Is NOT Used for Bootstrap

CIAM Email OTP MFA (`allowExternalIdToUseEmailOtp`) for **local member accounts** returns HTTP 500 (platform bug, unfixable). The bootstrap exception bypasses the OTP requirement, allowing the first passkey to be registered immediately after password sign-up.

---

## 6. Flow 5: Password-Only Sign-In → Step-Up

**Best for**: User forgets to use passkey / signs in on a new device  
**Banner State**: YELLOW → step-up → GREEN

### User Journey

```
1. User enters email → login_hint → CIAM password page
2. User enters password → signs in with password only
   Token: amr absent or ['pwd'] → mfaElevated = false, phishingResistant = false

3. Banner: YELLOW
   ┌─────────────────────────────────────────────────────────────┐
   │ 🔔 MFA required before managing passkeys. Password only.   │  ← YELLOW
   │                                    [Sign in with passkey] │
   └─────────────────────────────────────────────────────────────┘

4. User clicks "Sign in with passkey"
   → handleStepUp() → loginRedirect({ prompt: 'select_account' })
   → CIAM account picker → user selects account
   → CIAM password page (login_hint auto-added by MSAL from account cache)
   → User clicks "Use your face, fingerprint, PIN, or security key instead"
   → Passkey assertion → token with amr: fido, mfa

5. App: phishingResistant = true → GREEN banner ✅

NOTE: prompt='select_account' used (NOT 'login') to prevent MSA federation
cascade (login.live.com redirect_uri error for MSA/B2B guest accounts).
```

---

## 7. Flow 6: OTP MFA (Non-Phishing-Resistant Path)

**For**: Users who completed email OTP as second factor (not passkey path)  
**AMR**: `otp`, `mfa`  
**Banner State**: ORANGE

### User Journey

```
1. Password + Email OTP → token amr: [otp, mfa] or [mfa]
2. Banner: ORANGE
   ┌──────────────────────────────────────────────────────────────┐
   │ 🔔 Session used OTP — not phishing-resistant. Sign in      │  ← ORANGE
   │   with passkey or security key instead. [Sign in w/ passkey]│
   └──────────────────────────────────────────────────────────────┘

3. User registers passkey via + Add Passkey (if passkeyCount > 0 → ops window active)
   OR clicks "Sign in with passkey" → step-up flow
```

### Known Platform Limitation

CIAM does NOT offer passkeys at the "Verify your identity" MFA picker. Email OTP is the only option shown there. The OTP path is therefore the ONLY available MFA second factor via the standard sign-in flow when password is used. This is why passkey-as-primary-auth (Flow 1/2/3) is the correct architecture.

---

## 8. Flow 7: MSA / B2B Guest Account

**For**: Users with Microsoft personal accounts (Outlook, Hotmail, Xbox Live, g.petch@gmail.com via MSA)  
**AMR**: Varies (MSA handles internally, CIAM wraps)

### User Journey

```
1. Landing page → blank email → Continue (no login_hint)
2. CIAM email field
3. User enters MSA email (e.g. grahame@outlook.com)
4. CIAM HRD (home-realm discovery) detects MSA account
5. CIAM redirects to login.live.com for MSA authentication
6. MSA authenticates (passkey if registered in MSA, or password+phone)
7. MSA redirects back to CIAM with authorization
8. CIAM issues CIAM token (wrapping MSA identity)

CRITICAL: Do NOT use prompt=login for MSA users.
  prompt=login cascade: CIAM → login.live.com (force re-auth)
  login.live.com rejects CIAM's redirect_uri (not registered in MSA)
  RESULT: "We're unable to complete your request" error on login.live.com

resolveLoginHint behaviour for MSA:
  → Graph filter: identities/any(i: issuer eq 'tenant.onmicrosoft.com')
  → MSA guest accounts have different issuer (e.g. 'ExternalAzureAD' or 'MicrosoftAccount')
  → Filter does NOT match → returns null → no login_hint sent → HRD works normally
```

---

## 9. RP Decision Tree (Banner State Logic)

```
On SecurityPage load:
│
├─ loading = true → Spinner
│
├─ accessTokenError → RED alert (auth failure, can't proceed)
│
├─ !userId → redirect / sign-in prompt
│
└─ Token decoded successfully:
   │
   ├─ phishingResistant = true (amr has hwk/fido/ngcmfa/swk/pop/rsa)
   │   └─ GREEN banner: "MFA verified — passkey ops unlocked"
   │       PasskeysSection: ngcmfaExpiry = now + 15min
   │
   ├─ passkeyCount === 0 (bootstrap: new user, no passkeys)
   │   └─ BLUE banner: "Welcome! Register a passkey"
   │       PasskeysSection: ngcmfaExpiry = now + 15min (bootstrap exception)
   │       + Add Passkey: ENABLED
   │
   ├─ mfaElevated = true AND phishingResistant = false (OTP path)
   │   └─ ORANGE banner: "OTP MFA — not phishing-resistant"
   │       [Sign in with passkey] button → step-up
   │       PasskeysSection: ngcmfaExpiry = null (ops DISABLED)
   │
   └─ mfaElevated = false (password-only)
       └─ YELLOW banner: "Password only — MFA required"
           [Sign in with passkey] button → step-up
           PasskeysSection: ngcmfaExpiry = null (ops DISABLED)
```

---

## 10. WebAuthn RP ID: The Custom Domain Requirement

This is the most critical architectural constraint:

```
PROBLEM:
  App served from: orange-coast-0407c830f.7.azurestaticapps.net
  Graph returns rp.id: PetchyEntraExternalIDTest03.ciamlogin.com
  Browser check: Is ciamlogin.com a suffix of azurestaticapps.net? NO → FAIL

SOLUTION:
  Route app via Front Door → custom domain: login.azddns.top
  Override rp.id in PasskeyService: (appConfig.customDomain || rp.id).toLowerCase()
                                   = "login.azddns.top"
  Browser check: Is login.azddns.top a suffix of login.azddns.top? YES → PASS

IMPORTANT: The custom domain (login.azddns.top) MUST be:
  1. Registered as a Custom URL Domain in the CIAM tenant
  2. Verified (DNS TXT record)
  3. The Front Door endpoint CNAME points to it
  4. The SPA is served from it (Front Door → Static Web Apps)
```

---

## 11. Token Claims Reference

| Claim | Description | Example |
|-------|-------------|---------|
| `amr` | Authentication methods used | `["fido", "mfa"]` |
| `oid` | Object ID (stable user identifier) | `252e47ea-...` |
| `email` | User's email (optional claim) | `fidotest1@...` |
| `sub` | Subject (app-scoped user ID) | `AAA...` |
| `iat` | Issued at (Unix timestamp) | `1754985600` |
| `exp` | Expiry (Unix timestamp) | `1754989200` |
| `aud` | Audience (client_id) | `fb04a2bd-...` |
| `iss` | Issuer | `https://petchyentraexternalidtest03.ciamlogin.com/...` |
| `preferred_username` | UPN (often OID-based for local accounts) | `252e47ea-...@tenant.onmicrosoft.com` |

**Note on `email` claim**: External ID local accounts do NOT populate the `email` claim via optional claims configuration. Email must be fetched from Graph `GET /users/{oid}?$select=mail,identities` using the app token.

---

## 12. Platform Limitations Summary

| Limitation | Impact | Workaround |
|-----------|--------|------------|
| Passkeys NOT offered at MFA picker | Can't use passkey as 2nd factor | Use as 1st factor (primary auth) |
| Email OTP returns 500 for local accounts | Can't step up via OTP | Bootstrap exception (passkeyCount=0) |
| `login_hint` skips email field | Breaks passkey autofill | Blank email → no login_hint |
| `prompt=login` cascades to MSA | login.live.com redirect_uri error | Use no prompt or `select_account` |
| `allowExternalIdToUseEmailOtp=disabled` only affects guests | Can't disable OTP for local members | Accept OTP as fallback for locals |
| `client_credentials` blocked by browser CORS | App token can't be fetched client-side | SWA API function proxy |
| Graph rp.id is mixed-case | Browser WebAuthn check is case-sensitive | `.toLowerCase()` on rp.id |
| `email` optional claim not returned by CIAM | OID UPN shown instead of email | Fetch via Graph `/users/{oid}?$select=mail` |
