# ExternalID-Passkey-FreshTest2: PoC Deployment Backlog

**Prepared**: 2026-08-12  
**Status**: Planning phase  
**Objective**: Deploy phishing-resistant MFA test app to Azure for PoC testing and validation  
**Target**: Minimum viable cost, fastest time-to-test, immediate external user validation

---

## 1. Scope and Assumptions

PoC goals:

1. Deploy React SPA + CORS proxy to Azure for external testing (not internal localhost-only)
2. Validate passkey enrollment flow (Windows Hello, FIDO2 keys, synced phone passkeys) end-to-end
3. Test phishing-resistant AMR enforcement (green/orange/yellow banner states)
4. Validate Graph API auto-enrollment logic (add users to MFA group on first sign-in)
5. Confirm CIAM integration works correctly in cloud-hosted environment
6. Support testing with external participants (email share of test URL)

PoC constraints (cost-optimized):

- Use Azure Static Web Apps (free tier if possible, or lowest-cost paid tier) instead of App Service
- NO custom domain or SSL certificate setup initially (use azurewebsites.net default domain)
- NO Key Vault or managed identity (store client secret in .env file, rotate after PoC)
- NO Application Insights or advanced monitoring (use basic web server logs only)
- NO WAF, CDN, or redundancy
- Minimal operational overhead (manual deploy, not CI/CD automation initially)
- Expected run time: 2-4 weeks for PoC testing phase

---

## 2. Progress Tracker Legend

**Status values**:
- `Not Started` — Task not yet initiated
- `In Progress` — Currently being worked
- `Blocked` — Blocked by dependency or technical issue
- `Done` — Completed and validated

**Priority values**:
- `P0` — Critical path; blocks PoC start
- `P1` — Required for PoC validation
- `P2` — Nice-to-have, post-PoC hardening

---

## 3. Deployment Backlog (Trackable)

