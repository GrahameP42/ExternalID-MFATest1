<#
.SYNOPSIS
    Configure a fresh Entra External ID tenant for the passkey sample app.

.DESCRIPTION
    Performs all post-tenant-creation Entra configuration required by
    https://github.com/Azure-Samples/ms-identity-ciam-native-javascript-samples/tree/main/passkey-sample

    What this script does:
      1. Creates a single-tenant SPA app registration
      2. Grants UserAuthMethod-Passkey.ReadWrite.All (falls back to
         UserAuthenticationMethod.ReadWrite.All if not yet available)
      3. Admin-consents the permission
      4. Creates a client secret
      5. Enables FIDO2 authentication method (all users, no attestation)
      6. Creates a sign-up/sign-in user flow with email+password
      7. Associates the app with the user flow
      8. Optionally creates a local-account test user
      9. Outputs ready-to-paste .env values

.PARAMETER TenantId
    GUID of the newly created External ID tenant.

.PARAMETER TenantSubdomain
    The subdomain of the tenant (e.g. "passkeytest2" for passkeytest2.ciamlogin.com).

.PARAMETER AppDisplayName
    Display name for the app registration (default: passkey-fresh-test-2).

.PARAMETER TestUserEmail
    Email address for an optional local-account test user.

.PARAMETER TestUserPassword
    Password for the test user (must meet AAD complexity requirements).

.EXAMPLE
    .\01-Setup-Entra.ps1 `
        -TenantId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
        -TenantSubdomain "passkeytest2" `
        -TestUserEmail "testuser@passkeytest2.onmicrosoft.com" `
        -TestUserPassword "P@ssw0rd1234!"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [string]$TenantSubdomain,

    [Parameter()]
    [string]$AppDisplayName = 'passkey-fresh-test-2',

    [Parameter()]
    [string]$TestUserEmail,

    [Parameter()]
    [string]$TestUserPassword
)

$ErrorActionPreference = 'Stop'
$Port = 3000
$RedirectUri = "https://auth.${TenantSubdomain}.ciamlogin.com:${Port}"
$FlowName = "${AppDisplayName}-SignUpSignIn"

function Write-Step { param([string]$Msg) Write-Host "`n$Msg" -ForegroundColor Yellow }
function Write-OK   { param([string]$Msg) Write-Host "  $Msg" -ForegroundColor Green }
function Write-Skip { param([string]$Msg) Write-Host "  $Msg" -ForegroundColor Gray }

Write-Host "=== Entra External ID Passkey Sample — Tenant Setup ===" -ForegroundColor Cyan
Write-Host "Tenant ID  : $TenantId" -ForegroundColor Gray
Write-Host "Subdomain  : $TenantSubdomain.ciamlogin.com" -ForegroundColor Gray
Write-Host "App name   : $AppDisplayName" -ForegroundColor Gray
Write-Host "Redirect   : $RedirectUri" -ForegroundColor Gray

# -------------------------------------------------------------------------
# 1. Login
# -------------------------------------------------------------------------
Write-Step "[1/8] Logging in to tenant $TenantId..."
Write-Host "  A browser window will open — sign in as a Global Admin of the new tenant." -ForegroundColor Cyan
az login --tenant $TenantId --allow-no-subscriptions --output none
if ($LASTEXITCODE -ne 0) { throw "az login failed. Ensure the account has Global Admin rights in $TenantId." }
Write-OK "Authenticated"

# -------------------------------------------------------------------------
# 2. App registration
# -------------------------------------------------------------------------
Write-Step "[2/8] Creating app registration '$AppDisplayName'..."

