<#
.SYNOPSIS
    Batch-deploys multiple SharePoint training sites from a CSV manifest.

.DESCRIPTION
    Reads a CSV file containing training module definitions, validates each module's
    content directory, and deploys them sequentially by calling 01_Deploy_Training_Site.ps1.
    Supports dry-run mode, error continuation, and generates a comprehensive styled HTML
    batch report with dark theme.

    The CSV must contain columns: ModuleName, SiteUrlSuffix, Priority, Enabled.
    Only rows with Enabled=True are processed, sorted by Priority (ascending).

.PARAMETER CsvPath
    Path to the CSV manifest file. Defaults to ../config/training_modules.csv relative
    to the script directory.

.PARAMETER TenantUrl
    SharePoint Online tenant URL. Passed through to each module deployment.
    If not provided, each deployment will use its own config fallback.

.PARAMETER DryRun
    Display the deployment plan as a table without executing any deployments.

.PARAMETER ContinueOnError
    Continue deploying remaining modules if one fails. By default, the batch
    stops on the first failure.

.PARAMETER ReportOutputPath
    Custom path for the HTML batch report. Defaults to ../reports/batch_report_<timestamp>.html.

.EXAMPLE
    .\05_Batch_Deploy.ps1

.EXAMPLE
    .\05_Batch_Deploy.ps1 -DryRun

.EXAMPLE
    .\05_Batch_Deploy.ps1 -CsvPath "C:\configs\modules.csv" -ContinueOnError -TenantUrl "https://contoso.sharepoint.com"

.EXAMPLE
    .\05_Batch_Deploy.ps1 -ReportOutputPath "C:\reports\q4_deployment.html"

.NOTES
    Requires PnP.PowerShell module.
    Dot-sources ./utils/Deploy-Helpers.ps1 for shared utility functions.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, HelpMessage = "Path to CSV manifest with module definitions.")]
    [string]$CsvPath,

    [Parameter(Mandatory = $false, HelpMessage = "SharePoint tenant URL passed to each deployment.")]
    [string]$TenantUrl,

    [Parameter(HelpMessage = "Preview deployment plan without executing.")]
    [switch]$DryRun,

    [Parameter(HelpMessage = "Continue deploying remaining modules on failure.")]
    [switch]$ContinueOnError,

    [Parameter(Mandatory = $false, HelpMessage = "Custom output path for the HTML batch report.")]
    [string]$ReportOutputPath
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
 ║         SOVEREIGN BATCH TRAINING DEPLOYER v2.0              ║
 ║         Multi-Module • Automated Pipeline                   ║
 ╚══════════════════════════════════════════════════════════════╝

"@
Write-Host $banner -ForegroundColor Cyan

$batchTimer = [System.Diagnostics.Stopwatch]::StartNew()
$batchId    = [guid]::NewGuid().ToString("N").Substring(0, 8)

Write-DeployLog -Message "Batch Deployment ID: $batchId" -Level "Info"
Write-DeployLog -Message "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Level "Info"
Write-DeployLog -Message ("-" * 60) -Level "Info"

# ---------------------------------------------------------------------------
# Step 1 – Load and Validate CSV
# ---------------------------------------------------------------------------
Write-DeployLog -Message "[Step 1/4] Loading module manifest CSV..." -Level "Info"

# Default CSV path
if ([string]::IsNullOrWhiteSpace($CsvPath)) {
    $CsvPath = Join-Path (Split-Path $scriptRoot -Parent) "config" "training_modules.csv"
    Write-DeployLog -Message "Using default CSV path: $CsvPath" -Level "Info"
}

# Validate CSV exists
if (-not (Test-Path $CsvPath)) {
    $batchTimer.Stop()
    Write-DeployLog -Message "CSV manifest not found: $CsvPath" -Level "Error"
    throw "Module manifest CSV not found at '$CsvPath'. Create the file or specify -CsvPath."
}

# Import CSV
$rawModules = $null
try {
    $rawModules = Import-Csv -Path $CsvPath -ErrorAction Stop
}
catch {
    $batchTimer.Stop()
    Write-DeployLog -Message "Failed to parse CSV: $_" -Level "Error"
    throw "Could not parse CSV file '$CsvPath': $_"
}

# Validate CSV is not empty
if (-not $rawModules -or $rawModules.Count -eq 0) {
    $batchTimer.Stop()
    Write-DeployLog -Message "CSV manifest is empty. No modules defined." -Level "Error"
    throw "CSV manifest '$CsvPath' contains no module entries."
}

