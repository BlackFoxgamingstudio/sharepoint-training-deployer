<#
.SYNOPSIS
    Uploads training module assets to a SharePoint Online site.

.DESCRIPTION
    Asset upload engine that deploys training content (slides, video, interactive app)
    to the 'Training Assets' document library in SharePoint Online. Creates the required
    folder structure, uploads all files with progress tracking, provisions a 'Service Records'
    list with custom fields, and returns a hashtable of asset URLs.

    This script dot-sources Deploy-Helpers.ps1 for shared utilities including
    Write-DeployLog, Invoke-SafeOperation, Format-SharePointUrl, and Test-PnPConnection.

.PARAMETER SiteUrl
    The full URL of the target SharePoint Online site (e.g., https://contoso.sharepoint.com/sites/Training).

.PARAMETER ModuleName
    The name of the training module to upload (must correspond to a subfolder under ContentPath).

.PARAMETER ContentPath
    The root path to the content directory. Defaults to ../content relative to the script location.

.EXAMPLE
    .\03_Upload_Assets.ps1 -SiteUrl "https://contoso.sharepoint.com/sites/Training" -ModuleName "Module01"

.EXAMPLE
    .\03_Upload_Assets.ps1 -SiteUrl "https://contoso.sharepoint.com/sites/Training" -ModuleName "SafetyTraining" -ContentPath "C:\TrainingContent"

.NOTES
    Requires PnP.PowerShell module and Deploy-Helpers.ps1 utility script.
    Author: Sovereign Biz Box Automation
    Version: 1.0.0
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "SharePoint Online site URL")]
    [ValidateNotNullOrEmpty()]
    [string]$SiteUrl,

    [Parameter(Mandatory = $true, HelpMessage = "Training module name")]
    [ValidateNotNullOrEmpty()]
    [string]$ModuleName,

    [Parameter(Mandatory = $false, HelpMessage = "Path to content directory")]
    [string]$ContentPath
)

# ---------------------------------------------------------------------------
# Bootstrap: dot-source shared helpers
# ---------------------------------------------------------------------------
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$helpersPath = Join-Path $scriptDir "utils" "Deploy-Helpers.ps1"

if (-not (Test-Path $helpersPath)) {
    throw "Required helper script not found: $helpersPath"
}

. $helpersPath

# ---------------------------------------------------------------------------
# Execution timer
# ---------------------------------------------------------------------------
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# ---------------------------------------------------------------------------
# 1. Validate inputs
# ---------------------------------------------------------------------------
Write-DeployLog -Message "=== Asset Upload Engine Starting ===" -Level "Info"
Write-DeployLog -Message "Module: $ModuleName" -Level "Info"

# Format and validate the SharePoint URL
$SiteUrl = Format-SharePointUrl -Url $SiteUrl
Write-DeployLog -Message "Target site: $SiteUrl" -Level "Info"

# Resolve content path (default to ../content relative to script location)
if ([string]::IsNullOrWhiteSpace($ContentPath)) {
    $ContentPath = Join-Path (Split-Path -Parent $scriptDir) "content"
}

$ContentPath = Resolve-Path -Path $ContentPath -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Path

if (-not $ContentPath -or -not (Test-Path $ContentPath -PathType Container)) {
    $errorMsg = "Content path does not exist: $ContentPath"
    Write-DeployLog -Message $errorMsg -Level "Error"
    throw $errorMsg
}

Write-DeployLog -Message "Content path: $ContentPath" -Level "Info"

# Verify module subfolder exists
$modulePath = Join-Path $ContentPath $ModuleName
if (-not (Test-Path $modulePath -PathType Container)) {
    $errorMsg = "Module subfolder not found: $modulePath"
    Write-DeployLog -Message $errorMsg -Level "Error"
    throw $errorMsg
}

Write-DeployLog -Message "Module path verified: $modulePath" -Level "Info"

# ---------------------------------------------------------------------------
# 2. Connect to SharePoint Online
# ---------------------------------------------------------------------------
Invoke-SafeOperation -OperationName "Connect to SharePoint Online" -ScriptBlock {
    Write-DeployLog -Message "Connecting to SharePoint Online at $SiteUrl ..." -Level "Info"
    Connect-PnPOnline -Url $SiteUrl -Interactive

    if (-not (Test-PnPConnection)) {
        throw "SharePoint Online connection verification failed for $SiteUrl"
    }

    Write-DeployLog -Message "Successfully connected and verified SharePoint Online connection." -Level "Success"
}

