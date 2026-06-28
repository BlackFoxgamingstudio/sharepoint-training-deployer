<#
.SYNOPSIS
    Creates modern SharePoint pages for a training module deployment.

.DESCRIPTION
    Builds 5 modern SharePoint pages (Home, Procedure-Guide, Media-Resources,
    Assessment, Field-Logs) using PnP PowerShell. Each page is constructed with
    rich HTML content, inline CSS styling, and structured sections. Pages are
    published immediately after creation.

    This script is designed to run as part of the SharePoint Training Deployer
    pipeline and expects helper functions from Deploy-Helpers.ps1.

.PARAMETER SiteUrl
    The full URL of the target SharePoint site (e.g., https://contoso.sharepoint.com/sites/Training).

.PARAMETER ModuleName
    The name of the training module to deploy. Used to load module configuration
    via Get-ModuleConfig.

.PARAMETER AssetUrls
    A hashtable containing URLs for deployed assets. Required keys:
        - SlidesFolder   : URL to the folder containing uploaded slide images.
        - VideoUrl        : Direct URL or embed URL for the training video.
        - AppUrl          : URL to the interactive assessment application.
        - AppFolder       : URL to the folder containing application assets.
        - ServiceRecordsListUrl : URL to the Service Records SharePoint list.
        - SlideUrls       : Array of direct URLs to individual slide images.

.EXAMPLE
    $assets = @{
        SlidesFolder          = "https://contoso.sharepoint.com/sites/Training/SiteAssets/Slides"
        VideoUrl              = "https://contoso.sharepoint.com/sites/Training/SiteAssets/video.mp4"
        AppUrl                = "https://contoso.sharepoint.com/sites/Training/SiteAssets/app/index.html"
        AppFolder             = "https://contoso.sharepoint.com/sites/Training/SiteAssets/app"
        ServiceRecordsListUrl = "https://contoso.sharepoint.com/sites/Training/Lists/ServiceRecords"
        SlideUrls             = @("https://contoso.sharepoint.com/.../slide1.png", "https://contoso.sharepoint.com/.../slide2.png")
    }
    .\02_Create_SharePoint_Pages.ps1 -SiteUrl "https://contoso.sharepoint.com/sites/Training" -ModuleName "HVAC-Fundamentals" -AssetUrls $assets

.NOTES
    Author  : Sovereign Biz Box Automation
    Version : 1.0.0
    Requires: PnP.PowerShell module, Deploy-Helpers.ps1
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "SharePoint site URL for page deployment.")]
    [ValidateNotNullOrEmpty()]
    [string]$SiteUrl,

    [Parameter(Mandatory = $true, HelpMessage = "Training module name for configuration lookup.")]
    [ValidateNotNullOrEmpty()]
    [string]$ModuleName,

    [Parameter(Mandatory = $true, HelpMessage = "Hashtable of asset URLs (SlidesFolder, VideoUrl, AppUrl, AppFolder, ServiceRecordsListUrl, SlideUrls).")]
    [ValidateNotNull()]
    [hashtable]$AssetUrls
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Dot-source helpers
# ---------------------------------------------------------------------------
$helpersPath = Join-Path -Path $PSScriptRoot -ChildPath "utils/Deploy-Helpers.ps1"
if (-not (Test-Path -Path $helpersPath)) {
    throw "Required helper script not found: $helpersPath"
}
. $helpersPath

# ---------------------------------------------------------------------------
# Validate AssetUrls keys
# ---------------------------------------------------------------------------
$requiredKeys = @("SlidesFolder", "VideoUrl", "AppUrl", "AppFolder", "ServiceRecordsListUrl", "SlideUrls")
foreach ($key in $requiredKeys) {
    if (-not $AssetUrls.ContainsKey($key)) {
        throw "AssetUrls hashtable is missing required key: '$key'. Required keys: $($requiredKeys -join ', ')"
    }
}

# ---------------------------------------------------------------------------
# Load module configuration
# ---------------------------------------------------------------------------
Write-DeployLog -Message "Loading module configuration for '$ModuleName'..." -Level "Info"
$moduleConfig = Get-ModuleConfig -ModuleName $ModuleName

$moduleTitle       = $moduleConfig.Title
$moduleDescription = $moduleConfig.Description
$moduleVersion     = $moduleConfig.Version
$procedures        = $moduleConfig.Procedures
$assessmentConfig  = $moduleConfig.Assessment
$safetyItems       = $moduleConfig.SafetyPrecautions
$toolsMaterials    = $moduleConfig.ToolsAndMaterials
$keyMetrics        = $moduleConfig.KeyMetrics

Write-DeployLog -Message "Module config loaded: '$moduleTitle' v$moduleVersion" -Level "Info"

