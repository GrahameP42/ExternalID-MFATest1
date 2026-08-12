# B2B Guest vs Local Member Accounts — Identity Architecture

**Applies to**: Microsoft Entra External ID (CIAM)  
**Topic**: Home-Realm Discovery (HRD), MSA federation, account type differences, passkey limitations  
**Last Updated**: 2026-08-12

---

## 1. Account Types in External ID CIAM

External ID supports two fundamentally different kinds of user objects:

| Property | **Local Member Account** | **B2B Guest Account** |
|----------|--------------------------|----------------------|
| Created by | Self-service sign-up (SUSI) or Graph API | Invitation or federated sign-in |
| `userType` | `Member` | `Guest` |
| `creationType` | `LocalAccount` | `Invitation` or `ExternalAzureAD` |
| Authentication | CIAM handles directly (email+password, FIDO2) | Delegated to home identity provider |
| Identity issuer | `<tenant>.onmicrosoft.com` | `MicrosoftAccount`, `Google`, `ExternalAzureAD`, etc. |
| Passkeys managed by | CIAM tenant (via Graph `fido2Methods`) | Home IdP — invisible to CIAM |
| AMR in CIAM token | Reflects actual method used (`fido`, `hwk`, `otp`, etc.) | Often empty `amr: []` |
| Suitable for phishing-resistant RP enforcement | ✅ YES | ❌ NO |

---

## 2. Local Member Account — Full Detail

A local member account is created directly in the CIAM tenant. The user's credentials (password hash, FIDO2 public keys) are stored by CIAM.

**Example users in this tenant**:
- `fidotest1@robson-petch.com.au` — local member
- `fidotest2@robson-petch.com.au` — local member
- `testuser@petchyentraexternalidtest03.onmicrosoft.com` — local member (Graph-created)

**Graph identity object** for a local member:
```json
{
  "identities": [
    {
      "signInType": "emailAddress",
      "issuer": "petchyentraexternalidtest03.onmicrosoft.com",
      "issuerAssignedId": "fidotest1@robson-petch.com.au"
    },
    {
      "signInType": "userPrincipalName",
      "issuer": "petchyentraexternalidtest03.onmicrosoft.com",
      "issuerAssignedId": "2572b390-4cb0-4405-8a80-519c13676766@petchyentraexternalidtest03.onmicrosoft.com"
    }
  ]
}
```

**Sign-in flow**:
```
User enters email → CIAM identifies as local account (issuer matches tenant)
                 → CIAM shows password field (no HRD redirect)
                 → User authenticates: password OR passkey
                 → CIAM issues token with accurate AMR
```

**Passkey management**:
- Passkeys registered via `POST /users/{oid}/authentication/fido2Methods` (app-only token)
- Passkeys stored against RP ID `login.azddns.top` (custom URL domain)
- Visible in `GET /users/{oid}/authentication/fido2Methods`
- Managed by our app's PasskeysSection UI (Add, list, delete)

**CIAM token AMR** for local member with passkey:
```json
{ "amr": ["fido", "mfa"] }     // FIDO2 hardware key or synced passkey
{ "amr": ["hwk", "mfa"] }      // Windows Hello device-bound
```

---

## 3. B2B Guest Account — Full Detail

A B2B guest is a user whose primary identity lives in a **different identity system** (Microsoft Account, Google, another Entra tenant). They exist in the CIAM tenant as a guest object — a thin shell that holds their external identity reference.

**Example user in this tenant**:
- `g.petch@gmail.com` — B2B guest backed by Microsoft Account (MSA)

**Graph identity object** for an MSA guest:
```json
{
  "userType": "Guest",
  "identities": [
    {
      "signInType": "federated",
      "issuer": "ExternalAzureAD",
      "issuerAssignedId": "<MSA object ID>"
    }
  ]
}
```

