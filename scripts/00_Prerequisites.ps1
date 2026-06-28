#Requires -Version 7.0
<#
.SYNOPSIS
    SharePoint Training Deployer — Prerequisites Checker.

.DESCRIPTION
    Validates all prerequisites needed before deploying training modules to
    SharePoint Online. Checks PowerShell version, PnP.PowerShell module
    availability, deployment configuration, tenant connectivity, site
    collection admin permissions, and training content structure.

    Returns a PSCustomObject summarizing all checks with an AllPassed flag.

.PARAMETER TenantUrl
    Optional SharePoint Online tenant URL. When provided, overrides the
    TenantUrl value from deployment_config.json.

.PARAMETER ConfigPath
    Optional explicit path to deployment_config.json. When omitted, the
    script discovers it via the Get-DeployConfig helper.

.EXAMPLE
    ./00_Prerequisites.ps1
    # Runs all checks using defaults from deployment_config.json.

.EXAMPLE
    ./00_Prerequisites.ps1 -TenantUrl "https://contoso.sharepoint.com" -ConfigPath "./config/deployment_config.json"
    # Overrides tenant URL and config path.

.NOTES
    Author:  Sovereign Biz Box
    Version: 1.0.0
    Date:    2026-06-28
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$TenantUrl,

    [Parameter()]
    [string]$ConfigPath
)

# -------------------------------------------------------------------------
# Dot-source shared helpers
# -------------------------------------------------------------------------
$helpersPath = Join-Path $PSScriptRoot 'utils' 'Deploy-Helpers.ps1'
if (-not (Test-Path $helpersPath)) {
    Write-Error "Cannot find Deploy-Helpers.ps1 at expected path: $helpersPath"
    exit 1
}
. $helpersPath

# -------------------------------------------------------------------------
# State tracking
# -------------------------------------------------------------------------
$checks       = [System.Collections.Generic.List[PSCustomObject]]::new()
$scriptStart  = Get-Date

function Add-CheckResult {
    param(
        [string]$Name,
        [string]$Status,   # Passed | Failed | Warning
        [string]$Detail
    )
    $checks.Add([PSCustomObject]@{
        Name   = $Name
        Status = $Status
        Detail = $Detail
    })
}

# -------------------------------------------------------------------------
# Banner
# -------------------------------------------------------------------------
Write-Host ''
Write-Host '╔══════════════════════════════════════════════════════════════╗' -ForegroundColor Magenta
Write-Host '║   SharePoint Training Deployer — Prerequisites Check       ║' -ForegroundColor Magenta
Write-Host '╚══════════════════════════════════════════════════════════════╝' -ForegroundColor Magenta
Write-Host ''

Write-DeployLog -Message 'Starting prerequisites check...' -Level Info

# -------------------------------------------------------------------------
# 1. PowerShell Version >= 7.0
# -------------------------------------------------------------------------
Write-DeployLog -Message 'Checking PowerShell version...' -Level Info

$psVersion    = $PSVersionTable.PSVersion
$psVersionStr = "$($psVersion.Major).$($psVersion.Minor).$($psVersion.Build)"

if ($psVersion.Major -ge 7) {
    Write-DeployLog -Message "PowerShell version $psVersionStr detected — OK." -Level Success
    Add-CheckResult -Name 'PowerShell Version' -Status 'Passed' -Detail "v$psVersionStr (>= 7.0 required)"
}
else {
    Write-DeployLog -Message "PowerShell version $psVersionStr is below 7.0. Please install PowerShell 7+." -Level Error
    Add-CheckResult -Name 'PowerShell Version' -Status 'Failed' -Detail "v$psVersionStr — requires >= 7.0"
}

# -------------------------------------------------------------------------
# 2. PnP.PowerShell Module
# -------------------------------------------------------------------------
Write-DeployLog -Message 'Checking for PnP.PowerShell module...' -Level Info

$pnpModule = Get-Module -Name 'PnP.PowerShell' -ListAvailable -ErrorAction SilentlyContinue |
    Sort-Object Version -Descending |
    Select-Object -First 1

