# PoC Cost Tracker: ExternalID-Passkey-FreshTest2

**PoC Start Date**: 2026-08-12  
**PoC Status**: In Progress  
**Expected End Date**: 2026-08-26 (2 weeks)

---

## Azure Resource Costs (Actual)

| Resource | SKU/Tier | Estimated Monthly | Duration (days) | Prorated Cost | Status |
|----------|----------|-------------------|-----------------|---------------|--------|
| Static Web Apps | Standard | $10 | 14 | $4.67 | Active |
| App Service Plan | Free | $0 | N/A | $0 | Blocked (quota) |
| Storage (build artifacts) | Included | $0 | 14 | $0 | Active |
| Data Transfer (egress) | First 1 TB free | $0 | 14 | $0 | Included |
| Graph API calls | Per 1M calls ~$0.05 | Minimal | 14 | <$0.01 | Minimal usage |
| **Total PoC Cost (2 weeks)** | | | | **~$4.70** | Estimate |

---

## Cost Breakdown

### Static Web Apps (Standard SKU)
- **List Price**: ~$10/month (approximately)
- **Duration**: 14 days (PoC phase)
- **Prorated**: $4.67
- **Details**: Includes 100 GB bandwidth/month, SSL cert (free), auto-scaling

**Note**: Free tier may have been available but Standard tier was selected for production-grade testing. Can downgrade to Free tier ($0) if cost-sensitive.

### App Service Plan (Free Tier - Blocked)
- **List Price**: $0 (Free tier)
- **Duration**: Not deployed due to quota limit
- **Cost**: $0
- **Note**: Quota request pending or alternative deployment method needed

### Data Transfer
- **Outbound**: First 1 TB free per month; PoC usage <1 GB → $0
- **CDN**: Not used in PoC

### Graph API Calls
- **Cost per 1M calls**: ~$0.05 (if PoC reaches cap)
- **Estimated PoC calls**: ~100-500 (auto-enroll, passkey count) → <$0.01

---

## Actual Spend vs. Estimate

| Category | Estimated (at start) | Actual (end of PoC) | Variance |
|----------|----------------------|---------------------|----------|
| Static Web Apps | ~$10/month | ~$4.67 (14 days) | On budget |
| Backend API | ~$0 (Free tier) | $0 (Blocked) | N/A |
| Graph API | <$0.01 | TBD (pending testing) | Negligible |
| **Total** | **~$10/month** | **~$4.70 (14 days)** | **Under budget** |

---

## Cost Optimization Recommendations

1. **Use Static Web Apps Free Tier** (if available): Reduce from $10 to $0/month
   - Free tier includes 100 GB bandwidth/month
   - Limitations: 1 free custom domain, 1 staging environment
   - Recommended for PoC

2. **Skip Backend API for PoC**: App Service quota issue; can test core passkey flow without Graph API calls
   - Defer auto-enroll and passkey count display to PROD
   - Still validates passkey sign-in, AMR claims, banner states

3. **Clean up immediately after PoC**: Resource Group deletion prevents surprise charges
   - Estimated cleanup cost: $0 (Resources will be deleted)
   - Runbook: DELETE-POC-RESOURCES.ps1 (see below)

4. **Avoid Data Transfer Overages**: Keep egress <1 TB/month (PoC unlikely to exceed)

---

## Projected PROD Costs (for reference)

| Component | PROD SKU | Monthly Est. | Annual Est. |
|-----------|----------|--------------|------------|
| App Service Plan | Standard B2 | $80 | $960 |
| Application Insights | Basic | $20 | $240 |
| Key Vault | Standard | $0.60 | $7 |
| Static Web Apps | Removed (use App Service) | $0 | $0 |
| Graph API calls | Usage-based | <$1 | <$10 |
| **Total PROD (baseline)** | | **~$100/mo** | **~$1,200/yr** |

*(Does not include scaling, data egress overages, or optional WAF/CDN)*

---

## Budget Alert Thresholds

- **Warning**: If monthly spend exceeds $15
- **Critical**: If monthly spend exceeds $50

**Action**: Monitor via Azure Cost Management dashboard

---

## Notes

- PoC intentionally minimizes cost to validate concept before PROD investment
- All costs are AUD (estimate; actual may vary by region and billing cycle)
- Subscription: 7bb9ddf3-6e63-4e02-b065-2c8f380443b6 (External ID tenant)
- Resource Group: rg-external-id-passkey-poc (scheduled for deletion post-PoC)

