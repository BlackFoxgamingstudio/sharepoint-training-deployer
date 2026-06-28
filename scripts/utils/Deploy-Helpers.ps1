#Requires -Version 7.0
<#
.SYNOPSIS
    Shared utility functions for the SharePoint Training Deployer.

.DESCRIPTION
    This module provides common helper functions dot-sourced by all deployer scripts.
    Functions include structured logging, PnP connection testing, configuration loading,
    HTML report generation, safe operation execution, and SharePoint URL formatting.

.NOTES
    Author:  Sovereign Biz Box
    Version: 1.0.0
    Date:    2026-06-28
#>

# ---------------------------------------------------------------------------
# Script-scoped state
# ---------------------------------------------------------------------------
$script:CurrentLogFile = $null
$script:ProjectRoot    = $null

function Get-ProjectRoot {
    <#
    .SYNOPSIS
        Resolves the project root directory by walking up from this script's location.

    .DESCRIPTION
        Traverses parent directories from the utils/ folder until it finds a directory
        that contains a 'config' subfolder or reaches the filesystem root. Falls back
        to two levels up from the script directory (scripts/utils -> scripts -> root).

    .OUTPUTS
        [string] Absolute path to the project root.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if ($script:ProjectRoot) {
        return $script:ProjectRoot
    }

    $searchDir = $PSScriptRoot
    if (-not $searchDir) {
        $searchDir = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
    }

    # Walk up looking for config/ directory as a landmark
    $current = $searchDir
    while ($current -and $current -ne [System.IO.Path]::GetPathRoot($current)) {
        if (Test-Path (Join-Path $current 'config')) {
            $script:ProjectRoot = $current
            return $script:ProjectRoot
        }
        $current = Split-Path -Parent $current
    }

    # Fallback: assume utils/ is two levels below root  (root/scripts/utils/)
    $script:ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    return $script:ProjectRoot
}

# ---------------------------------------------------------------------------
# 1. Write-DeployLog
# ---------------------------------------------------------------------------
function Write-DeployLog {
    <#
    .SYNOPSIS
        Writes a structured log entry to the console and an on-disk log file.

    .DESCRIPTION
        Outputs a color-coded message to the console based on severity level and
        simultaneously appends a timestamped entry to a persistent log file. The
        log file is auto-created on the first invocation of the session at
        logs/deploy_YYYYMMDD_HHmmss.log under the project root.

    .PARAMETER Message
        The log message text.

    .PARAMETER Level
        Severity level. Accepted values: Info, Warning, Error, Success.
        Defaults to Info.

    .PARAMETER LogFile
        Optional explicit path to a log file. When provided, overrides the
        auto-generated session log file for this call only.

    .EXAMPLE
        Write-DeployLog -Message "Deployment started" -Level Info

    .EXAMPLE
        Write-DeployLog -Message "Page creation failed" -Level Error -LogFile "C:\logs\errors.log"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Message,

        [Parameter()]
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info',

        [Parameter()]
        [string]$LogFile
    )

    # Resolve the log file path
    $targetLogFile = $LogFile
    if (-not $targetLogFile) {
        if (-not $script:CurrentLogFile) {
            $logsDir = Join-Path (Get-ProjectRoot) 'logs'
            if (-not (Test-Path $logsDir)) {
                New-Item -Path $logsDir -ItemType Directory -Force | Out-Null
            }
            $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
            $script:CurrentLogFile = Join-Path $logsDir "deploy_${timestamp}.log"
        }
        $targetLogFile = $script:CurrentLogFile
    }

    # Build formatted entry
    $ts      = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    $padded  = $Level.ToUpper().PadRight(7)
    $logLine = "[$ts] [$padded] $Message"

    # Console color map
    $colorMap = @{
        Info    = 'Cyan'
        Warning = 'Yellow'
        Error   = 'Red'
        Success = 'Green'
    }

    $color = $colorMap[$Level]
    Write-Host $logLine -ForegroundColor $color

    # Ensure parent directory of the target log file exists
    $logDir = Split-Path -Parent $targetLogFile
    if ($logDir -and -not (Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }

    # Append to file (thread-safe via mutex for parallel scenarios)
    $mutexName = 'DeployLogMutex_' + ($targetLogFile -replace '[\\/:*?"<>|]', '_')
    $mutex = [System.Threading.Mutex]::new($false, $mutexName)
    try {
        [void]$mutex.WaitOne(5000)
        $logLine | Out-File -FilePath $targetLogFile -Append -Encoding utf8
    }
    finally {
        $mutex.ReleaseMutex()
        $mutex.Dispose()
    }
}

