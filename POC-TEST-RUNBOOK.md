# PoC Test Runbook: ExternalID-Passkey-FreshTest2

**Test Date**: 2026-08-12  
**App URL**: https://orange-coast-0407c830f.7.azurestaticapps.net/  
**Status**: Ready for manual testing

---

## Prerequisites

- Test user accounts in External ID tenant (583e0a9e-7cb8-4f1d-a627-e7819344f513)
- Passkey registered on test device (Windows Hello, FIDO2 hardware key, or phone synced passkey)
- Browser with WebAuthn support (Chrome 90+, Edge 90+, Safari 13+, Firefox 60+)
- Private browser session (to avoid cached credentials)

---

## Test Scenarios

### **Test 1: Smoke Test - App Loading**

**Objective**: Verify app loads and displays sign-in button  
**Steps**:
1. Navigate to https://orange-coast-0407c830f.7.azurestaticapps.net/
2. Observe app loads without errors
3. Verify page displays "Continue with Passkey" button
4. Check browser console (F12 → Console tab) for errors

**Expected Result**: 
- Page loads (no 404)
- Button visible
- No red errors in console (warnings OK)
- MSAL library initializes

**Result**: ☐ PASS / ☐ FAIL  
**Notes**: ___________________________________________________________

---

### **Test 2: CIAM Redirect**

**Objective**: Verify correct redirect to CIAM login  
**Steps**:
1. From home page, click "Continue with Passkey" button
2. Observe redirect to CIAM login page
3. Verify URL shows CIAM tenant domain: `petchyentraexternalidtest03.ciamlogin.com`
4. Verify email input field is visible (should show passkey autofill suggestion if passkey registered)

**Expected Result**:
- Redirect succeeds (no errors)
- CIAM page loads
- Email field visible
- No mixed-content warnings (HTTPS everywhere)

**Result**: ☐ PASS / ☐ FAIL  
**Notes**: ___________________________________________________________

---

### **Test 3: Passkey Sign-In (Windows Hello)**

**Objective**: Test Windows Hello passkey authentication  
**Steps**:
1. On CIAM login page, click email field
2. Observe browser autofill popup showing Windows Hello passkey
3. Click on Windows Hello option
4. Complete Windows Hello unlock (face/fingerprint/PIN)
5. Observe redirect back to PoC app

**Expected Result**:
- Windows Hello challenge appears
- Unlock succeeds
- Redirect back to app succeeds
- App displays security banner (color indicates MFA state)

**Result**: ☐ PASS / ☐ FAIL  
**Notes**: ___________________________________________________________

---

### **Test 4: Verify Phishing-Resistant Banner (GREEN)**

**Objective**: Confirm green banner displays for Windows Hello sign-in  
**Steps**:
1. After successful Windows Hello sign-in, observe banner at top of Security page
2. Verify banner color is GREEN
3. Verify banner text says "Phishing-resistant MFA active"
4. Open browser console (F12 → Console) and check for error messages

**Expected Result**:
- Banner displays GREEN
- Text indicates phishing-resistant MFA is active
- No errors in console
- Access token decoded successfully (token should contain amr claim with `hwk` or `fido`)

**Result**: ☐ PASS / ☐ FAIL  
**Amr Claim Observed**: _______________ (should include hwk, fido, or ngcmfa)  
**Notes**: ___________________________________________________________

---

### **Test 5: Email OTP Sign-In (Orange Banner)**

**Objective**: Test fallback to email OTP and verify orange banner  
**Steps**:
1. Sign out (if still logged in)
2. Navigate back to app home page
3. Click "Continue with Passkey"
4. On CIAM login page, do NOT use passkey autofill
5. Instead, enter email address and click Continue
6. Complete password sign-in
7. When prompted for MFA, select "Verify with email" (or similar OTP option)
8. Enter OTP code received in email
9. Complete sign-in and return to app

