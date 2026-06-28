# Troubleshooting Guide

**SharePoint Training Site Deployer v1.0.0** | June 2026 | SBB Training Engineering

---

## Quick Diagnostics

Before diving into specific errors, run the prerequisites checker to identify most common issues:

```powershell
.\scripts\00_Prerequisites.ps1
```

This validates your PowerShell version, PnP module, connectivity, and permissions in one pass.

---

## Common Errors & Solutions

### 1. PnP.PowerShell Module Issues

| Error | Cause | Solution |
|:------|:------|:---------|
| `The term 'Connect-PnPOnline' is not recognized` | PnP.PowerShell module not installed | Run `Install-Module PnP.PowerShell -Scope CurrentUser -Force` in PowerShell 7+ |
| `Module PnP.PowerShell requires PowerShell 7.2+` | Running in Windows PowerShell 5.1 instead of PowerShell 7 | Install PowerShell 7: `winget install Microsoft.PowerShell` then launch `pwsh.exe` |
| `Could not load type 'PnP.Framework...'` | Module version conflict or corruption | Run `Uninstall-Module PnP.PowerShell -AllVersions` then reinstall with `Install-Module PnP.PowerShell -Scope CurrentUser -Force` |
| `WARNING: A newer version of PnP.PowerShell is available` | Outdated module version | Run `Update-Module PnP.PowerShell -Force` |

> [!TIP]
> Always use PowerShell 7+ (`pwsh.exe`), NOT Windows PowerShell 5.1 (`powershell.exe`). PnP.PowerShell dropped support for PS 5.1 in 2024.

---

### 2. Authentication & Connection Errors

| Error | Cause | Solution |
|:------|:------|:---------|
| `Connect-PnPOnline: AADSTS50011: The redirect URI specified in the request does not match` | PnP app registration mismatch | Use `-Interactive` flag: `Connect-PnPOnline -Url $url -Interactive` |
| `Connect-PnPOnline: AADSTS65001: The user or administrator has not consented` | Tenant admin has not approved PnP app | Ask your IT admin to grant consent to the PnP Management Shell in Entra ID → Enterprise Applications |
| `Access denied. You do not have permission` | Insufficient permissions on the target site | Request Site Collection Administrator role from your SharePoint admin |
| `403 Forbidden` when creating site | Account lacks site creation rights | Contact tenant admin to enable self-service site creation, or ask them to create the site for you |
| `The remote server returned an error: (401) Unauthorized` | Authentication token expired or invalid | Disconnect (`Disconnect-PnPOnline`) and reconnect. Clear browser cache if using Interactive auth |
| MFA prompt loops indefinitely | Browser caching stale MFA session | Clear browser cookies for `login.microsoftonline.com`, then retry |

> [!IMPORTANT]
> **Interactive authentication** opens a browser window for login. If your organization enforces Conditional Access policies, ensure you are on a compliant device and network.

---

### 3. Site Creation Errors

| Error | Cause | Solution |
|:------|:------|:---------|
| `A site with the URL already exists` | Site URL is taken | Use a different `-SiteUrlSuffix` parameter, or connect to the existing site with the `-UseExisting` flag |
| `New-PnPSite: The managed path sites is not a managed path` | Tenant uses a non-standard managed path | Check your tenant's managed paths in SharePoint Admin Center → Settings → Site Creation |
| `Site creation failed: Tenant does not allow Communication Site creation` | Self-service site creation is disabled | Ask your SharePoint admin to enable it in Admin Center → Settings → Site Creation |
| Site creates but pages are empty | Template application failed silently | Check the deployment log in `logs/`. Re-run `02_Create_SharePoint_Pages.ps1` independently |

---

### 4. File Upload Errors