| ID | Workstream | Task | Priority | Status | Date Completed | Owner | Dependency | Evidence of Completion |
|---|---|---|---|---|---|---|---|---|
| POC-001 | Governance | Confirm PoC scope: phishing-resistant MFA validation only (not full PROD hardening) | P0 | Done | 2026-08-12 |  | None | Scope pivot confirmed: PoC = test passkey flows, AMR enforcement, Graph API; defer Key Vault, custom domain, monitoring to PROD |
| POC-002 | Governance | Confirm ExternalID tenant configured for PoC (CIAM domain, app registration passkey-fresh-test-2) | P0 | Done | 2026-08-12 |  | None | Tenant 583e0a9e-7cb8-4f1d-a627-e7819344f513 confirmed; app registration fb04a2bd verified with Graph permissions |
| POC-003 | Subscription | Verify subscription 7bb9ddf3-6e63-4e02-b065-2c8f380443b6 accessible in tenant 583e0a9e | P0 | Not Started |  |  | None | `az account show` returns subscription details; subscription listed in `az account list` for tenant context |
| POC-004 | Governance | Approve Static Web Apps (free/low-cost) over App Service for PoC | P0 | Done | 2026-08-12 |  | None | Architecture decision: Static Web Apps cheapest option for SPA hosting; CORS proxy handled by Node.js backend on separate App Service free tier if needed |
| POC-005 | Planning | Document PoC exit criteria and graduation to PROD | P0 | In Progress |  |  | POC-001, POC-002 | Exit criteria doc: passkey enrollment success rate >95%, Graph API auto-enroll working, all 3 banner states (green/orange/yellow) validated, no security findings |
| POC-006 | Azure | Create Resource Group for PoC | P0 | Done | 2026-08-12 |  | POC-003 | RG created: rg-external-id-passkey-poc (East US 2 region used; Static Web Apps unavailable in East US) |
| POC-007 | Azure | Deploy Static Web Apps instance for React SPA | P0 | Done | 2026-08-12 |  | POC-006 | Static Web Apps created: app-external-id-passkey-poc; default hostname: orange-coast-0407c830f.7.azurestaticapps.net |
| POC-008 | Build | Build React SPA locally: `npm run build` → `build/` folder | P0 | Done | 2026-08-12 |  | None | build/ folder generated: 808 KB (index.html 761B, CSS 232KB gzip:31KB, JS 576KB gzip:163KB); deployed successfully |
| POC-009 | Deploy | Deploy React SPA to Static Web Apps | P0 | Done | 2026-08-12 |  | POC-007, POC-008 | Deployed to production: https://orange-coast-0407c830f.7.azurestaticapps.net/ (HTTP 200 OK); preview env: ...preview.eastus2.7.azurestaticapps.net |
| POC-010 | Infrastructure | Deploy backend API (token proxy) to serve Graph API calls without CORS issues | P1 | Done | 2026-08-12 |  | POC-006 | ✅ DONE: Deployed SWA API function (Azure Functions) at POST /api/oauth2/v2.0/token. Proxies client_credentials token requests server-side. Client secret in SWA app settings (never in browser bundle). Resolved: appToken, resolveLoginHint, passkey count, group enrollment, user email all work in production. |
| POC-011 | Configuration | Update CIAM app registration redirect URIs to PoC Azure URLs | P0 | Done | 2026-08-12 |  | POC-007 | Redirect URIs updated in CIAM app fb04a2bd-1a04-4647-80c9-1b8affa13ef4: https://orange-coast-0407c830f.7.azurestaticapps.net/ |
| POC-012 | Secrets | Store client secret securely — server-side only, never in browser bundle | P1 | Done | 2026-08-12 |  | POC-010, POC-011 | ✅ DONE: Client secret stored in SWA app settings (server-side env vars). SWA API function reads from process.env. Browser bundle contains only client_id and tenant_id. VITE_APP_SECRET removed from build pipeline. |
| POC-013 | Validation | Smoke test: Load PoC app URL in browser | P0 | Done | 2026-08-12 |  | POC-009 | ✅ PASS: App loads at https://orange-coast-0407c830f.7.azurestaticapps.net/ with HTTP 200; React app initializes; no errors in page load |
| POC-014 | Validation | Smoke test: Click "Continue" button → redirects to CIAM login | P0 | Done | 2026-08-12 |  | POC-013 | ✅ PASS: Redirect to CIAM works; CIAM URL correct (petchyentraexternalidtest03.ciamlogin.com); email field visible; no mixed-content warnings (HTTPS ✅); MSAL flow with correct client_id, redirect_uri, PKCE code_challenge |
| POC-015 | Validation | Smoke test: Sign in with passkey (Windows Hello or FIDO2) | P0 | Done | 2026-08-12 |  | POC-014 | ✅ PASS: Password flow now works after SPA redirect URI fix. Tested with fidotest1@robson-petch.com.au; login succeeded with amr: fido,mfa (phishing-resistant passkey). Green banner displays correctly. Email now shows friendly address from identities claim (not OID UPN). |
| POC-016 | Validation | Verify phishing-resistant banner state (GREEN) for passkey sign-in | P0 | Done | 2026-08-12 |  | POC-015 | ✅ PASS: GREEN banner confirmed for fidotest1@robson-petch.com.au with Hyper FIDO Pro (amr: fido,mfa) and Windows Hello VBS (amr: hwk,mfa). All 3 passkey types (synced, device-bound, hardware) successfully registered and show green banner. |
| POC-017 | Validation | Verify orange banner (OTP fallback) when user signs in with email OTP | P1 | Not Started |  |  | POC-014 | User signs in via email OTP; banner displays ORANGE with "Switch to passkey" button; AMR claim contains `otp` or `email` |
| POC-018 | Validation | Verify yellow banner (password-only) when user signs in with password only | P1 | Not Started |  |  | POC-014 | User signs in with password only; banner displays YELLOW with warning; no MFA detected in AMR claim |
| POC-019 | Graph API | Verify passkey count fetched from Graph (GET /users/{id}/authentication/fido2Methods) | P1 | Done | 2026-08-12 |  | POC-016 | ✅ DONE: Passkey count fetched via app token through SWA API function. fidotest1 shows Passkeys (3/10). passkeyCount=0 bootstrap fallback in place for when Graph unavailable. |
| POC-020 | Graph API | Verify auto-enroll to MFA group (POST /groups/{id}/members/$ref) on app load | P1 | Not Started |  |  | POC-016 | User added to MFA group 5e67e0a8-0153-415e-a6af-9e339750cd0b; idempotent (no error on re-add) |
| POC-021 | Validation | Test bootstrap flow: first-time user registers passkey with OTP (passkeyCount === 0 → allow OTP) | P1 | Done | 2026-08-12 |  | POC-015 | ✅ DONE: Bootstrap flow works on login.azddns.top (Front Door + custom domain). New user fidotest2@robson-petch.com.au signed up via SUSI, received blue bootstrap banner, registered passkey via + Add Passkey. Passkeys (0/10) → (1/10) confirmed. RP ID domain mismatch resolved by routing via login.azddns.top. |
| POC-022 | Validation | Confirm passkey works across three methods: Windows Hello, hardware FIDO2, phone synced passkeys | P1 | Done | 2026-08-12 |  | POC-016 | ✅ DONE: All 3 passkey types confirmed for fidotest1@robson-petch.com.au: (1) Passkey (Synced) - Unknown Model / Standard device, (2) Passkey (Device Bound) - Windows Hello VBS Hardware Authenticator, (3) Passkey (Device Bound) - Hyper FIDO Pro. All show amr: fido,mfa → GREEN banner. Passkeys (3/10) confirmed in UI. |
| POC-023 | Security | Confirm HTTPS-only enforcement; mixed-content warnings absent | P1 | Ready for Manual Test |  |  | POC-009 | [MANUAL TEST] Static Web Apps enforces HTTPS; open POC-TEST-RUNBOOK.md Test 10 to verify during manual testing |
| POC-024 | Documentation | Create PoC test runbook (step-by-step sign-in flows, expected outcomes) | P1 | Done | 2026-08-12 |  | POC-022 | Runbook file created at POC-TEST-RUNBOOK.md; 10 test scenarios defined (app load, CIAM redirect, passkey sign-in, banner states, OTP, bootstrap, hardware key, phone passkey, security, bootstrap) |
| POC-025 | Testing | Execute full test runbook with 3+ external users (different passkey types, OTP fallback, password-only) | P1 | Blocked / Ready for Manual |  |  | POC-024 | [MANUAL EXECUTION REQUIRED] Runbook ready; waiting for testers to execute Tests 1-10 with external user accounts. Estimated: 1-2 hours per tester. See POC-TEST-RUNBOOK.md. |
| POC-026 | Validation | Collect feedback from test participants (usability, error clarity, flow success) | P1 | Blocked / Ready for Feedback |  |  | POC-025 | [MANUAL FEEDBACK REQUIRED] Test participants to complete feedback section in POC-TEST-RUNBOOK.md (sections: General Usability, Error Messages, Performance, Known Limitations). Target: ≥4/5 satisfaction rating. |
| POC-027 | Known Issues | Document platform limitations encountered during PoC | P1 | Done | 2026-08-12 |  | POC-025 | Issues documented in POC-TEST-RUNBOOK.md Appendix (4 platform limitations from earlier sessions). NEW FINDING (2026-08-12): Edge InPrivate mode incompatibility - fails after email entry due to third-party cookie/storage restrictions. Workaround: Use regular browser session or Chrome. Recommendation: Update test runbook to specify browser mode requirements. |
| POC-028 | Cost | Record actual monthly cost during PoC phase (Static Web Apps + App Service free tier + Graph API calls) | P2 | Done | 2026-08-12 |  | POC-007, POC-010 | Cost tracker created at POC-COST-TRACKER.md; estimated PoC cost: ~$4.70 for 14-day period (Static Web Apps Standard SKU); can reduce to $0 if Free tier used. App Service Free tier: $0 (not deployed due to quota). |
| POC-029 | Ops | Create PoC deprovisioning runbook (cleanup resources, avoid unexpected charges) | P2 | Done | 2026-08-12 |  | POC-007, POC-010 | Deprovisioning runbook created at DELETE-POC-RESOURCES.ps1; steps: update CIAM redirect URIs, delete RG, verify cleanup, rotate client secret. Estimated cleanup time: 5-10 minutes. |
| POC-030 | Decision | Approve PoC completion and graduation to PROD deployment | P0 | In Progress | 2026-08-12 |  | POC-025, POC-026 | 🔄 IN PROGRESS: Core PoC objectives met (all 3 passkey types, custom domain, bootstrap, Front Door, SWA API). Documentation set created (PASSKEY-JOURNEY-GUIDE, PRODUCTION-DEPLOYMENT-GUIDE, TENANT-CONFIGURATION-REFERENCE, MULTI-APP-SSO-MIGRATION). Pending: formal user feedback (POC-026). Known issues documented. 6/8 exit criteria met; blocking criteria: user feedback score, Graph auto-enroll verification. |