**Expected Result**:
- Sign-in succeeds
- App displays ORANGE banner
- Banner text indicates "Please use passkey" or similar warning
- Banner has "Switch to Passkey" button

**Result**: ☐ PASS / ☐ FAIL  
**Amr Claim Observed**: _______________ (should include otp or email)  
**Notes**: ___________________________________________________________

---

### **Test 6: Password-Only Sign-In (Yellow Banner)**

**Objective**: Test password-only (no MFA) and verify yellow banner  
**Steps**:
1. Sign out
2. Navigate back to app
3. Click "Continue with Passkey"
4. On CIAM login page, enter email and password
5. When prompted for MFA, attempt to skip or close the prompt (if available)
6. OR: If user account allows password-only (not required to enforce MFA), sign in without MFA

**Expected Result**:
- Sign-in succeeds (if no MFA required)
- App displays YELLOW banner
- Banner text indicates "Password only - MFA not used" or warning
- Amr claim does NOT contain hwk, fido, or otp

**Result**: ☐ PASS / ☐ FAIL  
**Amr Claim Observed**: _______________ (should NOT include hwk, fido, otp, mfa)  
**Notes**: ___________________________________________________________

---

### **Test 7: FIDO2 Hardware Key Sign-In**

**Objective**: Test hardware security key (e.g., Hyper FIDO Pro) authentication  
**Prerequisites**: Physical FIDO2 hardware key registered in CIAM for this user  
**Steps**:
1. Sign out
2. Navigate back to app
3. Click "Continue with Passkey"
4. On CIAM login page, click email field
5. Observe autofill popup showing FIDO2 hardware key
6. Click hardware key option
7. Insert key and complete biometric/PIN unlock

**Expected Result**:
- Hardware key is offered as autofill option
- Key insertion and unlock succeeds
- Redirect back to app succeeds
- App displays GREEN banner
- Amr claim contains `fido` (not hwk)

**Result**: ☐ PASS / ☐ FAIL  
**Amr Claim Observed**: _______________ (should include fido)  
**Notes**: ___________________________________________________________

---

### **Test 8: Phone Synced Passkey Sign-In**

**Objective**: Test synced phone passkey (Google Password Manager / iCloud Keychain) via QR code  
**Prerequisites**: Passkey registered in Google Password Manager (Android) or iCloud Keychain (iOS)  
**Steps**:
1. Sign out
2. Navigate back to app
3. Click "Continue with Passkey"
4. On CIAM login page, click email field
5. Observe autofill popup showing "Sign in with phone" or QR code option
6. Select phone passkey option
7. QR code appears
8. Scan QR code with phone (or phone auto-offers if nearby)
9. Complete biometric/PIN on phone
10. CIAM completes sign-in and redirects

**Expected Result**:
- QR code appears
- Phone scan succeeds
- Phone biometric/PIN triggers
- Redirect back to app succeeds
- App displays GREEN banner
- Amr claim contains `fido` or `pop` (proof of possession)

**Result**: ☐ PASS / ☐ FAIL  
**Amr Claim Observed**: _______________ (should include fido or pop)  
**Notes**: ___________________________________________________________

---

### **Test 9: First-Time User Bootstrap (OTP-Allowed Registration)**

**Objective**: Test new user with no passkeys can use OTP to register passkey  
**Prerequisites**: New test user account with no passkeys registered yet  
**Steps**:
1. Create new test user in External ID tenant (or use new account)
2. Navigate to app
3. Click "Continue with Passkey"
4. Sign in with email/password
5. Complete MFA (email OTP is OK at this stage)
6. Observe app displays BLUE banner or info message: "Complete passkey registration"
7. Click "Register Passkey" button
8. Complete passkey registration (Windows Hello or FIDO2)
9. Sign out
10. Sign back in using registered passkey