Note: The `issuer` is **not** `petchyentraexternalidtest03.onmicrosoft.com`. This is why `resolveLoginHint` (which filters by `issuer eq '<tenant>.onmicrosoft.com'`) returns `null` for B2B guests — they don't match the local issuer filter, correctly preventing their email from being passed as `login_hint`.

---

## 4. Home-Realm Discovery (HRD)

HRD is the process by which CIAM determines where to send the user for authentication based on their email address.

```
User enters email → CIAM evaluates the domain:

  @gmail.com, @outlook.com, @hotmail.com, @live.com
      → CIAM detects: Microsoft Account (MSA) domain
      → HRD decision: Redirect to login.live.com
      → login.live.com authenticates the user
      → MSA token returned to CIAM
      → CIAM issues CIAM token wrapping MSA identity

  @robson-petch.com.au (local member email)
      → CIAM looks up: is this a local account in tenant?
      → YES: handle authentication directly (no redirect)
      → CIAM shows password/passkey UI
```

**HRD is NOT triggered** when `login_hint` contains an OID-based UPN (`<uuid>@tenant.onmicrosoft.com`). This is the original purpose of `resolveLoginHint` — to bypass HRD for known local members by passing the internal UPN instead of the user-facing email. However, we now pass the friendly email as `loginHint` (since local accounts resolve correctly by email), and B2B guests return `null` from `resolveLoginHint` (no `loginHint` sent → HRD handles them naturally).

---

## 5. What Happens When g.petch@gmail.com Signs In

```
Step 1: Landing page
  User enters g.petch@gmail.com → resolveLoginHint(email)
  Graph filter: identities/any(i: issuer eq 'petchyentraexternalidtest03.onmicrosoft.com')
  Result: No match (issuer is ExternalAzureAD, not local)
  → resolveLoginHint returns null
  → No login_hint sent to CIAM

Step 2: CIAM receives auth request (no login_hint)
  CIAM email field appears
  User enters g.petch@gmail.com
  CIAM HRD: @gmail.com → detected as potential MSA address
  CIAM redirects to login.live.com

Step 3: login.live.com authenticates the user
  MSA shows: password, or passkey (if registered with MSA), or phone OTP
  User authenticates using their MSA passkey (Android phone / Google PM)
  login.live.com issues MSA token

Step 4: CIAM receives MSA token
  CIAM validates MSA token
  CIAM issues CIAM token for the guest object:
    {
      "aud": "<CIAM-app-client-id>",
      "iss": "https://petchyentraexternalidtest03.ciamlogin.com/...",
      "sub": "<CIAM-guest-OID>",
      "amr": []    ← EMPTY — MSA authentication method not forwarded
    }

Step 5: RP (our app) receives token
  hasPhishingResistantMfa(token) → false (amr is empty)
  mfaElevated → false
  Banner: YELLOW — "Multi-factor authentication is required"
  PasskeysSection: disabled (no ngcmfaExpiry)
  GET /users/{oid}/authentication/fido2Methods → [] (empty, no CIAM passkeys)
```

**Root cause of empty AMR**: Microsoft classifies MSA passkeys as an "account sign-in method" rather than an "account verification" (MFA) factor. When MSA authenticates and passes the result to CIAM, the CIAM federation layer does not map the MSA authentication method to an `amr` claim in the resulting CIAM token. This is a platform behaviour, not a configuration issue.

---

## 6. Passkeys: Where They Live

### For Local Member Accounts (fidotest1, fidotest2)

```
Passkey credential is stored:
  ┌─────────────────────────────────────────────────────────┐
  │  Microsoft Graph                                         │
  │  /users/{oid}/authentication/fido2Methods               │
  │  RP ID: login.azddns.top                               │
  │  Tenant: petchyentraexternalidtest03                    │
  └─────────────────────────────────────────────────────────┘

Physical location depends on type:
  Device-bound (Windows Hello VBS): TPM chip on the local machine
  FIDO2 hardware key: Key material inside the security key
  Synced passkey: Cloud service (Google Password Manager, iCloud Keychain)
                  Synced to registered devices of that account

  In ALL cases: the public key is stored in the CIAM tenant via Graph.
  The private key NEVER leaves the authenticator.
```

