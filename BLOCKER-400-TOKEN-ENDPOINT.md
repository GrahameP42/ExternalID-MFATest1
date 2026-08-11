# CRITICAL BLOCKER: 400 Token Endpoint Error

**Status**: 🔴 BLOCKER - Password flow fails after email + password entry  
**Date Discovered**: 2026-08-12  
**Affected Flow**: Password → MFA → Token Exchange  
**Error**: POST /oauth2/v2.0/token returns 400 Bad Request  
**Request ID**: 019ff31c-10c8-7211-98d0-1d5455b28d1e  

---

## Symptoms

1. User successfully enters email address (g.petch@gmail.com) on CIAM page
2. CIAM progresses to password entry screen
3. User enters password and clicks "Sign in"
4. Behind-the-scenes, CIAM attempts POST /oauth2/v2.0/token
5. CIAM token endpoint returns **400 Bad Request**
6. User sees no error; page hangs indefinitely
7. Browser DevTools Network tab shows the failed token request

---

## Root Cause Analysis

### Most Likely Causes (in order):

1. **PKCE code_verifier mismatch** (50% probability)
   - Authorization request sent code_challenge: `eM6C_Nc1Yur9I_OOAiy0d9orU8JlmmyaQPAcCA_N5_s`
   - Token request must send matching code_verifier (base64url encoded)
   - If code_verifier not sent or doesn't match → 400 Bad Request
   - **Check**: Browser DevTools → Network tab → Find token POST request → Payload tab → Look for `code_verifier` parameter

2. **Redirect URI Mismatch** (30% probability)
   - App registration has: `https://orange-coast-0407c830f.7.azurestaticapps.net/`
   - Token request must use exact same URI
   - OAuth is case-sensitive and includes path/query exactly as registered
   - **Check**: Verify CIAM app registration URIs match Static Web Apps hostname exactly

3. **State Parameter Validation Failure** (15% probability)
   - state parameter encoded in auth request: `eyJpZCI6IjAxOWZmMzE4LWMxODMtNzEwYS1hYTBhLTc5YzhlZTQxNGM0MiIsIm1ldGEiOnsiaW50ZXJhY3Rpb25UeXBlIjoicmVkaXJlY3QifX0%3D`
   - MSAL/CIAM validates state on token request
   - If state expired (>30 min) or tampered → 400
   - **Check**: Time elapsed between initial auth request and token request

4. **Missing/Invalid grant_type** (5% probability)
   - Token request must include `grant_type=authorization_code`
   - **Check**: Token POST payload should have this field

---

## Diagnostic Steps

### Step 1: Inspect Token Request Payload

1. Open **Edge DevTools** (F12)
2. Go to **Network** tab
3. Look for POST request to `...ciam.../oauth2/v2.0/token`
4. Click on it, go to **Payload** tab
5. Document the parameters sent:
   - `client_id`: Should be `fb04a2bd-1a04-4647-80c9-1b8affa13ef4`
   - `code`: Authorization code from CIAM (should be present)
   - `code_verifier`: PKCE verifier (required for PKCE flow)
   - `grant_type`: Should be `authorization_code`
   - `redirect_uri`: Should be `https://orange-coast-0407c830f.7.azurestaticapps.net/`

### Step 2: Inspect Token Response

1. Same network request, go to **Response** tab
2. Copy full JSON response
3. Look for error details:
   - `"error": "invalid_request"` → Missing/malformed parameter
   - `"error": "invalid_grant"` → Code/state/nonce invalid
   - `"error": "invalid_code_verifier"` → PKCE mismatch
   - `"error_description"`: Specific error message

### Step 3: Check CIAM App Registration

1. Azure Portal → Entra → External ID → App Registrations
2. Open `passkey-fresh-test-2` (ID: fb04a2bd-1a04-4647-80c9-1b8affa13ef4)
3. Go to **Authentication** tab
4. Verify **Redirect URIs** section contains EXACTLY:
   - `https://orange-coast-0407c830f.7.azurestaticapps.net/`
   - (No extra slashes, ports, query params)

### Step 4: Check MSAL Configuration

1. Open [ExternalID-Passkey-FreshTest2/src/authConfig.js](../src/authConfig.js)
2. Verify:
   - `redirectUri: '/'` → Should redirect to app root (relative)
   - When combined with app hostname → `https://orange-coast-0407c830f.7.azurestaticapps.net/` ✓

---

## Recovery Steps

### If PKCE Verifier is Missing:

**Affected**: MSAL library in authConfig.js must be sending code_verifier  
**Action**: Verify MSAL version ≥ 4.0 (supports PKCE by default)  
```powershell
# Check package.json
cat src/../package.json | grep "@azure/msal"
# Should show: "@azure/msal-browser": "^4.30.0" (or similar 4.x)
```

### If Redirect URI Mismatch:

**Affected**: App registration or authConfig.js  
**Action**: 
1. Get exact CIAM app registration URI: `https://orange-coast-0407c830f.7.azurestaticapps.net/`
2. Update MSAL config if needed:
   ```javascript
   redirectUri: 'https://orange-coast-0407c830f.7.azurestaticapps.net/'
   ```
3. Rebuild and redeploy

### If State Parameter Expired:

**Affected**: MSAL state TTL  
**Action**: Check auth flow timing; if >30 min between auth and token, may need to increase state TTL (if configurable)

---

## Impact Assessment

| Category | Impact |
|----------|--------|
| **PoC Testing** | 🔴 BLOCKS password flow testing (POC-015, POC-016, POC-017, POC-018) |
| **Passkey Path** | ✅ Not affected (primary passkey auth skips password step) |
| **PROD Deployment** | 🟠 CRITICAL - Cannot proceed if password path broken |
| **Exit Criteria** | ⚠️ Affects: POC-015, POC-017, POC-018 (password/OTP tests) |

**Severity**: P0 Critical  
**Must Resolve Before**: PROD decision gate (POC-030)

---

## Escalation Path

If diagnostic steps don't identify root cause:

1. **Check MSAL GitHub Issues**: Search `4.30.0 PKCE 400` or `token endpoint 400`
2. **Review Entra External ID Release Notes**: 2026-08 updates may document token endpoint changes
3. **Open Azure Support Ticket**: Attach request/response details, tenant ID, app ID
4. **Check if this affects all passwords or just this user**: Test with different user (fidotest1@robson-petch.com.au) to isolate

---

## Notes for Testing

- Passkey-only path (primary auth) does NOT use password step → should work independently
- If password path broken, PoC can still validate passkey/banner/AMR features via CIAM's "Use device" option (if available)
- Alternative: Defer password+OTP testing to PROD; focus PoC on passkey-as-primary validation

---

**Document Created**: 2026-08-12  
**Next Action**: Execute diagnostic steps above and report findings