Write-DeployLog -Message "Loaded $($rawModules.Count) total module(s) from CSV." -Level "Info"

# Validate required columns
$requiredColumns = @("ModuleName", "SiteUrlSuffix", "Priority", "Enabled")
$csvHeaders = $rawModules[0].PSObject.Properties.Name
foreach ($col in $requiredColumns) {
    if ($col -notin $csvHeaders) {
        $batchTimer.Stop()
        throw "CSV is missing required column '$col'. Expected columns: $($requiredColumns -join ', ')"
    }
}

# Filter enabled modules and sort by priority
$enabledModules = $rawModules | Where-Object {
    $_.Enabled -eq "True" -or $_.Enabled -eq "true" -or $_.Enabled -eq "TRUE" -or $_.Enabled -eq "1" -or $_.Enabled -eq "Yes"
} | Sort-Object { [int]$_.Priority }

if (-not $enabledModules -or @($enabledModules).Count -eq 0) {
    $batchTimer.Stop()
    Write-DeployLog -Message "No enabled modules found in CSV. All modules have Enabled != True." -Level "Warning"

    # Return empty result
    return [PSCustomObject]@{
        BatchId       = $batchId
        TotalModules  = 0
        Succeeded     = 0
        Failed        = 0
        Skipped       = $rawModules.Count
        ReportPath    = $null
        Duration      = $batchTimer.Elapsed.ToString('hh\:mm\:ss\.fff')
        Status        = "NoEnabledModules"
    }
}

$moduleCount = @($enabledModules).Count
Write-DeployLog -Message "$moduleCount enabled module(s) to deploy (sorted by priority)." -Level "Success"

# ---------------------------------------------------------------------------
# Step 2 – Validate Content Directories
# ---------------------------------------------------------------------------
Write-DeployLog -Message "[Step 2/4] Validating content directories..." -Level "Info"

$contentBase = Join-Path (Split-Path $scriptRoot -Parent) "content"
$validationErrors = @()

foreach ($mod in $enabledModules) {
    $modContentDir = Join-Path $contentBase $mod.ModuleName
    if (-not (Test-Path $modContentDir)) {
        $validationErrors += "Content directory missing for '$($mod.ModuleName)': $modContentDir"
        Write-DeployLog -Message "  MISSING: $($mod.ModuleName) → $modContentDir" -Level "Error"
    }
    else {
        Write-DeployLog -Message "  OK: $($mod.ModuleName) → $modContentDir" -Level "Success"
    }
}