if ($pnpModule) {
    Write-DeployLog -Message "PnP.PowerShell v$($pnpModule.Version) is installed." -Level Success
    Add-CheckResult -Name 'PnP.PowerShell Module' -Status 'Passed' -Detail "v$($pnpModule.Version) installed"
}
else {
    Write-DeployLog -Message 'PnP.PowerShell module is NOT installed.' -Level Warning

    $installChoice = $null
    try {
        Write-Host ''
        Write-Host '  PnP.PowerShell is required but not installed.' -ForegroundColor Yellow
        Write-Host '  Would you like to install it now? [Y/N]: ' -ForegroundColor Yellow -NoNewline
        $installChoice = Read-Host
    }
    catch {
        # Non-interactive session
        $installChoice = 'N'
    }

    if ($installChoice -match '^[Yy]') {
        Write-DeployLog -Message 'Installing PnP.PowerShell from PSGallery...' -Level Info
        try {
            Install-Module -Name 'PnP.PowerShell' -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
            $installed = Get-Module -Name 'PnP.PowerShell' -ListAvailable |
                Sort-Object Version -Descending |
                Select-Object -First 1
            Write-DeployLog -Message "PnP.PowerShell v$($installed.Version) installed successfully." -Level Success
            Add-CheckResult -Name 'PnP.PowerShell Module' -Status 'Passed' -Detail "v$($installed.Version) installed (just now)"
        }
        catch {
            Write-DeployLog -Message "Failed to install PnP.PowerShell: $($_.Exception.Message)" -Level Error
            Add-CheckResult -Name 'PnP.PowerShell Module' -Status 'Failed' -Detail "Install failed: $($_.Exception.Message)"
        }
    }
    else {
        Write-DeployLog -Message 'PnP.PowerShell installation declined. Manual install required: Install-Module PnP.PowerShell -Scope CurrentUser' -Level Warning
        Add-CheckResult -Name 'PnP.PowerShell Module' -Status 'Failed' -Detail 'Not installed — user declined auto-install'
    }
}

# -------------------------------------------------------------------------
# 3. Deployment Configuration
# -------------------------------------------------------------------------
Write-DeployLog -Message 'Loading deployment configuration...' -Level Info

$deployConfig = $null
try {
    $configParams = @{}
    if ($ConfigPath) {
        $configParams['ConfigPath'] = $ConfigPath
    }
    $deployConfig = Get-DeployConfig @configParams
    Add-CheckResult -Name 'Deployment Config' -Status 'Passed' -Detail "Loaded — Tenant: $($deployConfig.TenantUrl)"
}
catch {
    Write-DeployLog -Message "Deployment config check failed: $($_.Exception.Message)" -Level Error
    Add-CheckResult -Name 'Deployment Config' -Status 'Failed' -Detail $_.Exception.Message
}

# -------------------------------------------------------------------------
# 4. Tenant Connectivity & Site Collection Admin
# -------------------------------------------------------------------------
$effectiveTenantUrl = if ($TenantUrl) { $TenantUrl } elseif ($deployConfig) { $deployConfig.TenantUrl } else { $null }

if ($effectiveTenantUrl) {
    $effectiveTenantUrl = Format-SharePointUrl -Url $effectiveTenantUrl
    Write-DeployLog -Message "Testing connectivity to: $effectiveTenantUrl" -Level Info

    try {
        Connect-PnPOnline -Url $effectiveTenantUrl -Interactive -ErrorAction Stop
        Write-DeployLog -Message "Connected to $effectiveTenantUrl" -Level Success

        # Check site collection admin
        $isAdmin = $false
        try {
            $currentUser = Get-PnPProperty -ClientObject (Get-PnPWeb) -Property CurrentUser -ErrorAction Stop
            $siteAdmins  = Get-PnPSiteCollectionAdmin -ErrorAction Stop

            if ($currentUser -and $siteAdmins) {
                $currentLogin = $currentUser.LoginName
                $isAdmin = $siteAdmins | Where-Object { $_.LoginName -eq $currentLogin }
            }
        }
        catch {
            Write-DeployLog -Message "Could not verify site collection admin status: $($_.Exception.Message)" -Level Warning
        }

        if ($isAdmin) {
            Write-DeployLog -Message 'Current user IS a site collection administrator.' -Level Success
            Add-CheckResult -Name 'Tenant Connectivity' -Status 'Passed' -Detail "Connected to $effectiveTenantUrl — Site Collection Admin confirmed"
        }
        else {
            Write-DeployLog -Message 'Current user may NOT be a site collection administrator. Some operations may fail.' -Level Warning
            Add-CheckResult -Name 'Tenant Connectivity' -Status 'Warning' -Detail "Connected to $effectiveTenantUrl — Site Collection Admin status unconfirmed"
        }

        # Disconnect to clean up
        try { Disconnect-PnPOnline -ErrorAction SilentlyContinue } catch { }
    }
    catch {
        Write-DeployLog -Message "Connection to tenant failed: $($_.Exception.Message)" -Level Error
        Add-CheckResult -Name 'Tenant Connectivity' -Status 'Failed' -Detail "Cannot connect to $effectiveTenantUrl — $($_.Exception.Message)"
    }
}
else {
    Write-DeployLog -Message 'No TenantUrl available — skipping connectivity check.' -Level Warning
    Add-CheckResult -Name 'Tenant Connectivity' -Status 'Failed' -Detail 'No TenantUrl provided or discovered from config'
}

# -------------------------------------------------------------------------
# 5. Content Directory Scan
# -------------------------------------------------------------------------
Write-DeployLog -Message 'Scanning content directory for training modules...' -Level Info

$projectRoot = Get-ProjectRoot
$contentDir  = Join-Path $projectRoot 'content'