| Error | Cause | Solution |
|:------|:------|:---------|
| `Add-PnPFile: The file is too large for the destination` | File exceeds SharePoint size limit | SharePoint Online supports up to 250GB per file. Check network stability for large uploads |
| `Add-PnPFile: Access denied` | No write permissions to Document Library | Verify you have Contribute or Full Control on the target library |
| `Upload failed: The underlying connection was closed` | Network timeout on large files | Retry the upload. For files >100MB, ensure stable network. The script uses chunked upload automatically |
| `Add-PnPFile: File not found at path` | Local file path is incorrect | Verify the content folder structure matches: `content/[module]/interactive_app/assets/` |
| `Folder 'Training Assets' does not exist` | Document library not created | Run `03_Upload_Assets.ps1` which creates the folder structure automatically |
| Slides upload stalls at a specific percentage | Network interruption mid-upload | Re-run the upload script. It will skip already-uploaded files and continue |

> [!TIP]
> The total asset size for a typical training module is ~60–80MB (18 slides at ~3MB each + 5MB video). On a standard broadband connection, uploads complete in 2–5 minutes.

---

### 5. Page Creation Errors

| Error | Cause | Solution |
|:------|:------|:---------|
| `Add-PnPPage: A page with the name 'Home.aspx' already exists` | Pages from a previous deployment still exist | Delete the old pages first, or use the `-Force` parameter to overwrite |
| `Add-PnPPageTextPart: Section 1 does not exist` | Section was not created before adding content | Ensure `Add-PnPPageSection` runs before `Add-PnPPageTextPart`. Check script execution order |
| `Add-PnPPageWebPart: The web part type is not supported` | Invalid web part type name | Verify the web part type string matches PnP's supported types (e.g., `ContentEmbed`, `Image`, `List`) |
| Page appears blank after creation | Web parts added but page not published | Run `Set-PnPPage -Identity "Home.aspx" -Publish` or check that `Publish-PnPPage` was called |
| Images don't render on the page | Image URLs point to non-existent files | Verify the asset upload completed successfully. Check URLs in the deployment log |

---

### 6. Embed Web Part & HTML Field Security

| Error | Cause | Solution |
|:------|:------|:---------|
| `Embedding content from this website isn't allowed` | Domain not whitelisted in HTML Field Security | Go to **Site Settings → HTML Field Security** and add your SharePoint domain |
| Interactive app loads but JavaScript is blocked | SharePoint blocks inline scripts in Embed web parts | This is expected. The interactive app is designed to run as a standalone linked page, not inline. Use the "Launch Interactive App" link |
| Embed web part shows blank white area | iframe source URL is incorrect | Verify the app URL in the Embed web part properties matches the uploaded file location |

> [!WARNING]
> SharePoint Online blocks arbitrary JavaScript execution inside modern pages for security. The interactive HTML training app (with simulator, quiz, certificate) is designed to open in a new browser tab via a direct link, not render inline. This is by design and is the industry-standard approach.

---

### 7. Branding & Theme Errors

| Error | Cause | Solution |
|:------|:------|:---------|
| `Set-PnPWebTheme: Theme not found` | Custom theme not registered on the tenant | The script registers the theme automatically. If it fails, manually register with `Add-PnPTenantTheme` |
| Theme applies but colors look wrong | Browser caching old stylesheet | Hard refresh the page (Ctrl+Shift+R) or clear browser cache |
| Site logo doesn't appear | Logo file upload failed or path is wrong | Verify the favicon/logo was uploaded to Site Assets. Re-run `04_Apply_Branding.ps1` |
| Navigation links don't work | Page names have changed or pages were deleted | Re-run `04_Apply_Branding.ps1` to rebuild navigation |

---

### 8. Batch Deployment Errors

| Error | Cause | Solution |
|:------|:------|:---------|
| `Import-Csv: Cannot find path 'training_modules.csv'` | CSV file missing or wrong path | Verify `config/training_modules.csv` exists and has the correct headers |
| Batch stops after first failure | `-ContinueOnError` not specified | Re-run with: `.\05_Batch_Deploy.ps1 -ContinueOnError` |
| Some modules deployed, others failed | Mixed permissions or content issues | Check `logs/batch_report_*.html` for per-module status. Fix failed modules and re-run |
| `Rate limit exceeded` or `429 Too Many Requests` | Too many API calls in rapid succession | Add a delay between modules. The batch script includes a configurable `-DelayBetweenModules` parameter (default: 10 seconds) |

