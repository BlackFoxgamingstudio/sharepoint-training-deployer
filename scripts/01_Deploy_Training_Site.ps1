<#
.SYNOPSIS
    Master orchestrator for deploying a complete SharePoint Online training site.

.DESCRIPTION
    This script coordinates the end-to-end deployment of a SharePoint communication site
    for a training module. It performs the following steps in sequence:

    1. Loads configuration and validates prerequisites
    2. Creates the SharePoint communication site (or connects to existing)
    3. Uploads all training assets (images, videos, documents)
    4. Creates SharePoint modern pages with training content
    5. Applies custom branding, theme, and navigation
    6. Generates an HTML deployment report

    Each step calls a dedicated sub-script that can also be run independently.

.PARAMETER ModuleName
    The training module identifier (e.g., "Fire_Safety", "OSHA_Compliance").
    Used to locate content directories, configs, and name the site.

.PARAMETER TenantUrl
    The SharePoint Online tenant URL (e.g., "https://contoso.sharepoint.com").
    If not provided, falls back to the value in the deployment config file.

.PARAMETER SiteUrlSuffix
    The site URL suffix appended after /sites/. Defaults to the ModuleName with
    underscores replaced by hyphens (e.g., "Fire_Safety" → "fire-safety").

.PARAMETER SkipPrerequisites
    Skip the prerequisite validation checks (PnP module, connectivity, etc.).

.PARAMETER SkipBranding
    Skip the branding/theme/navigation step (Step 5).

.EXAMPLE
    .\01_Deploy_Training_Site.ps1 -ModuleName "Fire_Safety"

.EXAMPLE
    .\01_Deploy_Training_Site.ps1 -ModuleName "OSHA_Compliance" -TenantUrl "https://contoso.sharepoint.com" -SiteUrlSuffix "osha-2024"

.EXAMPLE
    .\01_Deploy_Training_Site.ps1 -ModuleName "Forklift_Operations" -SkipPrerequisites -SkipBranding

.NOTES
    Requires PnP.PowerShell module and SharePoint Online admin/site collection admin permissions.
    Dot-sources ./utils/Deploy-Helpers.ps1 for shared utility functions.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0, HelpMessage = "Training module name (e.g., 'Fire_Safety').")]
    [ValidateNotNullOrEmpty()]
    [string]$ModuleName,

    [Parameter(Mandatory = $false, HelpMessage = "SharePoint tenant URL (e.g., 'https://contoso.sharepoint.com').")]
    [string]$TenantUrl,

    [Parameter(Mandatory = $false, HelpMessage = "Site URL suffix after /sites/. Defaults to ModuleName with hyphens.")]
    [string]$SiteUrlSuffix,

    [Parameter(HelpMessage = "Skip prerequisite validation checks.")]
    [switch]$SkipPrerequisites,

    [Parameter(HelpMessage = "Skip branding, theme, and navigation application.")]
    [switch]$SkipBranding
)

# ---------------------------------------------------------------------------
# Bootstrap
# ---------------------------------------------------------------------------
$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $scriptRoot "utils" "Deploy-Helpers.ps1")

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
$banner = @"

 ╔══════════════════════════════════════════════════════════════╗
 ║         SOVEREIGN TRAINING SITE DEPLOYER v2.0               ║
 ║         SharePoint Online • Automated Deployment            ║
 ╚══════════════════════════════════════════════════════════════╝

"@
Write-Host $banner -ForegroundColor Cyan

$deploymentTimer = [System.Diagnostics.Stopwatch]::StartNew()
$deploymentId    = [guid]::NewGuid().ToString("N").Substring(0, 8)

Write-DeployLog -Message "Deployment ID: $deploymentId" -Level "Info"
Write-DeployLog -Message "Module: $ModuleName" -Level "Info"
Write-DeployLog -Message "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Level "Info"
Write-DeployLog -Message ("-" * 60) -Level "Info"

# ---------------------------------------------------------------------------
# Step 1 – Load Configuration
# ---------------------------------------------------------------------------
Write-DeployLog -Message "[Step 1/7] Loading configuration..." -Level "Info"