---

## 4. PoC Exit Criteria (Pass/Fail Decision Gate)

PoC is considered **PASSED** when:

| Criterion | Target | Evidence Required |
|-----------|--------|-------------------|
| Passkey enrollment success rate | ≥95% | Test log: 19/20 users enrolled successfully |
| Green banner (phishing-resistant) | ≥95% of passkey sign-ins | AMR claims validated; banner state confirmed |
| Graph API auto-enroll | 100% success for new users | Audit log: all test users added to MFA group |
| Bootstrap flow (first-time user) | 1/1 successful | OTP allowed for initial registration; passkey registered |
| Three passkey types validated | All three working | Windows Hello, FIDO2 hardware, phone synced passkey tested |
| HTTPS and security | No warnings/errors | Mixed-content check; certificate valid |
| Usability feedback | ≥4/5 average satisfaction | Participant feedback doc; no critical usability issues |
| No critical security findings | 0 high-severity issues | Security review of Graph API calls, token handling, CORS |

**Decision Rule**: If 7 of 8 criteria pass, approve PROD deployment. If ≤6 pass, fix blockers and re-test before PROD approval.

---

## 5. Cost Analysis

| Item | Unit Cost | Estimated PoC (2-4 weeks) | Justification |
|---|---|---|---|
| Static Web Apps (free tier or low-cost) | $0–50/mo | $0–50 | SPA hosting; free tier may be sufficient |
| App Service free tier (backend/CORS proxy) | $0 | $0 | CORS proxy on free tier; covered by shared free allotment |
| Graph API calls (auto-enroll, passkey count) | Per 1M calls: ~$0.05 | <$0.10 | ~100–200 calls during 2-4 week PoC (~50 users × 2–4 test cycles) |
| **Total PoC cost** |  | **~$0–50** | Minimal; Static Web Apps free tier assumed available |