---

## Debugging Steps

### Step 1: Check the Deployment Log

Every script writes detailed logs to the `logs/` directory with timestamps:

```powershell
# View the most recent log
Get-ChildItem .\logs\ -Filter "*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1 | Get-Content
```

### Step 2: Verify PnP Connection

```powershell
# Check if you're connected
Get-PnPConnection

# Check your permission level
Get-PnPWeb -Includes EffectiveBasePermissions
```

### Step 3: Test Individual Scripts

If the master orchestrator fails, run each script independently to isolate the issue:

```powershell
# Step 1: Prerequisites
.\scripts\00_Prerequisites.ps1

# Step 2: Upload assets only
.\scripts\03_Upload_Assets.ps1 -SiteUrl "https://tenant.sharepoint.com/sites/training-test" -ModuleName "scalestick_sop" -ContentPath ".\content\scalestick_sop"

# Step 3: Create pages only
.\scripts\02_Create_SharePoint_Pages.ps1 -SiteUrl "https://tenant.sharepoint.com/sites/training-test" -ModuleName "scalestick_sop"

# Step 4: Apply branding only
.\scripts\04_Apply_Branding.ps1 -SiteUrl "https://tenant.sharepoint.com/sites/training-test" -ModuleName "scalestick_sop"
```

### Step 4: Enable Verbose Output

All scripts support the `-Verbose` flag for detailed execution tracing:

```powershell
.\scripts\01_Deploy_Training_Site.ps1 -ModuleName "scalestick_sop" -Verbose
```

### Step 5: Dry Run

Test without making any changes:

```powershell
.\scripts\05_Batch_Deploy.ps1 -DryRun
```

---

## Collecting Logs for Support

If you need to escalate an issue, collect the following:

1. **Deployment log**: `logs/deploy_[module]_[timestamp].log`
2. **Batch report** (if applicable): `logs/batch_report_[timestamp].html`
3. **PowerShell version**: Output of `$PSVersionTable`
4. **PnP module version**: Output of `Get-Module PnP.PowerShell -ListAvailable`
5. **Error details**: Full error message including stack trace

Bundle these into a ZIP:

```powershell
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
Compress-Archive -Path ".\logs\*" -DestinationPath ".\support_bundle_$timestamp.zip"
```

---

## Environment Compatibility Matrix

| Component | Minimum Version | Recommended Version | Notes |
|:----------|:---------------|:-------------------|:------|
| Windows | 10 (21H2) | 11 (23H2+) | Windows 11 recommended |
| PowerShell | 7.2 | 7.4+ | Use `pwsh.exe`, not `powershell.exe` |
| PnP.PowerShell | 2.4.0 | Latest | Run `Update-Module` regularly |
| SharePoint Online | N/A | Current | Modern experience must be enabled |
| .NET Runtime | 6.0 | 8.0+ | Required by PnP.PowerShell |
| Browser (for Interactive auth) | Edge/Chrome | Latest | Required for `-Interactive` login |

---

## Known Limitations

1. **SharePoint Site Scripts** cannot create modern pages — the PnP scripts handle page creation separately
2. **Embed Web Part** cannot execute inline JavaScript — the interactive app opens in a new tab
3. **People/Group columns** may not transfer between site collections — user IDs differ per site
4. **Custom themes** require tenant-level permissions to register — site-level admins can apply pre-registered themes
5. **Rate limiting** may occur during batch deployments of 50+ modules — use the delay parameter

---

> [!NOTE]
> For issues not covered here, consult the [PnP PowerShell documentation](https://pnp.github.io/powershell/) or open an issue in your organization's IT service portal. Include the support bundle when reporting issues.