# ---------------------------------------------------------------------------
# Shared CSS Styles
# ---------------------------------------------------------------------------
$cssReset = "margin:0;padding:0;box-sizing:border-box;"
$fontStack = "font-family:'Segoe UI','Helvetica Neue',Arial,sans-serif;"
$cardStyle = "background:#ffffff;border-radius:12px;padding:28px 32px;margin:20px 0;box-shadow:0 2px 12px rgba(0,0,0,0.08);border:1px solid #e8e8e8;"
$headingStyle = "color:#1a1a2e;font-weight:700;margin-bottom:12px;$fontStack"
$bodyTextStyle = "color:#444444;font-size:15px;line-height:1.7;$fontStack"
$accentCyan = "#00d4ff"
$accentDark = "#1a1a2e"
$accentMid = "#16213e"
$warningYellow = "#fff3cd"
$warningBorder = "#ffc107"
$successGreen = "#28a745"
$linkStyle = "color:#0078d4;text-decoration:none;font-weight:600;"
$buttonStyle = "display:inline-block;padding:14px 36px;background:linear-gradient(135deg,$accentCyan,#0078d4);color:#ffffff;text-decoration:none;border-radius:8px;font-weight:700;font-size:16px;$fontStack;box-shadow:0 4px 15px rgba(0,212,255,0.3);transition:all 0.3s ease;"
$tableHeaderStyle = "background:linear-gradient(135deg,$accentDark,$accentMid);color:#ffffff;padding:14px 18px;text-align:left;font-weight:600;font-size:14px;$fontStack"
$tableCellStyle = "padding:12px 18px;border-bottom:1px solid #eee;font-size:14px;color:#444;$fontStack"
$badgeStyle = "display:inline-block;padding:4px 14px;border-radius:20px;font-size:12px;font-weight:700;$fontStack"
$sectionDivider = "<div style='height:2px;background:linear-gradient(90deg,$accentCyan,transparent);margin:32px 0;'></div>"

# ---------------------------------------------------------------------------
# Helper: Create a single SharePoint page
# ---------------------------------------------------------------------------
function New-TrainingPage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PageName,
        [Parameter(Mandatory)][string]$HtmlContent,
        [Parameter(Mandatory)][string]$Description
    )

    Invoke-SafeOperation -OperationName "Create page '$PageName'" -ScriptBlock {
        Write-DeployLog -Message "Removing existing page '$PageName' if present..." -Level "Info"
        Remove-PnPPage -Identity $PageName -Force -ErrorAction SilentlyContinue

        Write-DeployLog -Message "Creating new page '$PageName'..." -Level "Info"
        $page = Add-PnPPage -Name $PageName -LayoutType Article

        Write-DeployLog -Message "Adding content section to '$PageName'..." -Level "Info"
        Add-PnPPageSection -Page $page -SectionTemplate OneColumn -Order 1

        Write-DeployLog -Message "Inserting HTML content into '$PageName'..." -Level "Info"
        Add-PnPPageTextPart -Page $page -Section 1 -Column 1 -Text $HtmlContent

        Write-DeployLog -Message "Publishing page '$PageName'..." -Level "Info"
        Set-PnPPage -Identity $PageName -Publish

        Write-DeployLog -Message "Page '$PageName' created and published successfully." -Level "Success"
    }
}

# ---------------------------------------------------------------------------
# PAGE 1 — Home.aspx
# ---------------------------------------------------------------------------
function Build-HomePageHtml {
    [CmdletBinding()]
    param()

    $metricsHtml = ""
    if ($keyMetrics -and $keyMetrics.Count -gt 0) {
        $metricCards = ""
        $metricColors = @("#00d4ff", "#7c3aed", "#f59e0b", "#10b981", "#ef4444", "#6366f1")
        $colorIndex = 0
        foreach ($metric in $keyMetrics) {
            $color = $metricColors[$colorIndex % $metricColors.Count]
            $metricCards += @"
<div style='flex:1;min-width:180px;background:#ffffff;border-radius:12px;padding:24px;text-align:center;box-shadow:0 2px 12px rgba(0,0,0,0.08);border-top:4px solid $color;'>
    <div style='font-size:32px;font-weight:800;color:$color;$fontStack'>$($metric.Value)</div>
    <div style='font-size:13px;color:#888;margin-top:6px;font-weight:600;text-transform:uppercase;letter-spacing:0.5px;$fontStack'>$($metric.Label)</div>
</div>
"@
            $colorIndex++
        }
        $metricsHtml = @"
<div style='display:flex;gap:20px;flex-wrap:wrap;margin:28px 0;'>
$metricCards
</div>
"@
    }

    $quickLinks = @"
<div style='display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:16px;margin:24px 0;'>
    <a href='Procedure-Guide.aspx' style='$cardStyle;text-decoration:none;display:block;border-left:4px solid #7c3aed;transition:transform 0.2s ease;'>
        <div style='font-size:24px;margin-bottom:8px;'>📋</div>
        <div style='font-weight:700;color:$accentDark;font-size:16px;$fontStack'>Procedure Guide</div>
        <div style='color:#888;font-size:13px;margin-top:4px;$fontStack'>Step-by-step operating procedures</div>
    </a>
    <a href='Media-Resources.aspx' style='$cardStyle;text-decoration:none;display:block;border-left:4px solid $accentCyan;transition:transform 0.2s ease;'>
        <div style='font-size:24px;margin-bottom:8px;'>🎬</div>
        <div style='font-weight:700;color:$accentDark;font-size:16px;$fontStack'>Media Resources</div>
        <div style='color:#888;font-size:13px;margin-top:4px;$fontStack'>Slides, video, and interactive content</div>
    </a>
    <a href='Assessment.aspx' style='$cardStyle;text-decoration:none;display:block;border-left:4px solid $successGreen;transition:transform 0.2s ease;'>
        <div style='font-size:24px;margin-bottom:8px;'>✅</div>
        <div style='font-weight:700;color:$accentDark;font-size:16px;$fontStack'>Assessment</div>
        <div style='color:#888;font-size:13px;margin-top:4px;$fontStack'>Knowledge check and certification</div>
    </a>
    <a href='Field-Logs.aspx' style='$cardStyle;text-decoration:none;display:block;border-left:4px solid #f59e0b;transition:transform 0.2s ease;'>
        <div style='font-size:24px;margin-bottom:8px;'>📝</div>
        <div style='font-weight:700;color:$accentDark;font-size:16px;$fontStack'>Field Logs</div>
        <div style='color:#888;font-size:13px;margin-top:4px;$fontStack'>Service records and documentation</div>
    </a>
</div>
"@

    $html = @"
<!-- HOME PAGE — $moduleTitle -->
<div style='$cssReset'>

    <!-- Hero Banner -->
    <div style='background:linear-gradient(135deg,$accentDark,$accentMid);border-radius:16px;padding:60px 48px;margin-bottom:32px;position:relative;overflow:hidden;'>
        <div style='position:absolute;top:-40px;right:-40px;width:200px;height:200px;background:radial-gradient(circle,$accentCyan 0%,transparent 70%);opacity:0.15;'></div>
        <div style='position:absolute;bottom:-60px;left:-60px;width:300px;height:300px;background:radial-gradient(circle,#7c3aed 0%,transparent 70%);opacity:0.1;'></div>
        <div style='position:relative;z-index:1;'>
            <div style='$badgeStyle;background:rgba(0,212,255,0.15);color:$accentCyan;margin-bottom:16px;'>Training Module v$moduleVersion</div>
            <h1 style='color:#ffffff;font-size:36px;font-weight:800;margin:0 0 16px 0;$fontStack;letter-spacing:-0.5px;'>$moduleTitle</h1>
            <p style='color:rgba(255,255,255,0.8);font-size:18px;line-height:1.6;margin:0;max-width:700px;$fontStack'>$moduleDescription</p>
        </div>
    </div>

    <!-- Executive Summary -->
    <div style='$cardStyle'>
        <h2 style='$headingStyle;font-size:22px;'>📌 Executive Summary</h2>
        $sectionDivider
        <p style='$bodyTextStyle'>$moduleDescription</p>
        <p style='$bodyTextStyle;margin-top:12px;'>This training module provides comprehensive instruction including standard operating procedures, multimedia learning resources, knowledge assessments, and field documentation tools. Complete all sections to achieve certification.</p>
    </div>

    <!-- Key Metrics -->
    $metricsHtml

    <!-- Quick Links -->
    <div style='$cardStyle'>
        <h2 style='$headingStyle;font-size:22px;'>🚀 Quick Navigation</h2>
        $sectionDivider
        $quickLinks
    </div>

</div>
"@

    return $html
}

