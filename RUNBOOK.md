# External ID Passkey Fresh Test 2 — Setup Runbook

This runbook configures a brand-new Microsoft Entra External ID tenant and local
development environment from scratch, based on the official Microsoft sample:
<https://github.com/Azure-Samples/ms-identity-ciam-native-javascript-samples/tree/main/passkey-sample>

---

## Prerequisites

| Requirement | Notes |
|---|---|
| Node.js ≥ 20 | <https://nodejs.org/en/download> |
| Azure CLI | <https://learn.microsoft.com/en-us/cli/azure/install-azure-cli> |
| Git for Windows (includes OpenSSL) | <https://git-scm.com/download/win> |
| FIDO2-capable device | YubiKey, Windows Hello, Google PM, iCloud Keychain, etc. |
| Azure subscription | Needed to create the new tenant |

---

## Phase 1 — Create a fresh External ID tenant (manual, ~3 min)

1. Go to <https://entra.microsoft.com>
2. In the top-left tenant switcher, click **Switch tenant** → **Create a tenant**
3. Select **External** → **Continue**
4. Fill in:
   - **Organisation name**: `Passkey Fresh Test 2` (or any display name)
   - **Subdomain**: choose a unique subdomain, e.g. `passkeytest2`
     - This becomes `passkeytest2.ciamlogin.com`
   - **Country**: your region
5. Click **Review + Create** → **Create**
6. Wait ~1–2 minutes for provisioning to complete
7. Note the values you'll need for the scripts:
   - **Tenant subdomain**: `passkeytest2` (the part before `.ciamlogin.com`)
   - **Tenant (directory) ID**: found in **Entra ID** → **Overview**

> **CIAM allowlist note**: The new FIDO2 passkey feature for External ID is generally available (May 2026).
> If the passkey auth method is not present in your tenant's policy list, raise a support request.

---

## Phase 2 — Automate all Entra configuration

Open PowerShell **as your normal user** (not admin — `az login` opens a browser).

```powershell
cd C:\source\Azured\EntraExternalID\ExternalID-Passkey-FreshTest2

.\scripts\01-Setup-Entra.ps1 `
    -TenantId      "<paste-tenant-id-guid>" `
    -TenantSubdomain "passkeytest2" `
    -TestUserEmail "testuser@passkeytest2.onmicrosoft.com" `
    -TestUserPassword "P@ssw0rd1234!"
```

The script:
- Creates a **single-tenant SPA app registration** with redirect URI `https://auth.passkeytest2.ciamlogin.com:3000`
- Grants **`UserAuthMethod-Passkey.ReadWrite.All`** (application, admin-consented)
- Creates a **client secret** (1-year validity)
- **Enables FIDO2** authentication method for all users, no attestation enforcement
- Creates a **sign-up/sign-in user flow** with email+password identity provider
- Associates the app with the user flow
- Creates the **test user** (email+password local account)
- Outputs ready-to-paste `.env` values

**Copy the `.env` block from the script output** — you'll paste it in Phase 3.

---

## Phase 3 — Set up local dev environment

Open PowerShell **as Administrator** (needed for hosts file and certificate store).

```powershell
cd C:\source\Azured\EntraExternalID\ExternalID-Passkey-FreshTest2

.\scripts\02-Setup-LocalDev.ps1 `
    -TenantSubdomain "passkeytest2" `
    -TenantId        "<paste-tenant-id-guid>" `
    -ClientId        "<paste-client-id-from-phase-2>" `
    -ClientSecret    "<paste-client-secret-from-phase-2>"
```

This script:
- Adds `127.0.0.1  auth.passkeytest2.ciamlogin.com` to `C:\Windows\System32\drivers\etc\hosts`
- Generates a **self-signed TLS certificate** for `auth.passkeytest2.ciamlogin.com`
- Exports `auth-cert.pem` + `auth-key.pem` to the project root
- Installs the certificate in the **Trusted Root** store (no browser security warnings)
- Writes the **`.env`** file at the project root

---

## Phase 4 — Install dependencies

```powershell
cd C:\source\Azured\EntraExternalID\ExternalID-Passkey-FreshTest2
npm install
```

---

## Phase 5 — Run the application