$deployConfig = Get-DeploymentConfig
$moduleConfig = Get-ModuleConfig -ModuleName $ModuleName

# Resolve TenantUrl – parameter takes precedence over config
if ([string]::IsNullOrWhiteSpace($TenantUrl)) {
    $TenantUrl = $deployConfig.TenantUrl
    if ([string]::IsNullOrWhiteSpace($TenantUrl)) {
        throw "TenantUrl not provided and not found in deployment config. Use -TenantUrl parameter or set TenantUrl in config."
    }
    Write-DeployLog -Message "Using TenantUrl from config: $TenantUrl" -Level "Info"
}
else {
    Write-DeployLog -Message "Using TenantUrl from parameter: $TenantUrl" -Level "Info"
}

# Ensure TenantUrl has no trailing slash
$TenantUrl = $TenantUrl.TrimEnd('/')

# ---------------------------------------------------------------------------
# Step 2 – Build Site URL
# ---------------------------------------------------------------------------
Write-DeployLog -Message "[Step 2/7] Building site URL..." -Level "Info"

if ([string]::IsNullOrWhiteSpace($SiteUrlSuffix)) {
    $SiteUrlSuffix = ($ModuleName -replace '_', '-').ToLower()
    Write-DeployLog -Message "Auto-generated SiteUrlSuffix: $SiteUrlSuffix" -Level "Info"
}
else {
    $SiteUrlSuffix = $SiteUrlSuffix.ToLower()
    Write-DeployLog -Message "Using provided SiteUrlSuffix: $SiteUrlSuffix" -Level "Info"
}

$siteUrl = "$TenantUrl/sites/$SiteUrlSuffix"
Write-DeployLog -Message "Target site URL: $siteUrl" -Level "Success"

# ---------------------------------------------------------------------------
# Step 3 – Prerequisites Check
# ---------------------------------------------------------------------------
if ($SkipPrerequisites) {
    Write-DeployLog -Message "[Step 3/7] Skipping prerequisites (SkipPrerequisites flag set)." -Level "Warning"
}
else {
    Write-DeployLog -Message "[Step 3/7] Running prerequisite checks..." -Level "Info"

    # Check PnP.PowerShell module
    $pnpModule = Get-Module -Name "PnP.PowerShell" -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $pnpModule) {
        throw "PnP.PowerShell module is not installed. Run: Install-Module PnP.PowerShell -Scope CurrentUser"
    }
    Write-DeployLog -Message "  PnP.PowerShell v$($pnpModule.Version) found." -Level "Success"

    # Verify content directory exists for the module
    $contentRoot = Join-Path (Split-Path $scriptRoot -Parent) "content" $ModuleName
    if (-not (Test-Path $contentRoot)) {
        throw "Content directory not found: $contentRoot"
    }
    Write-DeployLog -Message "  Content directory verified: $contentRoot" -Level "Success"

    # Verify config loaded properly
    if (-not $moduleConfig) {
        throw "Module configuration for '$ModuleName' could not be loaded."
    }
    Write-DeployLog -Message "  Module configuration loaded." -Level "Success"

    Write-DeployLog -Message "  All prerequisites passed." -Level "Success"
}

# ---------------------------------------------------------------------------
# Step 4 – Create or Connect to Communication Site
# ---------------------------------------------------------------------------
Write-DeployLog -Message "[Step 4/7] Creating or connecting to communication site..." -Level "Info"

$siteCreated = $false