# ---------------------------------------------------------------------------
# 2. Test-PnPConnection
# ---------------------------------------------------------------------------
function Test-PnPConnection {
    <#
    .SYNOPSIS
        Tests whether an active PnP PowerShell connection exists.

    .DESCRIPTION
        Calls Get-PnPConnection and inspects the result. Returns $true when a
        valid connection is available, $false otherwise. All outcomes are logged
        via Write-DeployLog.

    .OUTPUTS
        [bool] $true if connected, $false otherwise.

    .EXAMPLE
        if (Test-PnPConnection) { Write-Host "Connected" }
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    Write-DeployLog -Message 'Testing PnP PowerShell connection...' -Level Info

    try {
        $connection = Get-PnPConnection -ErrorAction Stop

        if ($null -eq $connection) {
            Write-DeployLog -Message 'PnP connection returned null — not connected.' -Level Warning
            return $false
        }

        $url = $connection.Url
        Write-DeployLog -Message "PnP connection active — connected to: $url" -Level Success
        return $true
    }
    catch {
        Write-DeployLog -Message "PnP connection test failed: $($_.Exception.Message)" -Level Warning
        return $false
    }
}

# ---------------------------------------------------------------------------
# 3. Get-DeployConfig
# ---------------------------------------------------------------------------
function Get-DeployConfig {
    <#
    .SYNOPSIS
        Loads and validates the deployment configuration JSON file.

    .DESCRIPTION
        Reads config/deployment_config.json (relative to the project root unless
        an explicit path is given), parses it as JSON, and validates that the
        required keys TenantUrl, SiteUrlPrefix, and AdminEmail are present and
        non-empty. Returns a PSCustomObject with all configuration values.

    .PARAMETER ConfigPath
        Optional explicit path to the JSON config file. When omitted the function
        discovers the file by traversing up from the script location to find the
        project root's config/ directory.

    .OUTPUTS
        [PSCustomObject] Parsed and validated deployment configuration.

    .EXAMPLE
        $cfg = Get-DeployConfig
        Write-Host $cfg.TenantUrl

    .EXAMPLE
        $cfg = Get-DeployConfig -ConfigPath "C:\configs\deployment_config.json"
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$ConfigPath
    )

    # Discover config file
    if (-not $ConfigPath) {
        $root = Get-ProjectRoot
        $ConfigPath = Join-Path $root 'config' 'deployment_config.json'
    }

    Write-DeployLog -Message "Loading deployment config from: $ConfigPath" -Level Info

    if (-not (Test-Path $ConfigPath)) {
        $msg = "Deployment config not found at: $ConfigPath"
        Write-DeployLog -Message $msg -Level Error
        throw [System.IO.FileNotFoundException]::new($msg, $ConfigPath)
    }

    try {
        $raw    = Get-Content -Path $ConfigPath -Raw -Encoding utf8 -ErrorAction Stop
        $config = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        $msg = "Failed to parse deployment config: $($_.Exception.Message)"
        Write-DeployLog -Message $msg -Level Error
        throw
    }

    # Validate required keys
    $requiredKeys = @('TenantUrl', 'SiteUrlPrefix', 'AdminEmail')
    foreach ($key in $requiredKeys) {
        $value = $config.PSObject.Properties[$key]
        if (-not $value -or [string]::IsNullOrWhiteSpace($value.Value)) {
            $msg = "Deployment config is missing required key or has empty value: '$key'"
            Write-DeployLog -Message $msg -Level Error
            throw [System.ArgumentException]::new($msg)
        }
    }

    Write-DeployLog -Message "Deployment config loaded — Tenant: $($config.TenantUrl)" -Level Success
    return $config
}