# ---------------------------------------------------------------------------
# 3. Create folder structure in 'Training Assets' document library
# ---------------------------------------------------------------------------
$docLibrary = "Training Assets"
$slidesFolder = "$docLibrary/$ModuleName/slides"
$videoFolder  = "$docLibrary/$ModuleName/video"
$appFolder    = "$docLibrary/$ModuleName/app"

$foldersToCreate = @($slidesFolder, $videoFolder, $appFolder)

foreach ($folder in $foldersToCreate) {
    Invoke-SafeOperation -OperationName "Create folder: $folder" -ScriptBlock {
        Write-DeployLog -Message "Ensuring folder exists: $folder" -Level "Info"
        Resolve-PnPFolder -SiteRelativePath $folder
        Write-DeployLog -Message "Folder ready: $folder" -Level "Success"
    }
}

# ---------------------------------------------------------------------------
# Tracking variables
# ---------------------------------------------------------------------------
$totalFilesUploaded = 0
$totalBytesUploaded = [long]0
$slideUrls = [System.Collections.Generic.List[string]]::new()

# ---------------------------------------------------------------------------
# 4. Upload slides (*.png from interactive_app/assets/slides/)
# ---------------------------------------------------------------------------
$slidesSourcePath = Join-Path $modulePath "interactive_app" "assets" "slides"

Invoke-SafeOperation -OperationName "Upload slide images" -ScriptBlock {
    if (-not (Test-Path $slidesSourcePath -PathType Container)) {
        Write-DeployLog -Message "Slides source path not found, skipping: $slidesSourcePath" -Level "Warning"
        return
    }

    $slideFiles = Get-ChildItem -Path $slidesSourcePath -Filter "*.png" -File | Sort-Object Name
    $slideCount = $slideFiles.Count

    if ($slideCount -eq 0) {
        Write-DeployLog -Message "No PNG slide files found in: $slidesSourcePath" -Level "Warning"
        return
    }

    Write-DeployLog -Message "Found $slideCount slide(s) to upload." -Level "Info"
    $currentSlide = 0

    foreach ($slideFile in $slideFiles) {
        $currentSlide++
        $percentComplete = [math]::Round(($currentSlide / $slideCount) * 100, 0)

        Write-Progress -Activity "Uploading Slides" `
                       -Status "Uploading $($slideFile.Name) ($currentSlide of $slideCount)" `
                       -PercentComplete $percentComplete

        Write-DeployLog -Message "Uploading slide [$currentSlide/$slideCount]: $($slideFile.Name) ($([math]::Round($slideFile.Length / 1KB, 1)) KB)" -Level "Info"

        $uploadedFile = Add-PnPFile -Path $slideFile.FullName -Folder $slidesFolder
        $slideUrls.Add($uploadedFile.ServerRelativeUrl)

        $totalFilesUploaded++
        $totalBytesUploaded += $slideFile.Length
    }

    Write-Progress -Activity "Uploading Slides" -Completed
    Write-DeployLog -Message "All $slideCount slide(s) uploaded successfully." -Level "Success"
}

# ---------------------------------------------------------------------------
# 5. Upload video (procedure_video.mp4)
# ---------------------------------------------------------------------------
$videoSourcePath = Join-Path $modulePath "interactive_app" "assets" "procedure_video.mp4"

Invoke-SafeOperation -OperationName "Upload procedure video" -ScriptBlock {
    if (-not (Test-Path $videoSourcePath -PathType Leaf)) {
        Write-DeployLog -Message "Video file not found, skipping: $videoSourcePath" -Level "Warning"
        return
    }

    $videoFile = Get-Item -Path $videoSourcePath
    $videoSizeMB = [math]::Round($videoFile.Length / 1MB, 2)

    Write-DeployLog -Message "Uploading video: $($videoFile.Name) (Size: $videoSizeMB MB)" -Level "Info"

    $uploadedVideo = Add-PnPFile -Path $videoFile.FullName -Folder $videoFolder

    $totalFilesUploaded++
    $totalBytesUploaded += $videoFile.Length

    Write-DeployLog -Message "Video uploaded successfully: $($uploadedVideo.ServerRelativeUrl) ($videoSizeMB MB)" -Level "Success"
}

# ---------------------------------------------------------------------------
# 6. Upload interactive app (recursive, preserve directory structure)
# ---------------------------------------------------------------------------
$appSourcePath = Join-Path $modulePath "interactive_app"