# First, try connecting to see if the site already exists
try {
    Connect-PnPOnline -Url $siteUrl -Interactive -ErrorAction Stop
    $existingWeb = Get-PnPWeb -ErrorAction Stop
    Write-DeployLog -Message "Site already exists: $($existingWeb.Title) at $siteUrl" -Level "Warning"
    Write-DeployLog -Message "Connecting to existing site and continuing deployment..." -Level "Info"
    $siteCreated = $false
}
catch {
    Write-DeployLog -Message "Site does not exist. Creating new communication site..." -Level "Info"

    # Connect to tenant admin for site creation
    try {
        Connect-PnPOnline -Url $TenantUrl -Interactive -ErrorAction Stop
    }
    catch {
        throw "Failed to connect to tenant '$TenantUrl' for site creation: $_"
    }

    # Determine site owner
    $siteOwner = $deployConfig.SiteOwner
    if ([string]::IsNullOrWhiteSpace($siteOwner)) {
        $currentUser = Get-PnPProperty -ClientObject (Get-PnPWeb) -Property CurrentUser -ErrorAction SilentlyContinue
        $siteOwner = $currentUser.Email
        Write-DeployLog -Message "No SiteOwner in config; using current user: $siteOwner" -Level "Warning"
    }

    $siteTitle = if ($moduleConfig.SiteTitle) { $moduleConfig.SiteTitle } else { $ModuleName -replace '_', ' ' }

    # Create the communication site
    try {
        New-PnPSite -Type CommunicationSite `
            -Title $siteTitle `
            -Url $siteUrl `
            -Owner $siteOwner `
            -ErrorAction Stop
        Write-DeployLog -Message "Communication site creation initiated." -Level "Success"
    }
    catch {
        throw "Failed to create communication site: $_"
    }

    # Poll for site availability (site creation is async)
    $maxPollAttempts = 30
    $pollInterval    = 10  # seconds
    $siteReady       = $false

    Write-DeployLog -Message "Waiting for site to become available (polling every ${pollInterval}s, max ${maxPollAttempts} attempts)..." -Level "Info"

    for ($attempt = 1; $attempt -le $maxPollAttempts; $attempt++) {
        Start-Sleep -Seconds $pollInterval
        try {
            Connect-PnPOnline -Url $siteUrl -Interactive -ErrorAction Stop
            $web = Get-PnPWeb -ErrorAction Stop
            if ($web) {
                $siteReady = $true
                Write-DeployLog -Message "Site is ready after $attempt attempt(s) (~$($attempt * $pollInterval)s)." -Level "Success"
                break
            }
        }
        catch {
            Write-DeployLog -Message "  Attempt $attempt/$maxPollAttempts – site not ready yet..." -Level "Info"
        }
    }

    if (-not $siteReady) {
        throw "Site creation timed out after $($maxPollAttempts * $pollInterval) seconds. Check SharePoint admin center."
    }

    $siteCreated = $true
}

# ---------------------------------------------------------------------------
# Step 5 – Upload Assets
# ---------------------------------------------------------------------------
Write-DeployLog -Message "[Step 5/7] Uploading training assets..." -Level "Info"

$uploadScript = Join-Path $scriptRoot "03_Upload_Assets.ps1"
if (-not (Test-Path $uploadScript)) {
    throw "Asset upload script not found: $uploadScript"
}

$assetUrls = $null
try {
    $assetUrls = & $uploadScript -SiteUrl $siteUrl -ModuleName $ModuleName
    $assetCount = if ($assetUrls -and $assetUrls.UploadedFiles) { $assetUrls.UploadedFiles.Count } else { 0 }
    Write-DeployLog -Message "Asset upload complete. $assetCount file(s) uploaded." -Level "Success"
}
catch {
    Write-DeployLog -Message "Asset upload failed: $_" -Level "Error"
    throw "Asset upload step failed. Deployment cannot continue without assets."
}

# ---------------------------------------------------------------------------
# Step 6 – Create SharePoint Pages
# ---------------------------------------------------------------------------
Write-DeployLog -Message "[Step 6/7] Creating SharePoint pages..." -Level "Info"

$pagesScript = Join-Path $scriptRoot "02_Create_SharePoint_Pages.ps1"
if (-not (Test-Path $pagesScript)) {
    throw "Page creation script not found: $pagesScript"
}

$pages = $null
try {
    $pages = & $pagesScript -SiteUrl $siteUrl -ModuleName $ModuleName
    $pageCount = if ($pages -and $pages.CreatedPages) { $pages.CreatedPages.Count } else { 0 }
    Write-DeployLog -Message "Page creation complete. $pageCount page(s) created." -Level "Success"
}
catch {
    Write-DeployLog -Message "Page creation failed: $_" -Level "Error"
    throw "Page creation step failed. Deployment cannot continue without pages."
}