# ---------------------------------------------------------------------------
# 4. Get-ModuleConfig
# ---------------------------------------------------------------------------
function Get-ModuleConfig {
    <#
    .SYNOPSIS
        Loads and validates a training module's configuration JSON file.

    .DESCRIPTION
        Builds the path content/<ModuleName>/module_config.json relative to the
        project root, reads and parses the JSON, validates required keys
        (ModuleTitle, ModuleId, Description, Sections), and returns a
        PSCustomObject.

    .PARAMETER ModuleName
        The folder name of the module under the content/ directory.

    .OUTPUTS
        [PSCustomObject] Parsed and validated module configuration.

    .EXAMPLE
        $mod = Get-ModuleConfig -ModuleName "onboarding_101"
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$ModuleName
    )

    $root       = Get-ProjectRoot
    $configPath = Join-Path $root 'content' $ModuleName 'module_config.json'

    Write-DeployLog -Message "Loading module config for '$ModuleName' from: $configPath" -Level Info

    if (-not (Test-Path $configPath)) {
        $msg = "Module config not found for '$ModuleName' at: $configPath"
        Write-DeployLog -Message $msg -Level Error
        throw [System.IO.FileNotFoundException]::new($msg, $configPath)
    }

    try {
        $raw    = Get-Content -Path $configPath -Raw -Encoding utf8 -ErrorAction Stop
        $config = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        $msg = "Failed to parse module config for '$ModuleName': $($_.Exception.Message)"
        Write-DeployLog -Message $msg -Level Error
        throw
    }

    # Validate required keys
    $requiredKeys = @('ModuleTitle', 'ModuleId', 'Description', 'Sections')
    foreach ($key in $requiredKeys) {
        $value = $config.PSObject.Properties[$key]
        if (-not $value) {
            $msg = "Module config for '$ModuleName' is missing required key: '$key'"
            Write-DeployLog -Message $msg -Level Error
            throw [System.ArgumentException]::new($msg)
        }

        # For non-array types ensure value is not blank
        if ($key -ne 'Sections' -and [string]::IsNullOrWhiteSpace($value.Value)) {
            $msg = "Module config for '$ModuleName' has empty value for required key: '$key'"
            Write-DeployLog -Message $msg -Level Error
            throw [System.ArgumentException]::new($msg)
        }

        # Sections must be a non-empty array
        if ($key -eq 'Sections') {
            $sections = $value.Value
            if ($null -eq $sections -or ($sections -is [array] -and $sections.Count -eq 0)) {
                $msg = "Module config for '$ModuleName' must have at least one section in 'Sections'."
                Write-DeployLog -Message $msg -Level Error
                throw [System.ArgumentException]::new($msg)
            }
        }
    }

    Write-DeployLog -Message "Module config loaded — $($config.ModuleTitle) (ID: $($config.ModuleId))" -Level Success
    return $config
}