Invoke-SafeOperation -OperationName "Upload interactive app files" -ScriptBlock {
    if (-not (Test-Path $appSourcePath -PathType Container)) {
        Write-DeployLog -Message "Interactive app source path not found, skipping: $appSourcePath" -Level "Warning"
        return
    }

    $appFiles = Get-ChildItem -Path $appSourcePath -File -Recurse
    $appFileCount = $appFiles.Count

    if ($appFileCount -eq 0) {
        Write-DeployLog -Message "No files found in interactive app directory: $appSourcePath" -Level "Warning"
        return
    }

    Write-DeployLog -Message "Found $appFileCount file(s) in interactive app to upload." -Level "Info"
    $currentAppFile = 0

    foreach ($file in $appFiles) {
        $currentAppFile++
        $percentComplete = [math]::Round(($currentAppFile / $appFileCount) * 100, 0)

        Write-Progress -Activity "Uploading Interactive App" `
                       -Status "Uploading $($file.Name) ($currentAppFile of $appFileCount)" `
                       -PercentComplete $percentComplete

        # Compute relative path from the interactive_app root to preserve structure
        $relativePath = $file.FullName.Substring($appSourcePath.Length).TrimStart([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
        $relativeDir = Split-Path -Parent $relativePath

        # Build the target folder path in SharePoint
        if ([string]::IsNullOrWhiteSpace($relativeDir)) {
            $targetFolder = $appFolder
        } else {
            # Normalize path separators to forward slashes for SharePoint
            $normalizedRelativeDir = $relativeDir -replace '\\', '/'
            $targetFolder = "$appFolder/$normalizedRelativeDir"
        }

        # Ensure the target folder exists
        Resolve-PnPFolder -SiteRelativePath $targetFolder | Out-Null

        Write-DeployLog -Message "Uploading app file [$currentAppFile/$appFileCount]: $relativePath ($([math]::Round($file.Length / 1KB, 1)) KB)" -Level "Info"

        Add-PnPFile -Path $file.FullName -Folder $targetFolder | Out-Null

        $totalFilesUploaded++
        $totalBytesUploaded += $file.Length
    }

    Write-Progress -Activity "Uploading Interactive App" -Completed
    Write-DeployLog -Message "All $appFileCount interactive app file(s) uploaded successfully." -Level "Success"
}

# ---------------------------------------------------------------------------
# 7. Create 'Service Records' list with custom fields
# ---------------------------------------------------------------------------
$serviceRecordsListTitle = "Service Records"

Invoke-SafeOperation -OperationName "Provision Service Records list" -ScriptBlock {
    # Check if the list already exists
    $existingList = $null
    try {
        $existingList = Get-PnPList -Identity $serviceRecordsListTitle -ErrorAction SilentlyContinue
    } catch {
        # List does not exist — expected path
    }

    if ($null -ne $existingList) {
        Write-DeployLog -Message "List '$serviceRecordsListTitle' already exists. Skipping creation." -Level "Warning"
        return
    }

    Write-DeployLog -Message "Creating list: $serviceRecordsListTitle" -Level "Info"

    New-PnPList -Title $serviceRecordsListTitle -Template GenericList | Out-Null
    Write-DeployLog -Message "List '$serviceRecordsListTitle' created." -Level "Success"

    # Add custom fields
    Write-DeployLog -Message "Adding custom fields to '$serviceRecordsListTitle' ..." -Level "Info"

    # TechnicianName (Text, required)
    Add-PnPField -List $serviceRecordsListTitle `
                 -DisplayName "TechnicianName" `
                 -InternalName "TechnicianName" `
                 -Type Text `
                 -Required | Out-Null
    Write-DeployLog -Message "  Added field: TechnicianName (Text, Required)" -Level "Info"

    # Date (DateTime, required)
    Add-PnPField -List $serviceRecordsListTitle `
                 -DisplayName "Date" `
                 -InternalName "ServiceDate" `
                 -Type DateTime `
                 -Required | Out-Null
    Write-DeployLog -Message "  Added field: Date (DateTime, Required)" -Level "Info"

    # Location (Text, required)
    Add-PnPField -List $serviceRecordsListTitle `
                 -DisplayName "Location" `
                 -InternalName "Location" `
                 -Type Text `
                 -Required | Out-Null
    Write-DeployLog -Message "  Added field: Location (Text, Required)" -Level "Info"

    # CartridgeType (Text, optional)
    Add-PnPField -List $serviceRecordsListTitle `
                 -DisplayName "CartridgeType" `
                 -InternalName "CartridgeType" `
                 -Type Text | Out-Null
    Write-DeployLog -Message "  Added field: CartridgeType (Text)" -Level "Info"

    # PressureReading (Number, optional)
    Add-PnPField -List $serviceRecordsListTitle `
                 -DisplayName "PressureReading" `
                 -InternalName "PressureReading" `
                 -Type Number | Out-Null
    Write-DeployLog -Message "  Added field: PressureReading (Number)" -Level "Info"

    # Notes (Note / multiline, optional)
    Add-PnPField -List $serviceRecordsListTitle `
                 -DisplayName "Notes" `
                 -InternalName "ServiceNotes" `
                 -Type Note | Out-Null
    Write-DeployLog -Message "  Added field: Notes (Note/Multiline)" -Level "Info"

    # Status (Choice: Pass/Fail/Pending, default Pending)
    $statusFieldXml = @"
<Field Type="Choice" DisplayName="Status" Required="FALSE" Format="Dropdown" FillInChoice="FALSE" StaticName="ServiceStatus" Name="ServiceStatus">
    <Default>Pending</Default>
    <CHOICES>
        <CHOICE>Pass</CHOICE>
        <CHOICE>Fail</CHOICE>
        <CHOICE>Pending</CHOICE>
    </CHOICES>
</Field>
"@
    Add-PnPFieldFromXml -List $serviceRecordsListTitle -FieldXml $statusFieldXml | Out-Null
    Write-DeployLog -Message "  Added field: Status (Choice: Pass/Fail/Pending, Default: Pending)" -Level "Info"

    Write-DeployLog -Message "All custom fields added to '$serviceRecordsListTitle'." -Level "Success"
}

# ---------------------------------------------------------------------------
# 8. Build and return asset URLs hashtable
# ---------------------------------------------------------------------------
$stopwatch.Stop()
$elapsedTime = $stopwatch.Elapsed

# Construct URLs
$siteUri = [System.Uri]$SiteUrl
$basePath = $siteUri.AbsolutePath.TrimEnd('/')

$assetUrls = @{
    SlidesFolder       = "$basePath/$slidesFolder" -replace ' ', '%20'
    VideoUrl           = "$basePath/$videoFolder/procedure_video.mp4" -replace ' ', '%20'
    AppUrl             = "$basePath/$appFolder/index.html" -replace ' ', '%20'
    AppFolder          = "$basePath/$appFolder" -replace ' ', '%20'
    ServiceRecordsListUrl = "$basePath/Lists/$($serviceRecordsListTitle -replace ' ', '%20')"
    SlideUrls          = $slideUrls.ToArray()
}

# ---------------------------------------------------------------------------
# 9. Log summary
# ---------------------------------------------------------------------------
$totalSizeMB = [math]::Round($totalBytesUploaded / 1MB, 2)
$formattedElapsed = "{0:hh\:mm\:ss\.ff}" -f $elapsedTime

Write-DeployLog -Message "=== Asset Upload Complete ===" -Level "Success"
Write-DeployLog -Message "  Module:        $ModuleName" -Level "Info"
Write-DeployLog -Message "  Total files:   $totalFilesUploaded" -Level "Info"
Write-DeployLog -Message "  Total size:    $totalSizeMB MB ($totalBytesUploaded bytes)" -Level "Info"
Write-DeployLog -Message "  Elapsed time:  $formattedElapsed" -Level "Info"
Write-DeployLog -Message "  Slides folder: $($assetUrls.SlidesFolder)" -Level "Info"
Write-DeployLog -Message "  Video URL:     $($assetUrls.VideoUrl)" -Level "Info"
Write-DeployLog -Message "  App URL:       $($assetUrls.AppUrl)" -Level "Info"
Write-DeployLog -Message "  App folder:    $($assetUrls.AppFolder)" -Level "Info"
Write-DeployLog -Message "  Service list:  $($assetUrls.ServiceRecordsListUrl)" -Level "Info"
Write-DeployLog -Message "  Slide count:   $($assetUrls.SlideUrls.Count)" -Level "Info"
Write-DeployLog -Message "================================" -Level "Success"

# Return the asset URLs hashtable to the caller
return $assetUrls
