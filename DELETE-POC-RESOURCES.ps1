# DELETE-POC-RESOURCES.ps1: PoC Deprovisioning Runbook

**Purpose**: Clean up all Azure resources created during PoC  
**Risk Level**: HIGH — This script DELETES resources. Review carefully before execution.  
**Estimated Cleanup Time**: 5-10 minutes  
**Cleanup Cost**: $0 (resources deleted = no charges)

---

## Prerequisites

- Azure CLI installed and authenticated (same context as deployment)
- Subscription: 7bb9ddf3-6e63-4e02-b065-2c8f380443b6 (External ID tenant)
- Permissions: Contributor or Owner on subscription

---

## Pre-Deletion Checklist

- [ ] PoC testing is complete
- [ ] No critical data in PoC resources needs to be preserved
- [ ] No CIAM redirect URIs still pointing to PoC app URL
- [ ] Stakeholders approved resource deletion
- [ ] Backup/snapshot taken (if needed)

---

## Script: Clean Up PoC Resources

```powershell
#!/usr/bin/env pwsh

# ==============================================================================
# PoC DEPROVISIONING SCRIPT - ExternalID-Passkey-FreshTest2
# ==============================================================================
# WARNING: This script DELETES Azure resources. Review before running.
# ==============================================================================

# Configuration
$subscriptionId = "7bb9ddf3-6e63-4e02-b065-2c8f380443b6"
$resourceGroupName = "rg-external-id-passkey-poc"
$ciamAppId = "fb04a2bd-1a04-4647-80c9-1b8affa13ef4"
$pocAppUrl = "https://orange-coast-0407c830f.7.azurestaticapps.net/"

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "PoC DEPROVISIONING SCRIPT" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan

# Step 1: Verify context
Write-Host "`n[STEP 1] Verifying Azure context..." -ForegroundColor Yellow
$currentContext = az account show 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Not logged in to Azure. Run 'az login' first." -ForegroundColor Red
    exit 1
}
$currentSub = az account show --query "id" -o tsv
Write-Host "Current subscription: $currentSub" -ForegroundColor Green

if ($currentSub -ne $subscriptionId) {
    Write-Host "WARNING: Current subscription does not match expected subscription." -ForegroundColor Yellow
    Write-Host "Expected: $subscriptionId" -ForegroundColor Yellow
    Write-Host "Current: $currentSub" -ForegroundColor Yellow
    $response = Read-Host "Continue anyway? (yes/no)"
    if ($response -ne "yes") {
        Write-Host "Aborted." -ForegroundColor Red
        exit 1
    }
}

# Step 2: Restore CIAM redirect URIs
Write-Host "`n[STEP 2] Restoring CIAM app registration redirect URIs..." -ForegroundColor Yellow
Write-Host "Removing PoC URL from CIAM app $ciamAppId" -ForegroundColor Gray

# Option A: Set to empty (requires manual re-configuration for next deployment)
# Option B: Set to localhost (for future local testing)
# Using Option B for convenience
$newRedirectUri = "https://localhost:3000/"

az ad app update --id $ciamAppId --web-redirect-uris $newRedirectUri 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ Redirect URI updated to: $newRedirectUri" -ForegroundColor Green
} else {
    Write-Host "✗ WARNING: Failed to update redirect URI. You may need to do this manually in CIAM portal." -ForegroundColor Yellow
}

# Step 3: List resources before deletion
Write-Host "`n[STEP 3] Listing resources to be deleted..." -ForegroundColor Yellow
$resources = az resource list --resource-group $resourceGroupName --output table
if ($LASTEXITCODE -eq 0 -and $resources) {
    Write-Host $resources
} else {
    Write-Host "Resource group not found or empty. Skipping." -ForegroundColor Gray
}

# Step 4: Final confirmation
Write-Host "`n[STEP 4] FINAL CONFIRMATION" -ForegroundColor Yellow
Write-Host "About to delete Resource Group: $resourceGroupName" -ForegroundColor Red
Write-Host "This will delete ALL resources including:" -ForegroundColor Red
Write-Host "  - Static Web Apps (app-external-id-passkey-poc)" -ForegroundColor Red
Write-Host "  - Any other resources in the RG" -ForegroundColor Red
Write-Host "" -ForegroundColor Red

$confirmation = Read-Host "Type 'DELETE' to confirm (or press Enter to abort)"
if ($confirmation -ne "DELETE") {
    Write-Host "Aborted." -ForegroundColor Yellow
    exit 0
}

# Step 5: Delete Resource Group
Write-Host "`n[STEP 5] Deleting Resource Group: $resourceGroupName" -ForegroundColor Yellow
Write-Host "This may take 5-10 minutes..." -ForegroundColor Gray

az group delete --name $resourceGroupName --yes 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ Resource Group deleted successfully." -ForegroundColor Green
} else {
    Write-Host "✗ ERROR: Failed to delete Resource Group." -ForegroundColor Red
    Write-Host "Try deleting manually via Azure Portal or retry the command." -ForegroundColor Yellow
    exit 1
}

# Step 6: Verify deletion
Write-Host "`n[STEP 6] Verifying deletion..." -ForegroundColor Yellow
$rg = az group exists --name $resourceGroupName 2>&1
if ($rg -eq "false") {
    Write-Host "✓ Resource Group confirmed deleted." -ForegroundColor Green
} else {
    Write-Host "✗ WARNING: Resource Group still exists. Deletion may be in progress." -ForegroundColor Yellow
}