# ---------------------------------------------------------------------------
# 5. New-DeploymentReport
# ---------------------------------------------------------------------------
function New-DeploymentReport {
    <#
    .SYNOPSIS
        Generates a styled HTML deployment report.

    .DESCRIPTION
        Accepts a hashtable of deployment metrics and produces a dark-themed HTML
        report file containing a deployment summary, timing information, page and
        asset counts, and an error listing. Returns the absolute path to the
        generated report file.

    .PARAMETER ReportData
        A hashtable with the following keys:
          ModuleName      — Name of the deployed module.
          SiteUrl         — Target SharePoint site URL.
          StartTime       — [datetime] when deployment started.
          EndTime         — [datetime] when deployment ended.
          PagesCreated    — [int] number of pages created.
          AssetsUploaded  — [int] number of assets uploaded.
          Errors          — [array] of error message strings (empty if none).

    .PARAMETER OutputPath
        File path where the HTML report will be written.

    .OUTPUTS
        [string] Absolute path to the generated HTML report.

    .EXAMPLE
        $data = @{
            ModuleName     = 'onboarding_101'
            SiteUrl        = 'https://contoso.sharepoint.com/sites/training'
            StartTime      = $start
            EndTime        = $end
            PagesCreated   = 12
            AssetsUploaded = 34
            Errors         = @()
        }
        $path = New-DeploymentReport -ReportData $data -OutputPath './reports/report.html'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ReportData,

        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    Write-DeployLog -Message "Generating deployment report for module '$($ReportData.ModuleName)'..." -Level Info

    # Validate required keys in ReportData
    $requiredDataKeys = @('ModuleName', 'SiteUrl', 'StartTime', 'EndTime', 'PagesCreated', 'AssetsUploaded', 'Errors')
    foreach ($key in $requiredDataKeys) {
        if (-not $ReportData.ContainsKey($key)) {
            $msg = "ReportData is missing required key: '$key'"
            Write-DeployLog -Message $msg -Level Error
            throw [System.ArgumentException]::new($msg)
        }
    }

    $duration    = ($ReportData.EndTime - $ReportData.StartTime)
    $durationStr = '{0:D2}h {1:D2}m {2:D2}s' -f $duration.Hours, $duration.Minutes, $duration.Seconds
    $errorCount  = if ($ReportData.Errors) { $ReportData.Errors.Count } else { 0 }
    $status      = if ($errorCount -eq 0) { 'SUCCESS' } else { 'COMPLETED WITH ERRORS' }
    $statusColor = if ($errorCount -eq 0) { '#00e676' } else { '#ff5252' }
    $statusEmoji = if ($errorCount -eq 0) { '&#10004;' } else { '&#9888;' }
    $generated   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'

    # Build error rows
    $errorRows = ''
    if ($errorCount -gt 0) {
        $idx = 0
        foreach ($err in $ReportData.Errors) {
            $idx++
            $escaped = [System.Net.WebUtility]::HtmlEncode($err)
            $errorRows += @"
                <tr>
                    <td style="padding:10px 14px;border-bottom:1px solid #333;color:#aaa;text-align:center;">$idx</td>
                    <td style="padding:10px 14px;border-bottom:1px solid #333;color:#ff8a80;font-family:'Cascadia Code','Fira Code',monospace;font-size:0.85em;">$escaped</td>
                </tr>
"@
        }
    }

    $errorSection = ''
    if ($errorCount -gt 0) {
        $errorSection = @"
        <div style="margin-top:32px;">
            <h2 style="color:#ff5252;font-size:1.15em;margin-bottom:12px;">&#9888; Errors ($errorCount)</h2>
            <table style="width:100%;border-collapse:collapse;background:#1a1a2e;border-radius:8px;overflow:hidden;">
                <thead>
                    <tr style="background:#16213e;">
                        <th style="padding:10px 14px;text-align:center;color:#64b5f6;font-size:0.85em;width:60px;">#</th>
                        <th style="padding:10px 14px;text-align:left;color:#64b5f6;font-size:0.85em;">Error Message</th>
                    </tr>
                </thead>
                <tbody>
                    $errorRows
                </tbody>
            </table>
        </div>
"@
    }

    $escapedModule  = [System.Net.WebUtility]::HtmlEncode($ReportData.ModuleName)
    $escapedSiteUrl = [System.Net.WebUtility]::HtmlEncode($ReportData.SiteUrl)
    $startStr       = $ReportData.StartTime.ToString('yyyy-MM-dd HH:mm:ss')
    $endStr         = $ReportData.EndTime.ToString('yyyy-MM-dd HH:mm:ss')

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Deployment Report — $escapedModule</title>
    <style>
        *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: 'Segoe UI', -apple-system, BlinkMacSystemFont, sans-serif;
            background: #0d1117;
            color: #e6edf3;
            padding: 40px 24px;
            line-height: 1.6;
        }
        .container {
            max-width: 780px;
            margin: 0 auto;
            background: linear-gradient(145deg, #161b22 0%, #0d1117 100%);
            border: 1px solid #30363d;
            border-radius: 12px;
            padding: 40px 36px;
            box-shadow: 0 16px 48px rgba(0, 0, 0, 0.4);
        }
        .header {
            text-align: center;
            margin-bottom: 32px;
            padding-bottom: 24px;
            border-bottom: 1px solid #21262d;
        }
        .header h1 {
            font-size: 1.6em;
            font-weight: 600;
            background: linear-gradient(135deg, #58a6ff, #bc8cff);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
        }
        .header .subtitle {
            color: #8b949e;
            font-size: 0.9em;
            margin-top: 6px;
        }
        .status-badge {
            display: inline-block;
            margin-top: 16px;
            padding: 6px 20px;
            border-radius: 20px;
            font-weight: 600;
            font-size: 0.85em;
            letter-spacing: 0.5px;
            color: $statusColor;
            border: 1px solid $statusColor;
            background: ${statusColor}15;
        }
        .metrics {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
            gap: 16px;
            margin: 28px 0;
        }
        .metric-card {
            background: #1a1f2b;
            border: 1px solid #30363d;
            border-radius: 8px;
            padding: 18px 16px;
            text-align: center;
        }
        .metric-card .value {
            font-size: 1.8em;
            font-weight: 700;
            color: #58a6ff;
        }
        .metric-card .label {
            font-size: 0.8em;
            color: #8b949e;
            margin-top: 4px;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        .detail-table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 24px;
        }
        .detail-table tr {
            border-bottom: 1px solid #21262d;
        }
        .detail-table td {
            padding: 10px 4px;
            font-size: 0.92em;
        }
        .detail-table td:first-child {
            color: #8b949e;
            width: 140px;
            font-weight: 500;
        }
        .detail-table td:last-child {
            color: #e6edf3;
        }
        .footer {
            margin-top: 36px;
            padding-top: 16px;
            border-top: 1px solid #21262d;
            text-align: center;
            font-size: 0.78em;
            color: #484f58;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>SharePoint Training Deployer</h1>
            <div class="subtitle">Deployment Report</div>
            <div class="status-badge">$statusEmoji $status</div>
        </div>

        <div class="metrics">
            <div class="metric-card">
                <div class="value">$($ReportData.PagesCreated)</div>
                <div class="label">Pages Created</div>
            </div>
            <div class="metric-card">
                <div class="value">$($ReportData.AssetsUploaded)</div>
                <div class="label">Assets Uploaded</div>
            </div>
            <div class="metric-card">
                <div class="value">$errorCount</div>
                <div class="label">Errors</div>
            </div>
            <div class="metric-card">
                <div class="value" style="font-size:1.1em;">$durationStr</div>
                <div class="label">Duration</div>
            </div>
        </div>

        <table class="detail-table">
            <tr><td>Module</td><td>$escapedModule</td></tr>
            <tr><td>Site URL</td><td><a href="$escapedSiteUrl" style="color:#58a6ff;text-decoration:none;">$escapedSiteUrl</a></td></tr>
            <tr><td>Started</td><td>$startStr</td></tr>
            <tr><td>Completed</td><td>$endStr</td></tr>
        </table>

        $errorSection

        <div class="footer">
            Generated by SharePoint Training Deployer &mdash; $generated
        </div>
    </div>
</body>
</html>
"@

    # Ensure output directory exists
    $outDir = Split-Path -Parent $OutputPath
    if ($outDir -and -not (Test-Path $outDir)) {
        New-Item -Path $outDir -ItemType Directory -Force | Out-Null
    }

    $html | Out-File -FilePath $OutputPath -Encoding utf8 -Force
    $resolvedPath = (Resolve-Path $OutputPath).Path

    Write-DeployLog -Message "Deployment report saved to: $resolvedPath" -Level Success
    return $resolvedPath
}

# ---------------------------------------------------------------------------
# 6. Invoke-SafeOperation
# ---------------------------------------------------------------------------
function Invoke-SafeOperation {
    <#
    .SYNOPSIS
        Executes a script block with structured error handling and logging.

    .DESCRIPTION
        Wraps execution of a script block in a try/catch, logs the start,
        completion, and any failure via Write-DeployLog. Returns the result
        of the script block on success, or $null on failure when
        -ContinueOnError is set. Re-throws the exception otherwise.

    .PARAMETER OperationName
        A human-readable name for the operation (used in log messages).

    .PARAMETER ScriptBlock
        The script block to execute.

    .PARAMETER ContinueOnError
        When set, exceptions are caught and logged but not re-thrown.
        The function returns $null in this case.

    .OUTPUTS
        The output of the ScriptBlock, or $null on caught error.

    .EXAMPLE
        $result = Invoke-SafeOperation -OperationName "Create Page" -ScriptBlock {
            Add-PnPPage -Name "Welcome"
        }

    .EXAMPLE
        Invoke-SafeOperation -OperationName "Upload Asset" -ScriptBlock {
            Add-PnPFile -Path "./logo.png" -Folder "SiteAssets"
        } -ContinueOnError
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$OperationName,

        [Parameter(Mandatory, Position = 1)]
        [scriptblock]$ScriptBlock,

        [Parameter()]
        [switch]$ContinueOnError
    )

    Write-DeployLog -Message "Starting operation: $OperationName" -Level Info

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        $result = & $ScriptBlock
        $stopwatch.Stop()

        $elapsed = $stopwatch.Elapsed.TotalSeconds.ToString('F2')
        Write-DeployLog -Message "Completed operation: $OperationName (${elapsed}s)" -Level Success

        return $result
    }
    catch {
        $stopwatch.Stop()
        $elapsed = $stopwatch.Elapsed.TotalSeconds.ToString('F2')
        $errMsg  = $_.Exception.Message

        Write-DeployLog -Message "Failed operation: $OperationName after ${elapsed}s — $errMsg" -Level Error

        if ($ContinueOnError.IsPresent) {
            Write-DeployLog -Message "ContinueOnError is set — suppressing exception for: $OperationName" -Level Warning
            return $null
        }

        throw
    }
}