**Expected Result**:
- First sign-in with OTP succeeds
- Blue/info banner displays
- Passkey registration flow accessible
- Passkey registration succeeds
- Second sign-in with passkey shows GREEN banner

**Result**: ☐ PASS / ☐ FAIL  
**Bootstrap Banner Observed**: BLUE / INFO / OTHER: _____________  
**Notes**: ___________________________________________________________

---

### **Test 10: Security Verification**

**Objective**: Verify HTTPS enforcement and no mixed-content warnings  
**Steps**:
1. Navigate to app (should auto-upgrade to HTTPS if typed http://)
2. Open browser console (F12 → Console tab)
3. Look for warnings: "Mixed Content" or "insecure"
4. Navigate through sign-in flow
5. Check Network tab (F12 → Network) to verify all requests are HTTPS

**Expected Result**:
- All requests use HTTPS
- No mixed-content warnings
- No "insecure" warnings
- Certificate is valid (no certificate errors)

**Result**: ☐ PASS / ☐ FAIL  
**Certificate Status**: Valid / Expired / Other: _____________  
**Mixed-Content Warnings**: None / Present: _____________  
**Notes**: ___________________________________________________________

---

## Summary

**Total Tests Executed**: _____ / 10  
**Tests Passed**: _____ / 10  
**Tests Failed**: _____ / 10  
**Pass Rate**: _____%

**Critical Blockers Found**:
- [ ] Yes (describe): ___________________________________________________
- [ ] No

**Minor Issues Found**:
- [ ] Yes (describe): ___________________________________________________
- [ ] No

**Go/No-Go Recommendation**:
- [ ] GO — Recommend PROD deployment (if ≥7/10 pass, no critical blockers)
- [ ] NO-GO — Fix blockers before PROD (if ≤6/10 pass or critical blockers present)

**Tester Name**: ___________________________  
**Test Date**: ___________________________  
**Browser**: ___________________________  
**Device**: ___________________________  

---

## Notes and Observations

**General Usability**:
(How intuitive is the flow? Any confusing steps?)

___________________________________________________________________________

___________________________________________________________________________

**Error Messages**:
(Were error messages clear and helpful? Any cryptic errors?)

___________________________________________________________________________

___________________________________________________________________________

**Performance**:
(How fast was the app? Any lag or slow page loads?)

___________________________________________________________________________

___________________________________________________________________________

**Known Limitations** (for reference):

1. **Passkeys never offered at CIAM MFA prompt**: CIAM platform limitation. Passkeys work as first-factor only (email field autofill), not as second-factor MFA option. Workaround: Orange banner with "Switch to Passkey" button.

2. **allowExternalIdToUseEmailOtp only for B2B**: Policy doesn't affect local member accounts. Email OTP always available as fallback for local users.

3. **login_hint breaks autofill**: If app provides login_hint, CIAM skips email field and goes to password step (no passkey autofill). Workaround: App never sends login_hint.

4. **rp.id case sensitivity**: Graph returns mixed-case, browser requires lowercase. Workaround: Applied in PasskeyService.js.

---

## Appendix: How to Read AMR Claims

After signing in, the app displays the access token. To verify AMR (Authentication Methods Reference) claims:

1. Open browser console (F12)
2. Look for log message: `AMR:` or `Token decoded`
3. Verify the amr array contains expected values:
   - **`hwk`** = Windows Hello / Hardware-bound key
   - **`fido`** = FIDO2 security key
   - **`pop`** = Phone possession (synced passkey)
   - **`otp`** = One-Time Password (email/SMS)
   - **`mfa`** = Multi-Factor Authentication (general flag)
   - **`pwd`** = Password only

**Example valid claims**:
- Passkey-only sign-in: `["hwk", "mfa"]` or `["fido", "mfa"]` → GREEN banner ✅
- Email OTP: `["otp", "mfa"]` or `["email"]` → ORANGE banner ⚠️
- Password-only: `["pwd"]` → YELLOW banner ⚠️