# ---------------------------------------------------------------------------
# PAGE 2 — Procedure-Guide.aspx
# ---------------------------------------------------------------------------
function Build-ProcedureGuideHtml {
    [CmdletBinding()]
    param()

    # Safety precautions list
    $safetyHtml = ""
    if ($safetyItems -and $safetyItems.Count -gt 0) {
        $safetyListItems = ""
        foreach ($item in $safetyItems) {
            $safetyListItems += "<li style='padding:8px 0;color:#856404;font-size:14px;$fontStack'>$item</li>`n"
        }
        $safetyHtml = @"
<div style='background:$warningYellow;border:1px solid $warningBorder;border-radius:12px;padding:24px 28px;margin:24px 0;'>
    <h3 style='color:#856404;font-size:18px;font-weight:700;margin:0 0 12px 0;$fontStack'>⚠️ Safety Warning — Read Before Proceeding</h3>
    <p style='color:#856404;font-size:14px;margin:0 0 12px 0;$fontStack'>The following safety precautions are mandatory. Failure to comply may result in injury, equipment damage, or disciplinary action.</p>
    <ul style='margin:0;padding-left:24px;'>
$safetyListItems
    </ul>
</div>
"@
    }

    # Tools & Materials
    $toolsHtml = ""
    if ($toolsMaterials -and $toolsMaterials.Count -gt 0) {
        $toolRows = ""
        $toolIndex = 1
        foreach ($tool in $toolsMaterials) {
            $bgColor = if ($toolIndex % 2 -eq 0) { "#f9fafb" } else { "#ffffff" }
            $toolRows += @"
<tr style='background:$bgColor;'>
    <td style='$tableCellStyle;font-weight:600;width:40px;color:$accentDark;'>$toolIndex</td>
    <td style='$tableCellStyle;font-weight:600;color:$accentDark;'>$($tool.Name)</td>
    <td style='$tableCellStyle'>$($tool.Description)</td>
    <td style='$tableCellStyle;text-align:center;'>
        <span style='$badgeStyle;background:$(if($tool.Required){"#dcfce7;color:#16a34a"}else{"#f3f4f6;color:#6b7280"});'>$(if($tool.Required){"Required"}else{"Optional"})</span>
    </td>
</tr>
"@
            $toolIndex++
        }
        $toolsHtml = @"
<div style='$cardStyle'>
    <h2 style='$headingStyle;font-size:22px;'>🔧 Tools &amp; Materials</h2>
    $sectionDivider
    <table style='width:100%;border-collapse:collapse;border-radius:8px;overflow:hidden;'>
        <thead>
            <tr>
                <th style='$tableHeaderStyle;width:40px;'>#</th>
                <th style='$tableHeaderStyle'>Item</th>
                <th style='$tableHeaderStyle'>Description</th>
                <th style='$tableHeaderStyle;text-align:center;'>Status</th>
            </tr>
        </thead>
        <tbody>
$toolRows
        </tbody>
    </table>
</div>
"@
    }

    # Procedure Phases
    $phasesHtml = ""
    $phaseColors = @("#00d4ff", "#7c3aed", "#f59e0b", "#10b981")
    if ($procedures -and $procedures.Count -gt 0) {
        $phaseIndex = 0
        foreach ($phase in $procedures) {
            $phaseColor = $phaseColors[$phaseIndex % $phaseColors.Count]
            $phaseNumber = $phaseIndex + 1

            $stepsHtml = ""
            $stepIndex = 1
            foreach ($step in $phase.Steps) {
                $stepsHtml += @"
<div style='display:flex;gap:16px;align-items:flex-start;margin:16px 0;padding:16px;background:#f9fafb;border-radius:8px;border-left:3px solid $phaseColor;'>
    <div style='min-width:36px;height:36px;background:$phaseColor;color:#fff;border-radius:50%;display:flex;align-items:center;justify-content:center;font-weight:800;font-size:14px;$fontStack'>$stepIndex</div>
    <div>
        <div style='font-weight:700;color:$accentDark;font-size:15px;margin-bottom:4px;$fontStack'>$($step.Title)</div>
        <div style='color:#666;font-size:14px;line-height:1.6;$fontStack'>$($step.Description)</div>
    </div>
</div>
"@
                $stepIndex++
            }

            $phasesHtml += @"
<div style='$cardStyle;border-top:4px solid $phaseColor;'>
    <div style='display:flex;align-items:center;gap:14px;margin-bottom:16px;'>
        <div style='min-width:48px;height:48px;background:linear-gradient(135deg,$phaseColor,$(if($phaseColor -eq '#00d4ff'){'#0078d4'}else{$phaseColor}));border-radius:12px;display:flex;align-items:center;justify-content:center;color:#fff;font-weight:800;font-size:20px;$fontStack'>$phaseNumber</div>
        <div>
            <h3 style='color:$accentDark;font-size:20px;font-weight:700;margin:0;$fontStack'>$($phase.Title)</h3>
            <p style='color:#888;font-size:13px;margin:4px 0 0 0;$fontStack'>$($phase.Description)</p>
        </div>
    </div>
    $stepsHtml
</div>
"@
            $phaseIndex++
        }
    }

    $html = @"
<!-- PROCEDURE GUIDE PAGE — $moduleTitle -->
<div style='$cssReset'>

    <!-- SOP Header -->
    <div style='background:linear-gradient(135deg,#7c3aed,#5b21b6);border-radius:16px;padding:48px;margin-bottom:28px;'>
        <div style='$badgeStyle;background:rgba(255,255,255,0.15);color:#ffffff;margin-bottom:14px;'>Standard Operating Procedure</div>
        <h1 style='color:#ffffff;font-size:32px;font-weight:800;margin:0 0 12px 0;$fontStack'>$moduleTitle — Procedure Guide</h1>
        <p style='color:rgba(255,255,255,0.8);font-size:16px;margin:0;$fontStack'>Follow each phase sequentially. Do not skip steps unless authorized by a supervisor.</p>
    </div>

    <!-- Safety Warning -->
    $safetyHtml

    <!-- Tools & Materials -->
    $toolsHtml

    <!-- Procedure Phases -->
    <div style='$cardStyle;background:#f0f4ff;border:none;'>
        <h2 style='$headingStyle;font-size:22px;'>📋 Procedure Phases</h2>
        <p style='$bodyTextStyle'>Complete each phase in order. Verify all checklist items before advancing to the next phase.</p>
    </div>

    $phasesHtml

</div>
"@

    return $html
}