# ---------------------------------------------------------------------------
# 7. Format-SharePointUrl
# ---------------------------------------------------------------------------
function Format-SharePointUrl {
    <#
    .SYNOPSIS
        Normalizes and validates a SharePoint URL.

    .DESCRIPTION
        Trims whitespace, removes trailing slashes, and validates that the URL
        starts with https://. Returns the cleaned URL string. Throws
        ArgumentException if the URL is empty or does not begin with https://.

    .PARAMETER Url
        The SharePoint URL to normalize.

    .OUTPUTS
        [string] The cleaned and validated URL.

    .EXAMPLE
        $cleanUrl = Format-SharePointUrl -Url "  https://contoso.sharepoint.com/sites/training/  "
        # Returns: https://contoso.sharepoint.com/sites/training
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Url
    )

    # Trim whitespace
    $cleaned = $Url.Trim()

    if ([string]::IsNullOrWhiteSpace($cleaned)) {
        $msg = 'URL cannot be empty or whitespace.'
        Write-DeployLog -Message $msg -Level Error
        throw [System.ArgumentException]::new($msg)
    }

    # Remove trailing slashes
    $cleaned = $cleaned.TrimEnd('/')

    # Validate HTTPS
    if (-not $cleaned.StartsWith('https://', [System.StringComparison]::OrdinalIgnoreCase)) {
        $msg = "URL must start with 'https://'. Received: $cleaned"
        Write-DeployLog -Message $msg -Level Error
        throw [System.ArgumentException]::new($msg)
    }

    Write-DeployLog -Message "Formatted URL: $cleaned" -Level Info
    return $cleaned
}