You need **two terminals** — both in `ExternalID-Passkey-FreshTest2`:

### Terminal 1 — CORS proxy (forwards `client_credentials` token requests)

```powershell
npm run cors
```

Expected output:
```
CORS proxy running on http://localhost:3001
Proxying from /api ===> https://login.microsoftonline.com/<tenant-id>
```

### Terminal 2 — Vite dev server

```powershell
npm start
```

Expected output:
```
  VITE v6.x  ready in ... ms

  ➜  Local:   https://auth.passkeytest2.ciamlogin.com:3000/
```

---

## Phase 6 — Validate passkey registration

1. Open Chrome or Edge and navigate to:  
   `https://auth.passkeytest2.ciamlogin.com:3000`

2. Click **Sign in** — you'll be redirected to the External ID login page.

3. Sign in with the test user credentials:
   - Email: `testuser@passkeytest2.onmicrosoft.com`
   - Password: `P@ssw0rd1234!`

4. If MFA is not yet configured for this user, you'll be prompted to set it up
   (use Microsoft Authenticator or phone number). **MFA must be completed before
   registering a passkey.**

5. After sign-in, the app lands on the **Security** page showing your passkeys
   (initially empty).

6. Click **Add a passkey** → browser shows the native passkey creation dialog.  
   Choose one of:
   - **Windows Hello** (PIN / fingerprint)
   - **Security key** (YubiKey, etc.)
   - **Another device** (scan QR code with phone)

7. Complete the gesture. The passkey is registered via Graph API.

8. Sign out and sign back in — the browser should offer the passkey automatically.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `AADSTS50058: No session information` on redirect | MSAL redirect loop | Clear sessionStorage and cookies |
| `UserAuthMethod-Passkey.ReadWrite.All not found` | Tenant not on allowlist | Use `UserAuthenticationMethod.ReadWrite.All` fallback (script handles this automatically) |
| CORS proxy 401 on token request | Wrong `VITE_APP_SECRET` | Re-check `.env`, restart CORS proxy |
| `rp.id mismatch` on passkey creation | App served from wrong domain | Verify hosts file entry; must use `auth.<subdomain>.ciamlogin.com` |
| Browser certificate warning | Cert not in Trusted Root | Re-run `02-Setup-LocalDev.ps1` as Administrator |
| `MFA required` error on passkey page | Token lacks `ngcmfa` claim | Complete MFA on the test user account in the Entra portal first |
| Empty passkey list after registration | Graph propagation lag | Wait 30s and refresh |

---

## Architecture overview

```
Browser (https://auth.passkeytest2.ciamlogin.com:3000)
│
├─ MSAL sign-in  ──────────────────────────────── Entra External ID
│  (ngcmfa claims required)                       passkeytest2.ciamlogin.com
│
├─ client_credentials ─── CORS proxy :3001 ────── login.microsoftonline.com
│  for app token                                   (returns app token)
│
└─ Graph API (app token) ──────────────────────── graph.microsoft.com/beta
   POST /users/{oid}/authentication/fido2Methods/creationOptions
   POST /users/{oid}/authentication/fido2Methods
   GET  /users/{oid}/authentication/fido2Methods
   DELETE /users/{oid}/authentication/fido2Methods/{id}
```

**Key**: The rp.id in WebAuthn is set to `auth.passkeytest2.ciamlogin.com` (from
`creationOptions.rp.id` returned by Graph). Because the app is served from
`https://auth.passkeytest2.ciamlogin.com:3000`, the domain matches exactly — no
custom URL domain required.

---

## Relevant links

- [Sign in with passkeys in Entra External ID](https://learn.microsoft.com/en-us/entra/external-id/customers/how-to-sign-in-with-passkey)
- [Official sample (GitHub)](https://github.com/Azure-Samples/ms-identity-ciam-native-javascript-samples/tree/main/passkey-sample)
- [FIDO2 provisioning APIs](https://aka.ms/fido2provisioningapi)
- [Graph fido2AuthenticationMethod resource](https://learn.microsoft.com/en-gb/graph/api/resources/fido2authenticationmethod?view=graph-rest-beta)
- [Create an external tenant](https://learn.microsoft.com/en-us/entra/external-id/customers/quickstart-tenant-setup)