# ---------------------------------------------------------------------------
# Step 7 – Apply Branding
# ---------------------------------------------------------------------------
if ($SkipBranding) {
    Write-DeployLog -Message "[Step 7/7] Skipping branding (SkipBranding flag set)." -Level "Warning"
}
else {
    Write-DeployLog -Message "[Step 7/7] Applying branding, theme, and navigation..." -Level "Info"

    $brandingScript = Join-Path $scriptRoot "04_Apply_Branding.ps1"
    if (-not (Test-Path $brandingScript)) {
        throw "Branding script not found: $brandingScript"
    }

    try {
        $brandingResult = & $brandingScript -SiteUrl $siteUrl -ModuleName $ModuleName
        Write-DeployLog -Message "Branding applied successfully. Theme: $($brandingResult.ThemeName)" -Level "Success"
    }
    catch {
        Write-DeployLog -Message "Branding failed: $_" -Level "Error"
        throw "Branding step failed."
    }
}

# ---------------------------------------------------------------------------
# Generate Deployment Report
# ---------------------------------------------------------------------------
Write-DeployLog -Message "Generating deployment report..." -Level "Info"

$deploymentTimer.Stop()
$totalDuration = $deploymentTimer.Elapsed

$reportData = @{
    DeploymentId   = $deploymentId
    ModuleName     = $ModuleName
    SiteUrl        = $siteUrl
    TenantUrl      = $TenantUrl
    SiteCreated    = $siteCreated
    AssetUrls      = $assetUrls
    Pages          = $pages
    BrandingApplied= (-not $SkipBranding)
    Duration       = $totalDuration
    Timestamp      = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Status         = "Success"
}

$reportPath = $null
try {
    $reportPath = New-DeploymentReport -ReportData $reportData
    Write-DeployLog -Message "Deployment report saved: $reportPath" -Level "Success"
}
catch {
    Write-DeployLog -Message "Failed to generate deployment report: $_" -Level "Warning"
    $reportPath = "Report generation failed"
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
$summaryBorder = "=" * 60
Write-Host ""
Write-Host $summaryBorder -ForegroundColor Cyan
Write-Host "  DEPLOYMENT COMPLETE" -ForegroundColor Green
Write-Host $summaryBorder -ForegroundColor Cyan
Write-Host ""
Write-Host "  Deployment ID : $deploymentId" -ForegroundColor White
Write-Host "  Module        : $ModuleName" -ForegroundColor White
Write-Host "  Site URL      : $siteUrl" -ForegroundColor White
Write-Host "  Site Created  : $siteCreated" -ForegroundColor White
Write-Host "  Assets        : $assetCount file(s)" -ForegroundColor White
Write-Host "  Pages         : $pageCount page(s)" -ForegroundColor White
Write-Host "  Branding      : $(if ($SkipBranding) { 'Skipped' } else { 'Applied' })" -ForegroundColor White
Write-Host "  Report        : $reportPath" -ForegroundColor White
Write-Host "  Duration      : $($totalDuration.ToString('hh\:mm\:ss\.fff'))" -ForegroundColor White
Write-Host ""
Write-Host $summaryBorder -ForegroundColor Cyan
Write-Host ""

# ---------------------------------------------------------------------------
# Return Result Object
# ---------------------------------------------------------------------------
[PSCustomObject]@{
    DeploymentId    = $deploymentId
    ModuleName      = $ModuleName
    SiteUrl         = $siteUrl
    TenantUrl       = $TenantUrl
    SiteCreated     = $siteCreated
    AssetsUploaded  = $assetCount
    PagesCreated    = $pageCount
    BrandingApplied = (-not $SkipBranding)
    ReportPath      = $reportPath
    Duration        = $totalDuration.ToString('hh\:mm\:ss\.fff')
    Timestamp       = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Status          = "Success"
}