# ---------------------------------------------------------------------------
# PAGE 3 — Media-Resources.aspx
# ---------------------------------------------------------------------------
function Build-MediaResourcesHtml {
    [CmdletBinding()]
    param()

    # Slides Gallery
    $slidesGalleryHtml = ""
    $slideUrls = $AssetUrls.SlideUrls
    if ($slideUrls -and $slideUrls.Count -gt 0) {
        $slideCards = ""
        $slideNum = 1
        foreach ($slideUrl in $slideUrls) {
            $slideCards += @"
<div style='background:#ffffff;border-radius:10px;overflow:hidden;box-shadow:0 2px 10px rgba(0,0,0,0.08);transition:transform 0.2s ease;'>
    <img src='$slideUrl' alt='Slide $slideNum' style='width:100%;height:auto;display:block;border-bottom:1px solid #eee;' />
    <div style='padding:10px 14px;'>
        <span style='font-size:13px;font-weight:600;color:$accentDark;$fontStack'>Slide $slideNum</span>
    </div>
</div>
"@
            $slideNum++
        }
        $slidesGalleryHtml = @"
<div style='$cardStyle'>
    <h2 style='$headingStyle;font-size:22px;'>🖼️ Presentation Slides</h2>
    $sectionDivider
    <p style='$bodyTextStyle;margin-bottom:20px;'>Review each slide carefully. Click any slide to view it at full resolution.</p>
    <div style='display:grid;grid-template-columns:repeat(auto-fill,minmax(280px,1fr));gap:20px;'>
$slideCards
    </div>
    <div style='margin-top:16px;text-align:center;'>
        <a href='$($AssetUrls.SlidesFolder)' style='$linkStyle;font-size:14px;' target='_blank'>📂 Open Slides Folder</a>
    </div>
</div>
"@
    }

    # Video Embed
    $videoUrl = $AssetUrls.VideoUrl
    $videoEmbedHtml = @"
<div style='$cardStyle'>
    <h2 style='$headingStyle;font-size:22px;'>🎬 Training Video</h2>
    $sectionDivider
    <p style='$bodyTextStyle;margin-bottom:20px;'>Watch the complete training video. Pause and rewind as needed to ensure full comprehension.</p>
    <div style='position:relative;padding-bottom:56.25%;height:0;overflow:hidden;border-radius:12px;background:#000;box-shadow:0 4px 20px rgba(0,0,0,0.15);'>
        <iframe src='$videoUrl' style='position:absolute;top:0;left:0;width:100%;height:100%;border:none;' allowfullscreen></iframe>
    </div>
    <div style='margin-top:12px;text-align:center;'>
        <a href='$videoUrl' style='$linkStyle;font-size:14px;' target='_blank'>🔗 Open Video Directly</a>
    </div>
</div>
"@

    # Interactive App Link
    $appUrl = $AssetUrls.AppUrl
    $interactiveHtml = @"
<div style='$cardStyle;background:linear-gradient(135deg,#f0f9ff,#e0f2fe);border:1px solid #bae6fd;'>
    <h2 style='$headingStyle;font-size:22px;'>🎮 Interactive Application</h2>
    $sectionDivider
    <p style='$bodyTextStyle;margin-bottom:24px;'>Launch the interactive training application for hands-on practice with the concepts covered in this module.</p>
    <div style='text-align:center;padding:20px 0;'>
        <a href='$appUrl' style='$buttonStyle' target='_blank'>🚀 Launch Interactive App</a>
    </div>
    <div style='margin-top:12px;text-align:center;'>
        <a href='$($AssetUrls.AppFolder)' style='$linkStyle;font-size:13px;' target='_blank'>📂 View App Files</a>
    </div>
</div>
"@

    $html = @"
<!-- MEDIA RESOURCES PAGE — $moduleTitle -->
<div style='$cssReset'>

    <!-- Header -->
    <div style='background:linear-gradient(135deg,$accentCyan,#0078d4);border-radius:16px;padding:48px;margin-bottom:28px;'>
        <div style='$badgeStyle;background:rgba(255,255,255,0.2);color:#ffffff;margin-bottom:14px;'>Multimedia Learning</div>
        <h1 style='color:#ffffff;font-size:32px;font-weight:800;margin:0 0 12px 0;$fontStack'>Media Resources</h1>
        <p style='color:rgba(255,255,255,0.85);font-size:16px;margin:0;$fontStack'>Slides, video, and interactive materials for $moduleTitle.</p>
    </div>

    <!-- Slides Gallery -->
    $slidesGalleryHtml

    <!-- Video -->
    $videoEmbedHtml

    <!-- Interactive App -->
    $interactiveHtml

</div>
"@

    return $html
}

