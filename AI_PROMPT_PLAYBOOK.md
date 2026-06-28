# AI Training Site Factory — Prompt Playbook

> **Purpose:** Step-by-step AI prompts to recreate this entire system for any new training module.
> Copy-paste these prompts into your AI coding assistant to generate a new training site from raw materials (PowerPoint + Video) in under 30 minutes.

---

## Overview: The 6-Phase Factory Process

```
Phase 1: Content Extraction     → Convert PowerPoint to slide images + extract text
Phase 2: HTML Training Site     → Generate the interactive glassmorphic training app
Phase 3: SharePoint Package     → Configure module for SharePoint deployment
Phase 4: Deploy to SharePoint   → Run PowerShell automation
Phase 5: Quality Verification   → Test all components
Phase 6: Registry Update        → Add to batch manifest for tracking
```

---

## Phase 1: Content Extraction

### Prompt 1.1 — Extract Slides from PowerPoint

```
I have a PowerPoint file for a new training SOP: [ATTACH YOUR .PPTX FILE]

Extract every slide as a high-resolution PNG image (1920x1080 minimum).
Save them as slide_01.png through slide_XX.png in a folder called "slides/".
Also extract all text content from every slide into a structured JSON file
called "slide_content.json" with this format:

{
  "slides": [
    {
      "number": 1,
      "title": "Slide title text",
      "body": "All body text from the slide",
      "notes": "Speaker notes if any"
    }
  ]
}
```

### Prompt 1.2 — Download Training Video

```
Download this training video and save it as procedure_video.mp4:
[PASTE YOUR YOUTUBE OR VIDEO URL]

If the video is private or unavailable, let me know so I can make it accessible.
Save it at the highest available quality (1080p preferred).
```

---

## Phase 2: HTML Training Site Generation

### Prompt 2.1 — Generate the Interactive Training Site

```
Create a complete, single-file interactive training website for this SOP.
Use the attached slide images and the following training content:

**SOP Title:** [YOUR TITLE - e.g., "SS-10 ScaleStick™ Maintenance SOP"]
**Category:** [YOUR CATEGORY - e.g., "Water Treatment — Maintenance"]
**Description:** [2-3 SENTENCE DESCRIPTION OF THE PROCEDURE]

**Safety Hazards:**
- [LIST EACH HAZARD]

**Required Tools:**
- [LIST EACH TOOL/MATERIAL]

**Procedure Phases:**
Phase 1: [TITLE]
  Steps: [LIST STEPS]
Phase 2: [TITLE]
  Steps: [LIST STEPS]
Phase 3: [TITLE]
  Steps: [LIST STEPS]
Phase 4: [TITLE]
  Steps: [LIST STEPS]

**Quiz Questions (5 minimum, all must be answered correctly to pass):**
Q1: [QUESTION]
  a) [OPTION] b) [OPTION] c) [OPTION] d) [OPTION]
  Correct: [LETTER]
  Explanation: [WHY]
[REPEAT FOR ALL QUESTIONS]

DESIGN REQUIREMENTS (MANDATORY — DO NOT SIMPLIFY):
1. Dark glassmorphic theme (backdrop-filter: blur, translucent panels)
2. Color palette: deep navy (#030712) background, cyan (#00f0ff) accents
3. Font: Google Fonts "Outfit" for body, "JetBrains Mono" for code/data
4. Animated scroll progress bar at the top
5. Floating particle background animation
6. Smooth scroll-reveal animations on all sections
7. Interactive procedure simulator with step-by-step progression
8. Pressure gauge / system status indicator (animated SVG)
9. Slide carousel with click-to-fullscreen on each slide image
10. Embedded video player with fullscreen toggle
11. 5-question multiple-choice quiz with:
    - Immediate per-question feedback (correct/incorrect with explanation)
    - 100% pass requirement
    - Score tracking
    - Printable completion certificate with name, date, score, and unique certificate ID
12. Field verification log form with localStorage persistence
13. Print-optimized CSS (@media print) for the certificate
14. Mobile responsive design
15. Single HTML file with all CSS and JS inline (no external dependencies except Google Fonts)
16. Every section must have a unique ID for anchor navigation
17. Sticky navigation bar with smooth-scroll links to each section

The output must be a SINGLE index.html file. Do NOT simplify the design.
The site must look premium and state-of-the-art at first glance.
```

### Prompt 2.2 — Fix and Polish

```
Review the generated training site. Verify:
1. All slide images load correctly and click-to-fullscreen works
2. The video player works and has fullscreen toggle
3. The quiz scores correctly and generates a printable certificate
4. The procedure simulator advances through all steps
5. The field log saves to localStorage
6. All animations are smooth (no jank)
7. Mobile responsive layout works on phone-width screens
8. Print CSS generates a clean, professional certificate

Fix any issues found. Do NOT simplify the design during fixes.
```

---

## Phase 3: SharePoint Package Configuration

### Prompt 3.1 — Create Module Config

```
I have a completed training site for: [YOUR SOP TITLE]

Create a module_config.json file for the SharePoint Training Deployer system.
Use this template structure and fill in ALL fields with the actual content
from my training module:

- moduleName: [lowercase_with_underscores]
- siteSettings: title, description, siteUrlSuffix, category
- content: executiveSummary, safetyHazards[], requiredTools[], procedures (4 phases with steps)
- quizQuestions: 5 questions with options, correctIndex, explanation
- assets: paths to interactiveApp, slidesDirectory, slideCount, videoFile

Reference the existing scalestick_sop module_config.json as the template.
The config file lives at: content/[module_name]/module_config.json
```

### Prompt 3.2 — Set Up Content Folder