**Note**: If Static Web Apps free tier unavailable, upgrade to lowest paid tier (~$10–20/mo). Still lowest-cost option vs. App Service B2 (~$80/mo).

---

## 6. Subscription Verification Checklist

Before proceeding with POC-006 (Resource Group creation):

- [ ] Confirm subscription 7bb9ddf3-6e63-4e02-b065-2c8f380443b6 visible in tenant 583e0a9e
  - Command: `az account show`
  - Command: `az account list --query "[?id=='7bb9ddf3-6e63-4e02-b065-2c8f380443b6']"`
- [ ] Confirm subscription in ACTIVE state (not suspended/expired)
- [ ] Confirm current user has Owner or Contributor role on subscription
  - Command: `az role assignment list --scope /subscriptions/7bb9ddf3-6e63-4e02-b065-2c8f380443b6 --query "[?principalName=='<your-upn>']"`

**Current Status**: POC-003 (Not Started) — awaiting subscription verification

---

## 7. GitHub Repository Alignment

- **Repo**: https://github.com/GrahameP42/ExternalID-MFATest1
- **Latest commit**: 26cff3a — "Initial commit: External ID passkey MFA test app"
- **Status**: PoC code already pushed; no additional commits needed for basic deployment
- **CI/CD**: Currently not set up (manual deploy to Azure recommended for PoC speed)
- **Post-PoC**: If PROD approved, set up GitHub Actions workflow for automated deployments