# ---------------------------------------------------------------------------
# PAGE 4 — Assessment.aspx
# ---------------------------------------------------------------------------
function Build-AssessmentHtml {
    [CmdletBinding()]
    param()

    $quizQuestions = if ($assessmentConfig.Questions) { $assessmentConfig.Questions.Count } else { 0 }
    $passingScore  = if ($assessmentConfig.PassingScore) { $assessmentConfig.PassingScore } else { "80%" }
    $timeLimit     = if ($assessmentConfig.TimeLimit) { $assessmentConfig.TimeLimit } else { "30 minutes" }

    # Quiz details
    $questionsRowsHtml = ""
    if ($assessmentConfig.Questions -and $assessmentConfig.Questions.Count -gt 0) {
        $qIndex = 1
        foreach ($q in $assessmentConfig.Questions) {
            $bgColor = if ($qIndex % 2 -eq 0) { "#f9fafb" } else { "#ffffff" }
            $diffColor = switch ($q.Difficulty) {
                "Easy"     { "#dcfce7;color:#16a34a" }
                "Medium"   { "#fef3c7;color:#d97706" }
                "Hard"     { "#fee2e2;color:#dc2626" }
                default    { "#f3f4f6;color:#6b7280" }
            }
            $questionsRowsHtml += @"
<tr style='background:$bgColor;'>
    <td style='$tableCellStyle;font-weight:600;width:40px;color:$accentDark;'>$qIndex</td>
    <td style='$tableCellStyle'>$($q.Topic)</td>
    <td style='$tableCellStyle;text-align:center;'>$($q.Type)</td>
    <td style='$tableCellStyle;text-align:center;'>
        <span style='$badgeStyle;background:$diffColor;'>$($q.Difficulty)</span>
    </td>
    <td style='$tableCellStyle;text-align:center;'>$($q.Points) pts</td>
</tr>
"@
            $qIndex++
        }
    }

    # Compliance checklist
    $checklistHtml = ""
    if ($assessmentConfig.ComplianceChecklist -and $assessmentConfig.ComplianceChecklist.Count -gt 0) {
        $checkRows = ""
        $checkIndex = 1
        foreach ($item in $assessmentConfig.ComplianceChecklist) {
            $bgColor = if ($checkIndex % 2 -eq 0) { "#f9fafb" } else { "#ffffff" }
            $checkRows += @"
<tr style='background:$bgColor;'>
    <td style='$tableCellStyle;width:40px;text-align:center;font-size:18px;'>☐</td>
    <td style='$tableCellStyle;font-weight:600;color:$accentDark;'>$($item.Requirement)</td>
    <td style='$tableCellStyle'>$($item.Description)</td>
    <td style='$tableCellStyle;text-align:center;'>
        <span style='$badgeStyle;background:#f3f4f6;color:#6b7280;'>Pending</span>
    </td>
</tr>
"@
            $checkIndex++
        }
        $checklistHtml = @"
<div style='$cardStyle'>
    <h2 style='$headingStyle;font-size:22px;'>📋 Compliance Checklist</h2>
    $sectionDivider
    <p style='$bodyTextStyle;margin-bottom:16px;'>All items must be completed before certification can be issued.</p>
    <table style='width:100%;border-collapse:collapse;border-radius:8px;overflow:hidden;'>
        <thead>
            <tr>
                <th style='$tableHeaderStyle;width:40px;'>✓</th>
                <th style='$tableHeaderStyle'>Requirement</th>
                <th style='$tableHeaderStyle'>Description</th>
                <th style='$tableHeaderStyle;text-align:center;'>Status</th>
            </tr>
        </thead>
        <tbody>
$checkRows
        </tbody>
    </table>
</div>
"@
    }

    $appUrl = $AssetUrls.AppUrl

    $html = @"
<!-- ASSESSMENT PAGE — $moduleTitle -->
<div style='$cssReset'>

    <!-- Header -->
    <div style='background:linear-gradient(135deg,$successGreen,#16a34a);border-radius:16px;padding:48px;margin-bottom:28px;'>
        <div style='$badgeStyle;background:rgba(255,255,255,0.2);color:#ffffff;margin-bottom:14px;'>Knowledge Verification</div>
        <h1 style='color:#ffffff;font-size:32px;font-weight:800;margin:0 0 12px 0;$fontStack'>Assessment Center</h1>
        <p style='color:rgba(255,255,255,0.85);font-size:16px;margin:0;$fontStack'>Complete the assessment to demonstrate mastery of $moduleTitle.</p>
    </div>

    <!-- Assessment Overview -->
    <div style='$cardStyle'>
        <h2 style='$headingStyle;font-size:22px;'>📊 Assessment Overview</h2>
        $sectionDivider
        <p style='$bodyTextStyle'>This assessment evaluates your understanding of the procedures, safety requirements, and technical knowledge covered in the <strong>$moduleTitle</strong> training module.</p>
        <div style='display:flex;gap:20px;flex-wrap:wrap;margin:24px 0;'>
            <div style='flex:1;min-width:160px;background:#f0fdf4;border-radius:10px;padding:20px;text-align:center;border:1px solid #bbf7d0;'>
                <div style='font-size:28px;font-weight:800;color:$successGreen;$fontStack'>$quizQuestions</div>
                <div style='font-size:12px;color:#888;font-weight:600;text-transform:uppercase;margin-top:4px;$fontStack'>Questions</div>
            </div>
            <div style='flex:1;min-width:160px;background:#eff6ff;border-radius:10px;padding:20px;text-align:center;border:1px solid #bfdbfe;'>
                <div style='font-size:28px;font-weight:800;color:#2563eb;$fontStack'>$passingScore</div>
                <div style='font-size:12px;color:#888;font-weight:600;text-transform:uppercase;margin-top:4px;$fontStack'>Passing Score</div>
            </div>
            <div style='flex:1;min-width:160px;background:#fefce8;border-radius:10px;padding:20px;text-align:center;border:1px solid #fde68a;'>
                <div style='font-size:28px;font-weight:800;color:#d97706;$fontStack'>$timeLimit</div>
                <div style='font-size:12px;color:#888;font-weight:600;text-transform:uppercase;margin-top:4px;$fontStack'>Time Limit</div>
            </div>
        </div>
    </div>

    <!-- Quiz Details -->
    <div style='$cardStyle'>
        <h2 style='$headingStyle;font-size:22px;'>📝 Quiz Details</h2>
        $sectionDivider
        <table style='width:100%;border-collapse:collapse;border-radius:8px;overflow:hidden;'>
            <thead>
                <tr>
                    <th style='$tableHeaderStyle;width:40px;'>#</th>
                    <th style='$tableHeaderStyle'>Topic</th>
                    <th style='$tableHeaderStyle;text-align:center;'>Type</th>
                    <th style='$tableHeaderStyle;text-align:center;'>Difficulty</th>
                    <th style='$tableHeaderStyle;text-align:center;'>Points</th>
                </tr>
            </thead>
            <tbody>
$questionsRowsHtml
            </tbody>
        </table>
    </div>

    <!-- Launch Button -->
    <div style='$cardStyle;text-align:center;background:linear-gradient(135deg,#f0fdf4,#ecfdf5);border:1px solid #bbf7d0;'>
        <h2 style='$headingStyle;font-size:22px;margin-bottom:16px;'>🚀 Ready to Begin?</h2>
        <p style='$bodyTextStyle;margin-bottom:28px;'>Ensure you have reviewed all training materials before starting the assessment. Once started, the timer cannot be paused.</p>
        <a href='$appUrl' style='$buttonStyle;background:linear-gradient(135deg,$successGreen,#16a34a);box-shadow:0 4px 15px rgba(40,167,69,0.3);' target='_blank'>🎯 Launch Assessment</a>
    </div>

    <!-- Compliance Checklist -->
    $checklistHtml

</div>
"@

    return $html
}