if ($validationErrors.Count -gt 0 -and -not $ContinueOnError) {
    $batchTimer.Stop()
    throw "Content validation failed for $($validationErrors.Count) module(s). Use -ContinueOnError to proceed anyway.`n$($validationErrors -join "`n")"
}

# ---------------------------------------------------------------------------
# Step 3 – Dry Run or Deploy
# ---------------------------------------------------------------------------
if ($DryRun) {
    Write-DeployLog -Message "[Step 3/4] DRY RUN MODE – Displaying deployment plan only." -Level "Warning"
    Write-Host ""
    Write-Host "  DEPLOYMENT PLAN (DRY RUN)" -ForegroundColor Yellow
    Write-Host "  $('-' * 50)" -ForegroundColor Yellow
    Write-Host ""

    $planTable = $enabledModules | ForEach-Object {
        $suffix = if ([string]::IsNullOrWhiteSpace($_.SiteUrlSuffix)) { ($_.ModuleName -replace '_', '-').ToLower() } else { $_.SiteUrlSuffix }
        $contentExists = Test-Path (Join-Path $contentBase $_.ModuleName)

        [PSCustomObject]@{
            Priority     = $_.Priority
            ModuleName   = $_.ModuleName
            SiteUrlSuffix= $suffix
            ContentReady = if ($contentExists) { "Yes" } else { "NO" }
        }
    }

    $planTable | Format-Table -AutoSize

    Write-Host ""
    Write-DeployLog -Message "Dry run complete. $moduleCount module(s) would be deployed. No changes were made." -Level "Info"

    $batchTimer.Stop()
    return [PSCustomObject]@{
        BatchId       = $batchId
        TotalModules  = $moduleCount
        Succeeded     = 0
        Failed        = 0
        Skipped       = $moduleCount
        ReportPath    = $null
        Duration      = $batchTimer.Elapsed.ToString('hh\:mm\:ss\.fff')
        Status        = "DryRun"
    }
}

# ---------------------------------------------------------------------------
# Step 3 (Active) – Deploy Each Module
# ---------------------------------------------------------------------------
Write-DeployLog -Message "[Step 3/4] Beginning batch deployment of $moduleCount module(s)..." -Level "Info"

$deployScript = Join-Path $scriptRoot "01_Deploy_Training_Site.ps1"
if (-not (Test-Path $deployScript)) {
    $batchTimer.Stop()
    throw "Master deploy script not found: $deployScript"
}

$results       = @()
$succeededCount = 0
$failedCount    = 0
$skippedCount   = 0
$moduleIndex    = 0

foreach ($mod in $enabledModules) {
    $moduleIndex++
    $moduleTimer = [System.Diagnostics.Stopwatch]::StartNew()

    $moduleName    = $mod.ModuleName
    $siteUrlSuffix = $mod.SiteUrlSuffix

    Write-Host ""
    Write-DeployLog -Message ("=" * 60) -Level "Info"
    Write-DeployLog -Message "Module $moduleIndex/$moduleCount : $moduleName" -Level "Info"
    Write-DeployLog -Message ("=" * 60) -Level "Info"

    # Check if content directory exists (skip if missing and ContinueOnError)
    $modContentDir = Join-Path $contentBase $moduleName
    if (-not (Test-Path $modContentDir)) {
        $moduleTimer.Stop()
        Write-DeployLog -Message "Content directory missing. Skipping module." -Level "Warning"
        $skippedCount++
        $results += [PSCustomObject]@{
            ModuleName    = $moduleName
            SiteUrlSuffix = $siteUrlSuffix
            Status        = "Skipped"
            Reason        = "Content directory missing"
            Duration      = $moduleTimer.Elapsed.ToString('hh\:mm\:ss\.fff')
            SiteUrl       = $null
            Error         = $null
        }
        continue
    }

    # Build deployment parameters
    $deployParams = @{
        ModuleName = $moduleName
    }
    if (-not [string]::IsNullOrWhiteSpace($siteUrlSuffix)) {
        $deployParams['SiteUrlSuffix'] = $siteUrlSuffix
    }
    if (-not [string]::IsNullOrWhiteSpace($TenantUrl)) {
        $deployParams['TenantUrl'] = $TenantUrl
    }

    # Execute deployment
    try {
        $deployResult = & $deployScript @deployParams
        $moduleTimer.Stop()

        Write-DeployLog -Message "Module '$moduleName' deployed successfully in $($moduleTimer.Elapsed.ToString('hh\:mm\:ss\.fff'))." -Level "Success"
        $succeededCount++

        $results += [PSCustomObject]@{
            ModuleName    = $moduleName
            SiteUrlSuffix = if ($deployResult.SiteUrl) { $deployResult.SiteUrl } else { $siteUrlSuffix }
            Status        = "Success"
            Reason        = $null
            Duration      = $moduleTimer.Elapsed.ToString('hh\:mm\:ss\.fff')
            SiteUrl       = $deployResult.SiteUrl
            Error         = $null
        }
    }
    catch {
        $moduleTimer.Stop()
        $errorMessage = $_.Exception.Message

        Write-DeployLog -Message "Module '$moduleName' FAILED: $errorMessage" -Level "Error"
        $failedCount++

        $results += [PSCustomObject]@{
            ModuleName    = $moduleName
            SiteUrlSuffix = $siteUrlSuffix
            Status        = "Failed"
            Reason        = $errorMessage
            Duration      = $moduleTimer.Elapsed.ToString('hh\:mm\:ss\.fff')
            SiteUrl       = $null
            Error         = $errorMessage
        }

        if (-not $ContinueOnError) {
            Write-DeployLog -Message "Batch deployment halted due to failure. Use -ContinueOnError to continue past errors." -Level "Error"
            break
        }
        else {
            Write-DeployLog -Message "ContinueOnError is set. Proceeding to next module..." -Level "Warning"
        }
    }
}

# ---------------------------------------------------------------------------
# Step 4 – Generate Batch Report
# ---------------------------------------------------------------------------
Write-DeployLog -Message "[Step 4/4] Generating batch deployment report..." -Level "Info"

$batchTimer.Stop()
$totalDuration = $batchTimer.Elapsed

# Resolve report output path
if ([string]::IsNullOrWhiteSpace($ReportOutputPath)) {
    $reportsDir = Join-Path (Split-Path $scriptRoot -Parent) "reports"
    if (-not (Test-Path $reportsDir)) {
        New-Item -ItemType Directory -Path $reportsDir -Force | Out-Null
    }
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $ReportOutputPath = Join-Path $reportsDir "batch_report_$timestamp.html"
}
else {
    $reportDir = Split-Path $ReportOutputPath -Parent
    if (-not (Test-Path $reportDir)) {
        New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
    }
}

# Build HTML Report
$overallStatus = if ($failedCount -eq 0 -and $skippedCount -eq 0) { "ALL SUCCEEDED" }
                 elseif ($failedCount -eq 0) { "COMPLETED WITH SKIPS" }
                 elseif ($succeededCount -gt 0) { "PARTIAL FAILURE" }
                 else { "ALL FAILED" }

$statusColor = switch ($overallStatus) {
    "ALL SUCCEEDED"        { "#00d4ff" }
    "COMPLETED WITH SKIPS" { "#ffa500" }
    "PARTIAL FAILURE"      { "#ff6b6b" }
    "ALL FAILED"           { "#ff3333" }
}

$moduleRows = ""
foreach ($r in $results) {
    $rowStatusColor = switch ($r.Status) {
        "Success" { "#00d4ff" }
        "Skipped" { "#ffa500" }
        "Failed"  { "#ff6b6b" }
    }

    $statusBadge = "<span style='color: $rowStatusColor; font-weight: bold;'>$($r.Status.ToUpper())</span>"
    $siteLink    = if ($r.SiteUrl) { "<a href='$($r.SiteUrl)' target='_blank' style='color: #40e0ff;'>$($r.SiteUrl)</a>" } else { "—" }
    $errorCell   = if ($r.Error) { "<span style='color: #ff6b6b; font-size: 0.85em;'>$([System.Web.HttpUtility]::HtmlEncode($r.Error))</span>" } else { "—" }

    $moduleRows += @"
            <tr>
                <td>$($r.ModuleName)</td>
                <td>$statusBadge</td>
                <td>$siteLink</td>
                <td>$($r.Duration)</td>
                <td>$errorCell</td>
            </tr>

"@
}

$htmlReport = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Batch Deployment Report - $batchId</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }

        body {
            font-family: 'Segoe UI', -apple-system, BlinkMacSystemFont, sans-serif;
            background: linear-gradient(135deg, #0f0f23 0%, #16213e 50%, #1a1a2e 100%);
            color: #e0e0e0;
            min-height: 100vh;
            padding: 40px 20px;
        }

        .container {
            max-width: 1100px;
            margin: 0 auto;
        }

        .header {
            text-align: center;
            margin-bottom: 40px;
            padding: 30px;
            background: rgba(0, 212, 255, 0.05);
            border: 1px solid rgba(0, 212, 255, 0.15);
            border-radius: 12px;
            backdrop-filter: blur(10px);
        }

        .header h1 {
            font-size: 28px;
            font-weight: 700;
            color: #00d4ff;
            margin-bottom: 8px;
            letter-spacing: 1px;
        }

        .header .subtitle {
            font-size: 14px;
            color: #8888aa;
        }

        .summary-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
            gap: 16px;
            margin-bottom: 32px;
        }

        .summary-card {
            background: rgba(255, 255, 255, 0.03);
            border: 1px solid rgba(255, 255, 255, 0.08);
            border-radius: 10px;
            padding: 20px;
            text-align: center;
        }

        .summary-card .value {
            font-size: 32px;
            font-weight: 700;
            margin-bottom: 4px;
        }

        .summary-card .label {
            font-size: 12px;
            text-transform: uppercase;
            letter-spacing: 1px;
            color: #8888aa;
        }

        .status-banner {
            text-align: center;
            padding: 14px;
            border-radius: 8px;
            font-size: 18px;
            font-weight: 700;
            letter-spacing: 2px;
            margin-bottom: 32px;
            border: 1px solid;
        }

        table {
            width: 100%;
            border-collapse: collapse;
            background: rgba(255, 255, 255, 0.02);
            border-radius: 10px;
            overflow: hidden;
        }

        thead th {
            background: rgba(0, 212, 255, 0.1);
            color: #00d4ff;
            padding: 14px 16px;
            text-align: left;
            font-size: 12px;
            text-transform: uppercase;
            letter-spacing: 1px;
            border-bottom: 1px solid rgba(0, 212, 255, 0.2);
        }

        tbody td {
            padding: 12px 16px;
            border-bottom: 1px solid rgba(255, 255, 255, 0.05);
            font-size: 14px;
        }

        tbody tr:hover {
            background: rgba(0, 212, 255, 0.03);
        }

        tbody tr:last-child td {
            border-bottom: none;
        }

        .footer {
            text-align: center;
            margin-top: 32px;
            padding: 16px;
            font-size: 12px;
            color: #555577;
        }

        a { text-decoration: none; }
        a:hover { text-decoration: underline; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>BATCH DEPLOYMENT REPORT</h1>
            <div class="subtitle">Batch ID: $batchId &bull; Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</div>
        </div>

        <div class="status-banner" style="color: $statusColor; border-color: ${statusColor}44; background: ${statusColor}11;">
            $overallStatus
        </div>

        <div class="summary-grid">
            <div class="summary-card">
                <div class="value" style="color: #ffffff;">$moduleCount</div>
                <div class="label">Total Modules</div>
            </div>
            <div class="summary-card">
                <div class="value" style="color: #00d4ff;">$succeededCount</div>
                <div class="label">Succeeded</div>
            </div>
            <div class="summary-card">
                <div class="value" style="color: #ff6b6b;">$failedCount</div>
                <div class="label">Failed</div>
            </div>
            <div class="summary-card">
                <div class="value" style="color: #ffa500;">$skippedCount</div>
                <div class="label">Skipped</div>
            </div>
            <div class="summary-card">
                <div class="value" style="color: #73e8ff;">$($totalDuration.ToString('hh\:mm\:ss'))</div>
                <div class="label">Total Duration</div>
            </div>
        </div>

        <table>
            <thead>
                <tr>
                    <th>Module Name</th>
                    <th>Status</th>
                    <th>Site URL</th>
                    <th>Duration</th>
                    <th>Error Details</th>
                </tr>
            </thead>
            <tbody>
$moduleRows
            </tbody>
        </table>

        <div class="footer">
            Sovereign Biz Box &bull; SharePoint Training Deployer &bull; Batch Report v2.0
        </div>
    </div>
</body>
</html>
"@

try {
    # Ensure System.Web is loaded for HTML encoding
    Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue

    $htmlReport | Out-File -FilePath $ReportOutputPath -Encoding UTF8 -Force
    Write-DeployLog -Message "Batch report saved: $ReportOutputPath" -Level "Success"
}
catch {
    Write-DeployLog -Message "Failed to write batch report: $_" -Level "Warning"
    $ReportOutputPath = "Report generation failed: $_"
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
$summaryBorder = "=" * 60
Write-Host ""
Write-Host $summaryBorder -ForegroundColor Cyan
Write-Host "  BATCH DEPLOYMENT COMPLETE" -ForegroundColor Green
Write-Host $summaryBorder -ForegroundColor Cyan
Write-Host ""
Write-Host "  Batch ID    : $batchId" -ForegroundColor White
Write-Host "  Total       : $moduleCount module(s)" -ForegroundColor White
Write-Host "  Succeeded   : $succeededCount" -ForegroundColor Green
Write-Host "  Failed      : $failedCount" -ForegroundColor $(if ($failedCount -gt 0) { "Red" } else { "Green" })
Write-Host "  Skipped     : $skippedCount" -ForegroundColor $(if ($skippedCount -gt 0) { "Yellow" } else { "Green" })
Write-Host "  Duration    : $($totalDuration.ToString('hh\:mm\:ss\.fff'))" -ForegroundColor White
Write-Host "  Report      : $ReportOutputPath" -ForegroundColor White
Write-Host "  Status      : $overallStatus" -ForegroundColor $(if ($failedCount -eq 0) { "Cyan" } else { "Red" })
Write-Host ""
Write-Host $summaryBorder -ForegroundColor Cyan
Write-Host ""

# ---------------------------------------------------------------------------
# Return Result Object
# ---------------------------------------------------------------------------
[PSCustomObject]@{
    BatchId       = $batchId
    TotalModules  = $moduleCount
    Succeeded     = $succeededCount
    Failed        = $failedCount
    Skipped       = $skippedCount
    Results       = $results
    ReportPath    = $ReportOutputPath
    Duration      = $totalDuration.ToString('hh\:mm\:ss\.fff')
    Timestamp     = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Status        = $overallStatus
}
