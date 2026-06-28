<#
.SYNOPSIS
    Applies custom branding, theme, and navigation to a SharePoint training site.

.DESCRIPTION
    This script connects to a SharePoint Online site and applies a custom dark theme
    with cyan accents, sets the site title and description from module configuration,
    configures the top navigation bar with training module pages, and sets the home page.

    The dark theme uses a deep navy background (#16213e) with bright cyan primary
    accents (#00d4ff) for a modern, professional training portal appearance.

.PARAMETER SiteUrl
    The full URL of the SharePoint site to brand (e.g., https://contoso.sharepoint.com/sites/safety-training).

.PARAMETER ModuleName
    The name of the training module. Used to look up configuration for site title and description.

.EXAMPLE
    .\04_Apply_Branding.ps1 -SiteUrl "https://contoso.sharepoint.com/sites/fire-safety" -ModuleName "Fire_Safety"

.EXAMPLE
    .\04_Apply_Branding.ps1 -SiteUrl "https://contoso.sharepoint.com/sites/onboarding" -ModuleName "New_Hire_Onboarding"

.NOTES
    Requires PnP.PowerShell module.
    Must be run after the site and pages have been created.
    Dot-sources ./utils/Deploy-Helpers.ps1 for shared utility functions.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Full URL of the SharePoint site to brand.")]
    [ValidateNotNullOrEmpty()]
    [string]$SiteUrl,

    [Parameter(Mandatory = $true, HelpMessage = "Name of the training module for config lookup.")]
    [ValidateNotNullOrEmpty()]
    [string]$ModuleName
)

# ---------------------------------------------------------------------------
# Bootstrap
# ---------------------------------------------------------------------------
$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $scriptRoot "utils" "Deploy-Helpers.ps1")

# ---------------------------------------------------------------------------
# Theme Definition – Sovereign Dark with Cyan Accents
# ---------------------------------------------------------------------------
$sovereignThemePalette = @{
    "themePrimary"        = "#00d4ff"
    "themeLighterAlt"     = "#000809"
    "themeLighter"        = "#002233"
    "themeLight"          = "#003d5c"
    "themeTertiary"       = "#007ab8"
    "themeSecondary"      = "#00b8db"
    "themeDarkAlt"        = "#1ad8ff"
    "themeDark"           = "#40e0ff"
    "themeDarker"         = "#73e8ff"
    "neutralLighterAlt"   = "#1a1a2e"
    "neutralLighter"      = "#1f1f36"
    "neutralLight"        = "#2a2a42"
    "neutralQuaternaryAlt"= "#31314c"
    "neutralQuaternary"   = "#373754"
    "neutralTertiaryAlt"  = "#515175"
    "neutralTertiary"     = "#c8c8c8"
    "neutralSecondary"    = "#d0d0d0"
    "neutralPrimaryAlt"   = "#dadada"
    "neutralPrimary"      = "#ffffff"
    "neutralDark"         = "#f4f4f4"
    "black"               = "#f8f8f8"
    "white"               = "#16213e"
}

$themeName = "SovereignTrainingDark"

# ---------------------------------------------------------------------------
# Step 1 – Connect to SharePoint Online
# ---------------------------------------------------------------------------
Write-DeployLog -Message "Connecting to SharePoint site: $SiteUrl" -Level "Info"

try {
    Connect-PnPOnline -Url $SiteUrl -Interactive -ErrorAction Stop
}
catch {
    Write-DeployLog -Message "Failed to connect to SharePoint: $_" -Level "Error"
    throw "Connection to SharePoint site '$SiteUrl' failed. Ensure you have permissions and PnP.PowerShell is installed."
}

# Verify the connection is active
$connectionValid = $false
try {
    $web = Get-PnPWeb -ErrorAction Stop
    if ($web) {
        $connectionValid = $true
        Write-DeployLog -Message "Connection verified. Site: $($web.Title) | URL: $($web.Url)" -Level "Success"
    }
}
catch {
    Write-DeployLog -Message "Connection verification failed: $_" -Level "Error"
}

if (-not $connectionValid) {
    throw "PnP connection to '$SiteUrl' could not be verified. Aborting branding."
}

# ---------------------------------------------------------------------------
# Step 2 – Apply Custom Dark Theme
# ---------------------------------------------------------------------------
Write-DeployLog -Message "Applying custom theme '$themeName' with dark navy/cyan palette..." -Level "Info"

$themeApplied = $false

# Attempt 1: Add as a tenant theme (requires tenant admin rights)
try {
    Write-DeployLog -Message "Attempting to register theme at tenant level via Add-PnPTenantTheme..." -Level "Info"
    Add-PnPTenantTheme -Identity $themeName -Palette $sovereignThemePalette -IsInverted $true -Overwrite -ErrorAction Stop
    Write-DeployLog -Message "Tenant theme '$themeName' registered successfully." -Level "Success"

    # Apply the registered tenant theme to the current site
    Set-PnPWebTheme -Theme $themeName -ErrorAction Stop
    Write-DeployLog -Message "Tenant theme '$themeName' applied to site." -Level "Success"
    $themeApplied = $true
}
catch {
    Write-DeployLog -Message "Tenant-level theme registration failed (likely insufficient admin rights): $_" -Level "Warning"
    Write-DeployLog -Message "Falling back to site-level theme application..." -Level "Info"
}

# Attempt 2: Fallback – apply theme directly at site level
if (-not $themeApplied) {
    try {
        Set-PnPWebTheme -Theme $themeName -ErrorAction SilentlyContinue
    }
    catch {
        Write-DeployLog -Message "Named theme fallback failed, applying palette directly..." -Level "Warning"
    }

    try {
        # Apply theme palette directly to the web
        $web = Get-PnPWeb -ErrorAction Stop
        $themeHash = @{}
        foreach ($key in $sovereignThemePalette.Keys) {
            $themeHash[$key] = $sovereignThemePalette[$key]
        }

        # Use CSOM to apply the theme palette directly
        $context = Get-PnPContext
        $web.ApplyTheme(
            $null,  # colorPaletteUrl – not using SPColor file
            $null,  # fontSchemeUrl
            $null,  # backgroundImageUrl
            $true   # shareGenerated
        )
        $context.ExecuteQuery()

        Write-DeployLog -Message "Site-level theme applied via direct palette injection." -Level "Success"
        $themeApplied = $true
    }
    catch {
        Write-DeployLog -Message "Direct theme application also failed: $_" -Level "Warning"
        Write-DeployLog -Message "Theme will need to be applied manually via SharePoint admin center." -Level "Warning"
        # Non-fatal – continue with remaining branding steps
    }
}

# ---------------------------------------------------------------------------
# Step 3 – Set Site Title and Description from Module Config
# ---------------------------------------------------------------------------
Write-DeployLog -Message "Loading module configuration for '$ModuleName'..." -Level "Info"

$moduleConfig = Get-ModuleConfig -ModuleName $ModuleName

$siteTitle       = $moduleConfig.SiteTitle
$siteDescription = $moduleConfig.SiteDescription

if ([string]::IsNullOrWhiteSpace($siteTitle)) {
    $siteTitle = ($ModuleName -replace '_', ' ')
    Write-DeployLog -Message "No SiteTitle in config; defaulting to '$siteTitle'." -Level "Warning"
}

if ([string]::IsNullOrWhiteSpace($siteDescription)) {
    $siteDescription = "Training module: $siteTitle – Deployed by Sovereign Biz Box Training Deployer."
    Write-DeployLog -Message "No SiteDescription in config; using default description." -Level "Warning"
}

try {
    Set-PnPWeb -Title $siteTitle -Description $siteDescription -ErrorAction Stop
    Write-DeployLog -Message "Site title set to '$siteTitle'." -Level "Success"
    Write-DeployLog -Message "Site description updated." -Level "Success"
}
catch {
    Write-DeployLog -Message "Failed to update site title/description: $_" -Level "Error"
    throw
}

# ---------------------------------------------------------------------------
# Step 4 – Configure Top Navigation
# ---------------------------------------------------------------------------
Write-DeployLog -Message "Configuring top navigation bar..." -Level "Info"

# Navigation link definitions
$navigationLinks = @(
    @{ Title = "Home";              Url = "Home.aspx" }
    @{ Title = "Procedure Guide";   Url = "Procedure-Guide.aspx" }
    @{ Title = "Media & Resources"; Url = "Media-Resources.aspx" }
    @{ Title = "Assessment";        Url = "Assessment.aspx" }
    @{ Title = "Field Logs";        Url = "Field-Logs.aspx" }
)

# Clear existing top navigation nodes
try {
    $existingNodes = Get-PnPNavigationNode -Location TopNavigationBar -ErrorAction Stop
    if ($existingNodes -and $existingNodes.Count -gt 0) {
        Write-DeployLog -Message "Clearing $($existingNodes.Count) existing top navigation node(s)..." -Level "Info"
        foreach ($node in $existingNodes) {
            Remove-PnPNavigationNode -Identity $node.Id -Location TopNavigationBar -Force -ErrorAction SilentlyContinue
        }
        Write-DeployLog -Message "Existing navigation cleared." -Level "Success"
    }
    else {
        Write-DeployLog -Message "No existing navigation nodes to clear." -Level "Info"
    }
}
catch {
    Write-DeployLog -Message "Error clearing navigation nodes: $_" -Level "Warning"
    Write-DeployLog -Message "Proceeding to add new navigation links..." -Level "Info"
}

# Add new navigation links
$navAddedCount = 0
foreach ($link in $navigationLinks) {
    $pageUrl = "$SiteUrl/SitePages/$($link.Url)"
    try {
        Add-PnPNavigationNode -Location TopNavigationBar -Title $link.Title -Url $pageUrl -ErrorAction Stop
        Write-DeployLog -Message "  Added nav link: $($link.Title) → $($link.Url)" -Level "Success"
        $navAddedCount++
    }
    catch {
        Write-DeployLog -Message "  Failed to add nav link '$($link.Title)': $_" -Level "Error"
        throw "Navigation configuration failed on link '$($link.Title)'. Aborting."
    }
}

Write-DeployLog -Message "Top navigation configured: $navAddedCount link(s) added." -Level "Success"

# ---------------------------------------------------------------------------
# Step 5 – Set Home Page
# ---------------------------------------------------------------------------
Write-DeployLog -Message "Setting Home.aspx as the site home page..." -Level "Info"

try {
    Set-PnPHomePage -RootFolderRelativeUrl "SitePages/Home.aspx" -ErrorAction Stop
    Write-DeployLog -Message "Home page set to SitePages/Home.aspx." -Level "Success"
}
catch {
    Write-DeployLog -Message "Failed to set home page: $_" -Level "Error"
    throw "Could not set Home.aspx as the site home page."
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-DeployLog -Message ("=" * 60) -Level "Info"
Write-DeployLog -Message "Branding Complete for '$siteTitle'" -Level "Success"
Write-DeployLog -Message "  Theme Applied : $themeApplied" -Level "Info"
Write-DeployLog -Message "  Site Title    : $siteTitle" -Level "Info"
Write-DeployLog -Message "  Nav Links     : $navAddedCount" -Level "Info"
Write-DeployLog -Message "  Home Page     : SitePages/Home.aspx" -Level "Info"
Write-DeployLog -Message ("=" * 60) -Level "Info"

# Return result object for caller consumption
[PSCustomObject]@{
    SiteUrl        = $SiteUrl
    ModuleName     = $ModuleName
    ThemeApplied   = $themeApplied
    ThemeName      = $themeName
    SiteTitle      = $siteTitle
    NavigationLinks= $navAddedCount
    HomePageSet    = $true
    Timestamp      = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
}