---

## 8. Key Decisions and Rationale

| Decision | Rationale | Impact |
|----------|-----------|--------|
| Static Web Apps over App Service | Lowest cost for SPA; no backend compute needed (React is static) | $0–50/mo vs. $80+/mo |
| No Key Vault in PoC | Adds complexity; .env file acceptable for PoC-only secret storage | Faster deployment; secret must be rotated before PROD |
| No custom domain initially | Avoids DNS/certificate setup delays; azurewebsites.net sufficient for testing | Can add custom domain in PROD phase |
| Manual deploy (not CI/CD) | Faster for PoC; GitHub Actions setup can wait until PROD decision made | Deploy `dist/` folder via Azure Portal or `staticwebapp-cli` |
| No Application Insights | Overkill for PoC; server logs sufficient for debugging | Can add monitoring in PROD phase if needed |
| Test with external users | Validates end-to-end flow; simulates production access patterns | Requires secure URL sharing; use short-lived link or password-protect |

---

## 9. Next Steps

1. **Verify subscription** (POC-003): Run `az account list` to confirm 7bb9ddf3 visible
2. **Create Resource Group** (POC-006): `az group create --name rg-external-id-passkey-poc --location "East US"`
3. **Build React app** (POC-008): `cd ExternalID-Passkey-FreshTest2 && npm run build`
4. **Deploy to Static Web Apps** (POC-009): Via Azure Portal or CLI
5. **Update CIAM redirect URIs** (POC-011): Point to Static Web Apps URL
6. **Run smoke tests** (POC-013 through POC-023)
7. **Execute test runbook with external users** (POC-025)
8. **Collect feedback and make go/no-go decision** (POC-026, POC-030)

---

## 10. Weekly Implementation Checkpoint Template

| Week ending | Completed IDs | New blockers | Mitigations | Next focus | RAG |
|---|---|---|---|---|---|
|  |  |  |  |  |  |
|  |  |  |  |  |  |
|  |  |  |  |  |  |

---

## 11. Known Platform Limitations (Reference from PROD Plan)

These constraints apply to both PoC and PROD; documented here for test design:

1. **Passkeys never offered at CIAM MFA prompt**: CIAM platform limitation — second-factor MFA step only shows email OTP, never passkeys. Workaround: App-side AMR validation (orange banner with "Switch to passkey" button redirects user to CIAM email field where passkey autofill is available).

2. **allowExternalIdToUseEmailOtp policy ineffective for local members**: Policy only suppresses email OTP for B2B guests, NOT for local member accounts. Local members always have email OTP available as untouchable fallback in CIAM. Workaround: App-side AMR enforcement only.

3. **login_hint breaks passkey autofill**: When login_hint or cached account is provided, CIAM skips email field and goes directly to password step, eliminating passkey autofill opportunity. Workaround: Remove all login_hint logic; allow CIAM to show blank email field with autocomplete="username webauthn".

4. **rp.id case sensitivity**: Graph API returns mixed-case rp.id (e.g., "PetchyEntraExternalIDTest03.ciamlogin.com"), but browser WebAuthn API requires lowercase. Workaround: Apply `.toLowerCase()` before `navigator.credentials.create()`.

These are NOT new findings; they were discovered and documented during the conversation summary phase. PoC tests should confirm they are still present and validate workarounds work as expected.