Our app manages these via the SWA API function (app token → Graph `fido2Methods` endpoints).

### For B2B Guest Accounts (g.petch@gmail.com)

```
Passkey credential is stored at the home IdP:
  ┌─────────────────────────────────────────────────────────┐
  │  Microsoft Account (login.live.com)                     │
  │  /authentication/fido2Methods (MSA Graph endpoint)      │
  │  RP ID: login.live.com (NOT login.azddns.top)          │
  └─────────────────────────────────────────────────────────┘

  Completely separate from our CIAM tenant.
  Our app CANNOT read, create, or delete these passkeys.
  They are not visible in our CIAM tenant's Graph.
```

---

## 7. Impact on the RP Application

| Behaviour | Local Member | B2B Guest |
|-----------|-------------|-----------|
| `resolveLoginHint` finds user | ✅ Yes (issuer matches tenant) | ❌ No (foreign issuer) |
| `login_hint` passed to CIAM | ✅ Friendly email | ❌ None (HRD handles naturally) |
| CIAM handles auth directly | ✅ Yes | ❌ No (delegates to home IdP) |
| FIDO2 methods in Graph | ✅ Visible and manageable | ❌ Empty — managed by home IdP |
| Passkey registration via RP app | ✅ Works (Graph `fido2Methods`) | ❌ Not possible |
| AMR in CIAM token reflects actual auth | ✅ Yes (`fido`, `hwk`, `otp`) | ❌ No (usually empty) |
| GREEN banner achievable | ✅ Yes (passkey sign-in) | ❌ Not reliably |
| Passkey count displayed correctly | ✅ Yes (Graph `fido2Methods`) | ❌ Shows 0 (not CIAM-managed) |
| Bootstrap passkey registration | ✅ Works | ❌ Blocked (Graph returns 405 or empty) |

---

## 8. Supported User Type for This RP

**This RP is designed for local member accounts only.**

The phishing-resistant MFA enforcement model relies on:
1. CIAM managing the user's credentials (password + FIDO2 passkeys)
2. AMR claims accurately reflecting the authentication method
3. The app being able to register, list, and delete passkeys via Graph

None of these work for B2B guest accounts. Organisations with B2B guest users who require phishing-resistant MFA should:

- **Option A**: Migrate B2B guests to local member accounts (create local accounts with the same email, migrate credentials)
- **Option B**: Use Entra External ID federated to a workforce Entra ID tenant — enforce phishing-resistant MFA at the workforce tenant level (where Microsoft Authenticator and Entra-managed passkeys are supported), bridge the result to External ID via OIDC federation
- **Option C**: Accept that B2B guests use their home IdP's MFA and rely on CA policy (`builtInControls: ["mfa"]`) without phishing-resistant validation at the RP layer

---

## 9. Detecting Account Type at Sign-In

If your application needs to differentiate at runtime:

```javascript
// From the decoded CIAM access token:
function isLocalMember(decodedToken) {
    // Local accounts have preferred_username = <oid>@<tenant>.onmicrosoft.com
    // OR email claim is present (if optional claim configured)
    // Reliable check: look for the tenant issuer in the token
    return decodedToken?.iss?.includes(appConfig.tenantId);
    // OR check idp claim (not always present):
    // return !decodedToken?.idp || decodedToken?.idp === appConfig.tenantId;
}

// Via Graph (most reliable — use app token):
async function getUserType(appToken, userId) {
    const resp = await fetch(
        `https://graph.microsoft.com/v1.0/users/${userId}?$select=userType,creationType,identities`,
        { headers: { Authorization: `Bearer ${appToken}` } }
    );
    const user = await resp.json();
    return {
        isLocalMember: user.userType === 'Member' && user.creationType === 'LocalAccount',
        isB2BGuest: user.userType === 'Guest'
    };
}
```