# ---------------------------------------------------------------------------
# PAGE 5 — Field-Logs.aspx
# ---------------------------------------------------------------------------
function Build-FieldLogsHtml {
    [CmdletBinding()]
    param()

    $serviceRecordsUrl = $AssetUrls.ServiceRecordsListUrl

    # List web part fallback — embed link to the list if web part insertion fails
    $listWebPartHtml = @"
<div style='$cardStyle;border-left:4px solid $accentCyan;'>
    <h2 style='$headingStyle;font-size:22px;'>📊 Service Records</h2>
    $sectionDivider
    <p style='$bodyTextStyle;margin-bottom:16px;'>Access the Service Records list to view, add, and manage field service documentation.</p>

    <div style='background:#f0f9ff;border:1px solid #bae6fd;border-radius:10px;padding:20px;margin:16px 0;'>
        <h3 style='color:$accentDark;font-size:16px;font-weight:700;margin:0 0 10px 0;$fontStack'>📝 How to Add a New Record</h3>
        <ol style='margin:0;padding-left:24px;'>
            <li style='padding:6px 0;color:#444;font-size:14px;$fontStack'>Click the <strong>+ New</strong> button in the Service Records list</li>
            <li style='padding:6px 0;color:#444;font-size:14px;$fontStack'>Fill in all required fields (Date, Technician, Equipment, Description)</li>
            <li style='padding:6px 0;color:#444;font-size:14px;$fontStack'>Attach supporting photos or documents if applicable</li>
            <li style='padding:6px 0;color:#444;font-size:14px;$fontStack'>Set the status to <strong>Pending Review</strong></li>
            <li style='padding:6px 0;color:#444;font-size:14px;$fontStack'>Click <strong>Save</strong> to submit the record</li>
        </ol>
    </div>

    <div style='text-align:center;padding:20px 0;'>
        <a href='$serviceRecordsUrl' style='$buttonStyle;background:linear-gradient(135deg,$accentCyan,#0078d4);' target='_blank'>📂 Open Service Records List</a>
    </div>
</div>
"@

    $html = @"
<!-- FIELD LOGS PAGE — $moduleTitle -->
<div style='$cssReset'>

    <!-- Header -->
    <div style='background:linear-gradient(135deg,#f59e0b,#d97706);border-radius:16px;padding:48px;margin-bottom:28px;'>
        <div style='$badgeStyle;background:rgba(255,255,255,0.2);color:#ffffff;margin-bottom:14px;'>Field Documentation</div>
        <h1 style='color:#ffffff;font-size:32px;font-weight:800;margin:0 0 12px 0;$fontStack'>Field Logs &amp; Service Records</h1>
        <p style='color:rgba(255,255,255,0.85);font-size:16px;margin:0;$fontStack'>Document field activities, service calls, and maintenance records for $moduleTitle.</p>
    </div>

    <!-- Service Records Instructions -->
    <div style='$cardStyle'>
        <h2 style='$headingStyle;font-size:22px;'>📋 Service Record Instructions</h2>
        $sectionDivider
        <p style='$bodyTextStyle'>All field service activities must be documented in the SharePoint Service Records list. Accurate and timely documentation is critical for compliance, warranty tracking, and performance analysis.</p>

        <div style='display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:16px;margin:24px 0;'>
            <div style='background:#f8fafc;border-radius:10px;padding:20px;border:1px solid #e2e8f0;text-align:center;'>
                <div style='font-size:32px;margin-bottom:8px;'>⏱️</div>
                <div style='font-weight:700;color:$accentDark;font-size:14px;$fontStack'>Timeliness</div>
                <div style='color:#888;font-size:13px;margin-top:4px;$fontStack'>Submit within 24 hours of service</div>
            </div>
            <div style='background:#f8fafc;border-radius:10px;padding:20px;border:1px solid #e2e8f0;text-align:center;'>
                <div style='font-size:32px;margin-bottom:8px;'>📸</div>
                <div style='font-weight:700;color:$accentDark;font-size:14px;$fontStack'>Documentation</div>
                <div style='color:#888;font-size:13px;margin-top:4px;$fontStack'>Include photos of work performed</div>
            </div>
            <div style='background:#f8fafc;border-radius:10px;padding:20px;border:1px solid #e2e8f0;text-align:center;'>
                <div style='font-size:32px;margin-bottom:8px;'>✅</div>
                <div style='font-weight:700;color:$accentDark;font-size:14px;$fontStack'>Accuracy</div>
                <div style='color:#888;font-size:13px;margin-top:4px;$fontStack'>Double-check all entries before saving</div>
            </div>
        </div>
    </div>

    <!-- Service Records List / Web Part -->
    $listWebPartHtml

    <!-- List Web Part Fallback -->
    <div style='$cardStyle;background:#fffbeb;border:1px solid #fde68a;'>
        <h3 style='color:#92400e;font-size:16px;font-weight:700;margin:0 0 10px 0;$fontStack'>💡 Embedded List View</h3>
        <p style='color:#92400e;font-size:14px;margin:0 0 12px 0;$fontStack'>If the embedded list does not appear above, use the direct link below to access the Service Records list in a new tab.</p>
        <div style='background:#ffffff;border-radius:8px;padding:16px;border:1px solid #e5e7eb;'>
            <iframe src='$serviceRecordsUrl' style='width:100%;height:500px;border:none;border-radius:8px;' title='Service Records List'></iframe>
        </div>
        <div style='margin-top:12px;text-align:center;'>
            <a href='$serviceRecordsUrl' style='$linkStyle;font-size:14px;' target='_blank'>🔗 Open Service Records in Full Page</a>
        </div>
    </div>

    <!-- Field Documentation Guidance -->
    <div style='$cardStyle'>
        <h2 style='$headingStyle;font-size:22px;'>📖 Field Documentation Guidance</h2>
        $sectionDivider
        <div style='display:grid;grid-template-columns:1fr 1fr;gap:20px;margin-top:16px;'>
            <div style='background:#f0fdf4;border-radius:10px;padding:20px;border:1px solid #bbf7d0;'>
                <h3 style='color:#16a34a;font-size:16px;font-weight:700;margin:0 0 10px 0;$fontStack'>✅ Do</h3>
                <ul style='margin:0;padding-left:20px;'>
                    <li style='padding:4px 0;color:#444;font-size:13px;$fontStack'>Record exact equipment model and serial numbers</li>
                    <li style='padding:4px 0;color:#444;font-size:13px;$fontStack'>Document pre-service and post-service conditions</li>
                    <li style='padding:4px 0;color:#444;font-size:13px;$fontStack'>Note any deviations from standard procedures</li>
                    <li style='padding:4px 0;color:#444;font-size:13px;$fontStack'>Include customer sign-off when required</li>
                    <li style='padding:4px 0;color:#444;font-size:13px;$fontStack'>Attach relevant safety inspection forms</li>
                </ul>
            </div>
            <div style='background:#fef2f2;border-radius:10px;padding:20px;border:1px solid #fecaca;'>
                <h3 style='color:#dc2626;font-size:16px;font-weight:700;margin:0 0 10px 0;$fontStack'>❌ Don&apos;t</h3>
                <ul style='margin:0;padding-left:20px;'>
                    <li style='padding:4px 0;color:#444;font-size:13px;$fontStack'>Leave fields blank or use placeholder text</li>
                    <li style='padding:4px 0;color:#444;font-size:13px;$fontStack'>Backdate entries more than 48 hours</li>
                    <li style='padding:4px 0;color:#444;font-size:13px;$fontStack'>Omit safety incident details</li>
                    <li style='padding:4px 0;color:#444;font-size:13px;$fontStack'>Use abbreviations not in the approved glossary</li>
                    <li style='padding:4px 0;color:#444;font-size:13px;$fontStack'>Share records outside authorized channels</li>
                </ul>
            </div>
        </div>
    </div>

</div>
"@

    return $html
}