```
Set up the content folder for my new training module: [MODULE_NAME]

Create this structure:
content/[MODULE_NAME]/
  ├── module_config.json (already created)
  ├── interactive_app/
  │   ├── index.html (my training site)
  │   └── assets/
  │       ├── slides/slide_01.png through slide_XX.png
  │       ├── procedure_video.mp4
  │       └── favicon.svg
  └── content_pages/
      └── (optional markdown content files)

Copy my training site files into this structure.
```

---

## Phase 4: Deploy to SharePoint

### Prompt 4.1 — First-Time Setup (Run Once Per Organization)

```
I'm setting up the SharePoint Training Deployer for the first time at my organization.

My SharePoint tenant URL is: https://[TENANT].sharepoint.com

Help me:
1. Edit config/deployment_config.json with my tenant URL
2. Run scripts/00_Prerequisites.ps1 to validate my environment
3. Fix any issues the prerequisites check finds
4. Test connectivity to my SharePoint tenant
```

### Prompt 4.2 — Deploy a Training Module

```
Deploy my training module "[MODULE_NAME]" to SharePoint.

Run: .\scripts\01_Deploy_Training_Site.ps1 -ModuleName "[MODULE_NAME]"

If any errors occur, diagnose and fix them using the troubleshooting guide
at docs/TROUBLESHOOTING.md.

After successful deployment, verify:
1. All 5 SharePoint pages are created and published
2. All slides are visible in the Media & Resources page
3. The video plays in the embedded player
4. The "Launch Interactive Training App" link opens the full HTML app
5. The Service Records list is created with all columns
```

---

## Phase 5: Quality Verification

### Prompt 5.1 — Full QA Checklist

```
Run a complete quality assurance check on the deployed training site at:
https://[TENANT].sharepoint.com/sites/[SITE_URL]

Verify ALL of the following:

SHAREPOINT NATIVE PAGES:
☐ Home page loads with hero image and executive summary
☐ Procedure Guide has all 4 phases with complete step text
☐ Media page shows slide thumbnails and embedded video
☐ Assessment page has quiz instructions and compliance checklist
☐ Field Logs page shows the Service Records list
☐ Navigation bar links work for all 5 pages
☐ Site branding (theme, logo) is applied correctly

INTERACTIVE HTML APP:
☐ "Launch Interactive Training App" link opens the full app
☐ Glassmorphic design renders correctly (dark theme, blur effects, animations)
☐ All slide images load in the carousel
☐ Click-to-fullscreen works on slides
☐ Video player plays and fullscreen works
☐ Procedure simulator advances through all steps
☐ Quiz scores correctly (all 5 questions)
☐ Quiz requires 100% to pass
☐ Certificate generates with correct name and date
☐ Certificate prints cleanly
☐ Field log form saves data

Report any failures with the specific element and error description.
```

---

## Phase 6: Registry & Batch Management

### Prompt 6.1 — Add to Batch Manifest

```
Add my new training module to the batch deployment manifest.

Append this row to config/training_modules.csv:
[MODULE_NAME],[SITE_URL_SUFFIX],[TITLE],[DESCRIPTION],[CONTENT_FOLDER],[VIDEO_SOURCE],[OWNER],[CATEGORY],[PRIORITY]

Then commit the change to git.
```

### Prompt 6.2 — Batch Deploy All Modules

```
Deploy all training modules listed in config/training_modules.csv to SharePoint.

Run: .\scripts\05_Batch_Deploy.ps1 -ContinueOnError

Monitor the deployment and report:
- Total modules attempted
- Successful deployments
- Failed deployments with error details
- The HTML deployment report location
```

---

## Annual Planning: 100 Modules Per Year

### Scaling Strategy

| Quarter | Modules | Focus |
|:--------|:--------|:------|
| Q1 (Jan–Mar) | 25 | Core safety & compliance SOPs |
| Q2 (Apr–Jun) | 25 | Equipment maintenance procedures |
| Q3 (Jul–Sep) | 25 | Operational processes & workflows |
| Q4 (Oct–Dec) | 25 | Specialized/advanced training |

### Weekly Cadence (2 modules/week)

```
Monday:    Receive PowerPoint + Video from SME
Tuesday:   Phase 1 (Extract content) + Phase 2 (Generate HTML site)
Wednesday: Phase 3 (Configure module) + Phase 4 (Deploy to SharePoint)
Thursday:  Phase 5 (QA verification) + Phase 6 (Registry update)
Friday:    Buffer/fixes + next module prep
```

### Per-Module Time Budget

| Phase | Time | AI-Assisted? |
|:------|:-----|:-------------|
| Content Extraction | 10 min | ✅ Fully automated |
| HTML Site Generation | 15 min | ✅ AI generates, human reviews |
| SharePoint Configuration | 5 min | ✅ Template-based |
| SharePoint Deployment | 5 min | ✅ Fully automated |
| Quality Verification | 15 min | 🔶 Human reviews with AI checklist |
| Registry Update | 2 min | ✅ Fully automated |
| **Total per module** | **~52 min** | |

### Annual Metrics

- **100 modules × 52 min = ~87 hours of production time**
- **That's ~2 hours/week sustained over 50 weeks**
- **Each module serves unlimited employees once deployed**

---

## Quick Reference: AI Prompt Chain for New Module

For maximum speed, run these prompts in sequence:

```
1. "Extract slides from this PowerPoint as PNGs and text JSON" [attach .pptx]
2. "Download this video as MP4" [paste URL]
3. "Create an interactive glassmorphic training site with these slides, video, and content: [paste details]"
4. "Create module_config.json for [module_name] using the scalestick_sop template"
5. "Set up the content folder and deploy to SharePoint: [module_name]"
6. "Run QA verification on the deployed site"
7. "Add [module_name] to training_modules.csv and commit"
```

**Total prompts: 7 | Total time: ~52 minutes | Result: Complete SharePoint training site**