if (Test-Path $contentDir) {
    $moduleFolders = Get-ChildItem -Path $contentDir -Directory -ErrorAction SilentlyContinue

    if ($moduleFolders.Count -eq 0) {
        Write-DeployLog -Message 'Content directory exists but contains no module folders.' -Level Warning
        Add-CheckResult -Name 'Content Modules' -Status 'Warning' -Detail 'content/ directory is empty — no modules found'
    }
    else {
        $validModules   = 0
        $invalidModules = [System.Collections.Generic.List[string]]::new()

        foreach ($folder in $moduleFolders) {
            $moduleName       = $folder.Name
            $moduleConfigFile = Join-Path $folder.FullName 'module_config.json'
            $interactiveDir   = Join-Path $folder.FullName 'interactive_app'

            $hasConfig      = Test-Path $moduleConfigFile
            $hasInteractive = Test-Path $interactiveDir

            if ($hasConfig -and $hasInteractive) {
                Write-DeployLog -Message "  Module '$moduleName' — OK (config + interactive_app found)" -Level Success
                $validModules++
            }
            else {
                $missing = @()
                if (-not $hasConfig)      { $missing += 'module_config.json' }
                if (-not $hasInteractive) { $missing += 'interactive_app/' }
                $missingStr = $missing -join ', '

                Write-DeployLog -Message "  Module '$moduleName' — INCOMPLETE (missing: $missingStr)" -Level Warning
                $invalidModules.Add("$moduleName (missing: $missingStr)")
            }
        }

        $totalModules = $moduleFolders.Count
        if ($invalidModules.Count -eq 0) {
            Add-CheckResult -Name 'Content Modules' -Status 'Passed' -Detail "$validModules of $totalModules modules valid"
        }
        else {
            $detail = "$validModules of $totalModules valid; incomplete: $($invalidModules -join '; ')"
            Add-CheckResult -Name 'Content Modules' -Status 'Warning' -Detail $detail
        }
    }
}
else {
    Write-DeployLog -Message "Content directory not found at: $contentDir" -Level Error
    Add-CheckResult -Name 'Content Modules' -Status 'Failed' -Detail "Directory not found: $contentDir"
}

# -------------------------------------------------------------------------
# Summary Table
# -------------------------------------------------------------------------
Write-Host ''
Write-Host '┌──────────────────────────────────────────────────────────────┐' -ForegroundColor DarkGray
Write-Host '│                  PREREQUISITES SUMMARY                      │' -ForegroundColor DarkGray
Write-Host '├───────────────────────┬──────────┬──────────────────────────┤' -ForegroundColor DarkGray
Write-Host '│ Check                 │ Status   │ Detail                   │' -ForegroundColor DarkGray
Write-Host '├───────────────────────┼──────────┼──────────────────────────┤' -ForegroundColor DarkGray

foreach ($check in $checks) {
    $statusColor = switch ($check.Status) {
        'Passed'  { 'Green'  }
        'Warning' { 'Yellow' }
        'Failed'  { 'Red'    }
        default   { 'Gray'   }
    }

    $symbol = switch ($check.Status) {
        'Passed'  { '[OK]'   }
        'Warning' { '[!!]'   }
        'Failed'  { '[XX]'   }
        default   { '[??]'   }
    }

    $nameCol   = $check.Name.PadRight(21)
    $statusCol = $symbol.PadRight(8)
    # Truncate detail to fit column
    $detailMax = 24
    $detailCol = if ($check.Detail.Length -gt $detailMax) {
        $check.Detail.Substring(0, $detailMax - 1) + '…'
    } else {
        $check.Detail.PadRight($detailMax)
    }

    Write-Host -NoNewline '│ '
    Write-Host -NoNewline $nameCol -ForegroundColor White
    Write-Host -NoNewline '│ '
    Write-Host -NoNewline $statusCol -ForegroundColor $statusColor
    Write-Host -NoNewline '│ '
    Write-Host -NoNewline $detailCol -ForegroundColor DarkGray
    Write-Host '│'
}

Write-Host '└───────────────────────┴──────────┴──────────────────────────┘' -ForegroundColor DarkGray
Write-Host ''

# -------------------------------------------------------------------------
# Final Result
# -------------------------------------------------------------------------
$allPassed = ($checks | Where-Object { $_.Status -eq 'Failed' }).Count -eq 0
$scriptEnd = Get-Date

if ($allPassed) {
    Write-DeployLog -Message 'All prerequisites checks passed (or have warnings). Ready to deploy.' -Level Success
}
else {
    Write-DeployLog -Message 'One or more prerequisite checks FAILED. Please resolve before deploying.' -Level Error
}

$result = [PSCustomObject]@{
    AllPassed = $allPassed
    Checks    = $checks.ToArray()
    Timestamp = $scriptEnd
}

Write-DeployLog -Message "Prerequisites check completed in $(($scriptEnd - $scriptStart).TotalSeconds.ToString('F1'))s." -Level Info

return $result