$existing = az ad app list --display-name $AppDisplayName --query '[0].{appId:appId,id:id}' -o json | ConvertFrom-Json
if ($null -ne $existing -and -not [string]::IsNullOrEmpty($existing.appId)) {
    $appId       = $existing.appId
    $appObjectId = $existing.id
    Write-Skip "App already exists: $appId"
} else {
    $appId = az ad app create `
        --display-name $AppDisplayName `
        --sign-in-audience AzureADMyOrg `
        --query appId -o tsv
    Write-OK "App created: $appId"
    $appObjectId = az ad app show --id $appId --query id -o tsv
}

# Set SPA redirect URI (PATCH via Graph)
$spaBody = @{
    spa = @{ redirectUris = @($RedirectUri) }
} | ConvertTo-Json -Depth 5 -Compress

az rest --method PATCH `
    --uri "https://graph.microsoft.com/v1.0/applications/$appObjectId" `
    --headers "Content-Type=application/json" `
    --body $spaBody `
    --output none
Write-OK "SPA redirect URI set: $RedirectUri"

# Ensure service principal exists
$spId = az ad sp list --filter "appId eq '$appId'" --query '[0].id' -o tsv
if ([string]::IsNullOrWhiteSpace($spId)) {
    $spId = az ad sp create --id $appId --query id -o tsv
    Write-OK "Service principal created: $spId"
} else {
    Write-Skip "Service principal exists: $spId"
}

# -------------------------------------------------------------------------
# 3. Locate Graph API permission role
# -------------------------------------------------------------------------
Write-Step "[3/8] Resolving Graph API permission role..."

$graphAppId = '00000003-0000-0000-c000-000000000000'
$allRoles   = az ad sp show --id $graphAppId --query 'appRoles' -o json | ConvertFrom-Json

# Try new targeted permission first, fall back to broad permission
$passkeyRole = $allRoles | Where-Object { $_.value -eq 'UserAuthMethod-Passkey.ReadWrite.All' } | Select-Object -First 1
if ($null -eq $passkeyRole) {
    Write-Host "  UserAuthMethod-Passkey.ReadWrite.All not found — falling back to UserAuthenticationMethod.ReadWrite.All" -ForegroundColor Magenta
    $passkeyRole = $allRoles | Where-Object { $_.value -eq 'UserAuthenticationMethod.ReadWrite.All' } | Select-Object -First 1
}
if ($null -eq $passkeyRole) {
    throw "Neither UserAuthMethod-Passkey.ReadWrite.All nor UserAuthenticationMethod.ReadWrite.All found on the Graph SP. Verify the tenant is on the FIDO2 allowlist."
}
Write-OK "Using role: $($passkeyRole.value)  (id=$($passkeyRole.id))"

# -------------------------------------------------------------------------
# 4. Assign application permission + admin consent
# -------------------------------------------------------------------------
Write-Step "[4/8] Granting application permission and admin consent..."

$existing = az ad app permission list --id $appId -o json | ConvertFrom-Json
$alreadyGranted = $existing | Where-Object {
    $_.resourceAppId -eq $graphAppId -and
    ($_.resourceAccess | Where-Object { $_.id -eq $passkeyRole.id })
}
if ($null -eq $alreadyGranted) {
    az ad app permission add `
        --id $appId `
        --api $graphAppId `
        --api-permissions "$($passkeyRole.id)=Role" `
        --output none
    Write-OK "Permission added"
} else {
    Write-Skip "Permission already present"
}

az ad app permission admin-consent --id $appId --output none
Write-OK "Admin consent granted"

# -------------------------------------------------------------------------
# 5. Create client secret
# -------------------------------------------------------------------------
Write-Step "[5/8] Creating client secret (1-year validity)..."

$clientSecret = az ad app credential reset `
    --id $appId `
    --append `
    --display-name 'passkey-dev-secret' `
    --years 1 `
    --query password -o tsv `
    --only-show-errors
Write-OK "Client secret created"

# -------------------------------------------------------------------------
# 6. Enable FIDO2 authentication method
# -------------------------------------------------------------------------
Write-Step "[6/8] Enabling FIDO2 (passkey) authentication method..."

$fido2Body = @{
    "@odata.type"                   = "#microsoft.graph.fido2AuthenticationMethodConfiguration"
    state                           = "enabled"
    isAttestationEnforced           = $false
    isSelfServiceRegistrationAllowed = $true
    includeTargets                  = @(
        @{
            targetType            = "group"
            id                    = "all_users"
            isRegistrationRequired = $false
        }
    )
} | ConvertTo-Json -Depth 10 -Compress

az rest --method PATCH `
    --uri "https://graph.microsoft.com/v1.0/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/Fido2" `
    --headers "Content-Type=application/json" `
    --body $fido2Body `
    --output none
Write-OK "FIDO2 method enabled for all users (no attestation enforcement)"

# -------------------------------------------------------------------------
# 7. Create sign-up / sign-in user flow
# -------------------------------------------------------------------------
Write-Step "[7/8] Creating sign-up/sign-in user flow '$FlowName'..."

$existingFlow = az rest --method GET `
    --uri "https://graph.microsoft.com/beta/identity/authenticationEventsFlows?`$filter=displayName eq '$FlowName'" `
    -o json 2>$null | ConvertFrom-Json

$flowId = $existingFlow.value[0].id

if ([string]::IsNullOrWhiteSpace($flowId)) {
    $flowBody = @{
        "@odata.type"  = "#microsoft.graph.externalUsersSelfServiceSignUpEventsFlow"
        displayName    = $FlowName
        conditions     = @{
            applications = @{ includeAllApplications = $false }
        }
        onInteractiveAuthFlowStart = @{
            "@odata.type"    = "#microsoft.graph.onInteractiveAuthFlowStartExternalUsersSelfServiceSignUp"
            isSignUpAllowed  = $true
        }
        onAuthenticationMethodLoadStart = @{
            "@odata.type"       = "#microsoft.graph.onAuthenticationMethodLoadStartExternalUsersSelfServiceSignUp"
            identityProviders   = @(
                @{
                    "@odata.type" = "#microsoft.graph.builtInIdentityProvider"
                    id            = "EmailPassword-OAUTH"
                }
            )
        }
        onAttributeCollection = @{
            "@odata.type"   = "#microsoft.graph.onAttributeCollectionExternalUsersSelfServiceSignUp"
            accessPackages  = @()
            attributeCollectionPage = @{
                views = @(
                    @{
                        inputs = @(
                            @{
                                attribute        = "email"
                                label            = "Email Address"
                                inputType        = "text"
                                hidden           = $true
                                editable         = $false
                                required         = $true
                                writeToDirectory = $true
                            }
                            @{
                                attribute        = "displayName"
                                label            = "Display Name"
                                inputType        = "text"
                                hidden           = $false
                                editable         = $true
                                required         = $true
                                writeToDirectory = $true
                            }
                        )
                    }
                )
            }
            attributes = @(
                @{ id = "email" }
                @{ id = "displayName" }
            )
        }
        onUserCreateStart = @{
            "@odata.type"    = "#microsoft.graph.onUserCreateStartExternalUsersSelfServiceSignUp"
            userTypeToCreate = "member"
            accessPackages   = @()
        }
    } | ConvertTo-Json -Depth 20 -Compress

    $flowResult = az rest --method POST `
        --uri "https://graph.microsoft.com/beta/identity/authenticationEventsFlows" `
        --headers "Content-Type=application/json" `
        --body $flowBody `
        -o json | ConvertFrom-Json

    $flowId = $flowResult.id
    Write-OK "User flow created: $flowId"

    # Associate app
    $includeAppBody = @{
        "@odata.type" = "#microsoft.graph.authenticationConditionApplication"
        appId         = $appId
    } | ConvertTo-Json -Compress

    az rest --method POST `
        --uri "https://graph.microsoft.com/beta/identity/authenticationEventsFlows/$flowId/conditions/applications/includeApplications" `
        --headers "Content-Type=application/json" `
        --body $includeAppBody `
        --output none
    Write-OK "App '$appId' associated with user flow"
} else {
    Write-Skip "User flow already exists: $flowId"
}

# -------------------------------------------------------------------------
# 8. Optional: create test user
# -------------------------------------------------------------------------
if (-not [string]::IsNullOrWhiteSpace($TestUserEmail)) {
    Write-Step "[8/8] Creating test user '$TestUserEmail'..."

    if ([string]::IsNullOrWhiteSpace($TestUserPassword)) {
        throw "-TestUserPassword is required when -TestUserEmail is specified."
    }

    $userBody = @{
        displayName      = "Passkey Test User"
        passwordPolicies = "DisablePasswordExpiration"
        passwordProfile  = @{
            password                      = $TestUserPassword
            forceChangePasswordNextSignIn = $false
        }
        identities = @(
            @{
                signInType       = "emailAddress"
                issuer           = "${TenantSubdomain}.onmicrosoft.com"
                issuerAssignedId = $TestUserEmail
            }
        )
    } | ConvertTo-Json -Depth 10 -Compress

    $userResult = az rest --method POST `
        --uri "https://graph.microsoft.com/v1.0/users" `
        --headers "Content-Type=application/json" `
        --body $userBody `
        -o json | ConvertFrom-Json

    $testUserId = $userResult.id
    Write-OK "Test user created (id=$testUserId)"
} else {
    Write-Step "[8/8] Skipping test user creation (no -TestUserEmail provided)"
    Write-Skip "Create a user manually in the Entra portal or re-run with -TestUserEmail / -TestUserPassword"
    $testUserId = "<create-manually>"
}

# -------------------------------------------------------------------------
# Output summary
# -------------------------------------------------------------------------
$ciamDomain = "${TenantSubdomain}.ciamlogin.com"

Write-Host "`n`n========================================" -ForegroundColor Cyan
Write-Host "  Setup complete — copy values below" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "--- .env (place at ExternalID-Passkey-FreshTest2/.env) ---" -ForegroundColor Magenta
$envOut = @"
VITE_HOST=auth.${ciamDomain}
VITE_PORT=${Port}

VITE_TENANT_ID=${TenantId}
VITE_CIAM_DOMAIN=${ciamDomain}
VITE_CLIENT_ID=${appId}

VITE_SSL_CERT=auth-cert.pem
VITE_SSL_KEY=auth-key.pem

VITE_APP_SECRET=${clientSecret}

VITE_CUSTOM_DOMAIN=
"@
Write-Host $envOut -ForegroundColor Cyan

Write-Host "--- Summary ---" -ForegroundColor Magenta
[pscustomobject]@{
    tenantId       = $TenantId
    ciamDomain     = $ciamDomain
    appId          = $appId
    appObjectId    = $appObjectId
    spId           = $spId
    flowId         = $flowId
    redirectUri    = $RedirectUri
    testUserId     = $testUserId
} | Format-List

Write-Host "Next: run scripts\02-Setup-LocalDev.ps1 to set up SSL cert and hosts file." -ForegroundColor Yellow