# ===========================================================================
# MAIN EXECUTION
# ===========================================================================

$createdPages = @()

Write-DeployLog -Message "========================================" -Level "Info"
Write-DeployLog -Message "SharePoint Page Builder — $moduleTitle" -Level "Info"
Write-DeployLog -Message "Site: $SiteUrl" -Level "Info"
Write-DeployLog -Message "========================================" -Level "Info"

# --- PAGE 1: Home ---
Write-DeployLog -Message "Building Page 1/5: Home.aspx..." -Level "Info"
$homeHtml = Build-HomePageHtml
New-TrainingPage -PageName "Home" -HtmlContent $homeHtml -Description "Training module home page"
$createdPages += "Home.aspx"

# --- PAGE 2: Procedure-Guide ---
Write-DeployLog -Message "Building Page 2/5: Procedure-Guide.aspx..." -Level "Info"
$procedureHtml = Build-ProcedureGuideHtml
New-TrainingPage -PageName "Procedure-Guide" -HtmlContent $procedureHtml -Description "Standard operating procedures guide"
$createdPages += "Procedure-Guide.aspx"

# --- PAGE 3: Media-Resources ---
Write-DeployLog -Message "Building Page 3/5: Media-Resources.aspx..." -Level "Info"
$mediaHtml = Build-MediaResourcesHtml
New-TrainingPage -PageName "Media-Resources" -HtmlContent $mediaHtml -Description "Multimedia learning resources"
$createdPages += "Media-Resources.aspx"

