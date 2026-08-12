# Documentation Index

**Project**: ExternalID-Passkey-FreshTest2 — Phishing-Resistant MFA via FIDO2 Passkeys  
**Tenant**: Microsoft Entra External ID (CIAM)  
**Production URL**: https://login.azddns.top/  
**Last Updated**: 2026-08-12

---

## Document Set

| # | Document | Description |
|---|----------|-------------|
| 01 | [PASSKEY-JOURNEY-GUIDE.md](./01-PASSKEY-JOURNEY-GUIDE.md) | All passkey authentication flows and RP decision logic |
| 02 | [PRODUCTION-DEPLOYMENT-GUIDE.md](./02-PRODUCTION-DEPLOYMENT-GUIDE.md) | Full production deployment (infrastructure, DNS, Front Door, SWA) |
| 03 | [TENANT-CONFIGURATION-REFERENCE.md](./03-TENANT-CONFIGURATION-REFERENCE.md) | CIAM tenant config: auth methods, flows, app registration, CA policies |
| 04 | [MULTI-APP-SSO-MIGRATION.md](./04-MULTI-APP-SSO-MIGRATION.md) | Adding a second application: SSO, token flow, Authenticator/TOTP options |

---

## Quick Reference

### Authentication Methods Available in External ID

| Method | Phishing-Resistant | AMR | RP Banner |
|--------|-------------------|-----|-----------|
| Windows Hello (device-bound passkey) | ✅ YES | `hwk`, `mfa` | GREEN |
| FIDO2 hardware key | ✅ YES | `fido`, `mfa` | GREEN |
| Synced passkey (phone/iCloud/Google PM) | ✅ YES | `fido`, `mfa` | GREEN |
| Email OTP | ❌ NO | `otp`, `mfa` | ORANGE |
| Password only | ❌ NO | absent | YELLOW |
| Microsoft Authenticator | ❌ Not available in External ID | N/A | — |
| TOTP (Google Authenticator etc.) | ❌ Not available in External ID | N/A | — |
| SMS/Phone OTP | ❌ Limited (500 errors) | `otp`, `mfa` | ORANGE |

### Key Infrastructure Components

```
User → login.azddns.top (Front Door)
         → orange-coast-0407c830f.7.azurestaticapps.net (Static Web Apps)
              → SPA (React + MSAL)
              → /api/oauth2/v2.0/token (Azure Function — token proxy)
              ↕ Graph API (passkey management, user email, group enrollment)
         → petchyentraexternalidtest03.ciamlogin.com (CIAM)
```

### Current Environment

| Component | Value |
|-----------|-------|
| Tenant | PetchyEntraExternalIDTest03 |
| Tenant ID | 583e0a9e-7cb8-4f1d-a627-e7819344f513 |
| App Client ID | fb04a2bd-1a04-4647-80c9-1b8affa13ef4 |
| Custom Domain | login.azddns.top |
| Static Web Apps | app-external-id-passkey-poc |
| Front Door | fd-passkey-auth |
| Resource Group | rg-external-id-passkey-poc |
| MFA Group ID | 5e67e0a8-0153-415e-a6af-9e339750cd0b |