# Step 7: Summary
Write-Host "`n[STEP 7] DEPROVISIONING COMPLETE" -ForegroundColor Green
Write-Host "================================================================================" -ForegroundColor Green
Write-Host "Summary:" -ForegroundColor Green
Write-Host "  ✓ CIAM redirect URI updated to: $newRedirectUri" -ForegroundColor Green
Write-Host "  ✓ Resource Group deleted: $resourceGroupName" -ForegroundColor Green
Write-Host "  ✓ All PoC resources removed" -ForegroundColor Green
Write-Host "  ✓ PoC charges will cease (may take up to 1 hour to stop accruing)" -ForegroundColor Green
Write-Host "" -ForegroundColor Green
Write-Host "Next steps:" -ForegroundColor Green
Write-Host "  1. Verify no charges on subscription via Cost Management" -ForegroundColor Green
Write-Host "  2. Remove .env file from ExternalID-Passkey-FreshTest2 (if present)" -ForegroundColor Green
Write-Host "  3. Archive PoC test results and logs" -ForegroundColor Green
Write-Host "  4. If PROD approved, proceed with PROD-DEPLOYMENT-BACKLOG.md" -ForegroundColor Green
Write-Host "================================================================================" -ForegroundColor Green

exit 0
```

---

## Manual Execution Steps

If PowerShell script is not available or preferred:

### Step 1: Update CIAM App Registration

```powershell
# Remove PoC redirect URI from CIAM app
az ad app update --id fb04a2bd-1a04-4647-80c9-1b8affa13ef4 --web-redirect-uris "https://localhost:3000/"
```

### Step 2: Delete Resource Group

```powershell
# Delete the entire resource group and all resources within it
az group delete --name rg-external-id-passkey-poc --yes
```

**Note**: This command will prompt for confirmation unless `--yes` flag is used. Deletion takes 5-10 minutes.

### Step 3: Verify Deletion

```powershell
# Check if resource group still exists
az group exists --name rg-external-id-passkey-poc
# Should return: false (if deletion complete)
```

---

## What Gets Deleted

| Resource | Details | Deletion Cost |
|----------|---------|----------------|
| Static Web Apps | app-external-id-passkey-poc | Charges stop immediately |
| All storage/data in RG | Build artifacts, logs | Purged |
| IP addresses (if any) | Released | No longer billed |
| DNS entries | Removed | N/A |

**Data Retention**: Azure may retain deleted resources for 14-90 days in soft-delete state before permanent purge (depends on resource type). Deleted resources are not accessible or billable.

---

## Post-Deletion Actions

1. **Verify Cleanup**:
   - Check Azure Portal → Resource Groups → Confirm rg-external-id-passkey-poc no longer exists
   - Check Cost Management → Confirm no charges from PoC resources after 1 hour

2. **Clean Up Local Files** (optional):
   ```powershell
   # Remove PoC build artifacts and environment files
   cd C:\source\Azured\EntraExternalID\ExternalID-Passkey-FreshTest2
   rm -r build/            # Remove build artifacts
   rm .env                 # Remove local .env file (DON'T COMMIT THIS)
   rm .env.local          # Remove any local overrides
   ```

3. **Rotate Client Secret** (IMPORTANT if secret was exposed):
   ```powershell
   # Generate new client secret in CIAM app registration
   # ⚠️ OLD SECRET REVOKED - DO NOT USE
   # New secret: [generated in CIAM portal after cleanup]
   az ad app credential create --id fb04a2bd-1a04-4647-80c9-1b8affa13ef4
   ```

4. **Archive Test Results**:
   ```powershell
   # Save PoC test results to archive folder
   mkdir c:\archive\poc-2026-08-12
   cp POC-TEST-RUNBOOK.md c:\archive\poc-2026-08-12\
   cp POC-COST-TRACKER.md c:\archive\poc-2026-08-12\
   ```

---

## Troubleshooting

### "Resource Group Not Found"
- Resource group may have already been deleted
- Check Azure Portal to confirm
- Continue with next steps

### "Permission Denied"
- Verify logged-in user has Contributor role on subscription
- Run: `az role assignment list --scope /subscriptions/7bb9ddf3-6e63-4e02-b065-2c8f380443b6`

### "Deletion Timeout"
- Large resource groups may take 15+ minutes to delete
- Wait and retry, or delete individual resources manually via Portal

### "CIAM App Update Failed"
- Manually update redirect URI in CIAM portal:
  - Portal.azure.com → External ID → App registrations → passkey-fresh-test-2 → Authentication
  - Remove PoC URL, set to localhost:3000 or empty
  - Save

---

## Rollback (If Accidental Deletion)

**Note**: Rollback is NOT possible. Deleted resources cannot be recovered.

**Prevention**:
- Always use `--yes` flag with caution
- Consider renaming resources before deletion as safety check
- Take backup of important configs before running

---

## Support & Escalation

If deletion fails or unexpected errors occur:

1. Check Azure Status Page: https://status.azure.com/
2. Review error messages in terminal output
3. Open Azure Support case (if subscription supports it)
4. Escalate to platform team if needed

---

**Script Version**: 1.0  
**Last Updated**: 2026-08-12  
**Author**: DevOps  
**Status**: Ready for use