# --- PAGE 4: Assessment ---
Write-DeployLog -Message "Building Page 4/5: Assessment.aspx..." -Level "Info"
$assessmentHtml = Build-AssessmentHtml
New-TrainingPage -PageName "Assessment" -HtmlContent $assessmentHtml -Description "Knowledge assessment center"
$createdPages += "Assessment.aspx"

# --- PAGE 5: Field-Logs ---
Write-DeployLog -Message "Building Page 5/5: Field-Logs.aspx..." -Level "Info"
$fieldLogsHtml = Build-FieldLogsHtml
New-TrainingPage -PageName "Field-Logs" -HtmlContent $fieldLogsHtml -Description "Field logs and service records"
$createdPages += "Field-Logs.aspx"

# --- Summary ---
Write-DeployLog -Message "========================================" -Level "Success"
Write-DeployLog -Message "Page Creation Summary" -Level "Success"
Write-DeployLog -Message "========================================" -Level "Success"
Write-DeployLog -Message "Total Pages Created: $($createdPages.Count)" -Level "Success"
foreach ($pageName in $createdPages) {
    Write-DeployLog -Message "  ✅ $pageName" -Level "Success"
}
Write-DeployLog -Message "Site URL: $SiteUrl" -Level "Info"
Write-DeployLog -Message "All pages published successfully." -Level "Success"

return $createdPages
