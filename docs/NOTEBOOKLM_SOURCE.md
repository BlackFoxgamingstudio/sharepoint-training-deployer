# NotebookLM Source Document: SharePoint Training Site Deployer — Complete Technical & Operational Briefing

**Source Repository**: https://github.com/BlackFoxgamingstudio/sharepoint-training-deployer
**Version**: 1.0.0 | **Date**: June 2026 | **Author**: SBB Training Engineering

---

## SECTION 1: PROJECT OVERVIEW AND STRATEGIC PURPOSE

### 1.1 The Problem This System Solves

Enterprise organizations face a critical training delivery gap. Subject Matter Experts (SMEs) create PowerPoint presentations and demonstration videos to teach standard operating procedures (SOPs), but these passive materials fail to ensure knowledge retention or compliance verification. Employees click through slides without absorbing content. There is no interactive simulation to practice the procedure. There is no graded assessment to verify comprehension. There is no printable certificate to document compliance. And there is no automated system to deploy these training materials at scale across an organization's Microsoft SharePoint infrastructure.

The SharePoint Training Site Deployer solves all of these problems with a single, integrated automation platform. It takes raw training inputs — a PowerPoint slide deck and a procedure demonstration video — and transforms them into a fully deployed, interactive SharePoint Online training site in under 60 minutes. The system is designed to scale to 100 or more training modules per year with identical quality, consistent branding, and zero manual SharePoint page building.

### 1.2 Who This System Is For

This platform serves three distinct audiences within an enterprise organization:

1. **Training Engineers and Program Managers**: The primary operators who prepare training content, run the deployment scripts, and manage the training module library. They use the AI Prompt Playbook to generate new modules efficiently.

2. **IT Administrators and SharePoint Tenant Admins**: The technical gatekeepers who configure SharePoint permissions, manage Entra ID app registrations, whitelist domains for HTML embedding, and approve site creation policies. They use the Admin Guide and Troubleshooting documentation.

3. **End Users (Employees and Field Technicians)**: The trainees who access the deployed SharePoint sites, interact with the training simulations, take assessment quizzes, earn completion certificates, and log field service records.

### 1.3 The Complete GitHub Repository

The project is hosted as a public repository at https://github.com/BlackFoxgamingstudio/sharepoint-training-deployer. It contains 47 files totaling over 12,200 lines of production code and documentation. The repository includes seven PowerShell deployment scripts, eight JSON configuration and template files, seven markdown documentation files (including the README, Quickstart Guide, Admin Guide, Trainer Guide, Troubleshooting Reference, AI Scale Blueprint, and AI Prompt Playbook), one CSV batch deployment manifest, and one complete reference training module with an interactive HTML application, 18 slide images, and a procedure video.

The repository also serves as a live demonstration site via GitHub Pages. The root `index.html` file is the complete interactive training application for the ScaleStick SOP, accessible at https://blackfoxgamingstudio.github.io/sharepoint-training-deployer/.

---

## SECTION 2: THE TWO-TIER ARCHITECTURE

### 2.1 Why Two Tiers Are Necessary

Modern SharePoint Online enforces strict security sandboxing on its modern pages. Custom JavaScript, external CSS stylesheets, and arbitrary HTML injection are blocked by default. This means that the rich, interactive glassmorphic training application — with its animated pressure gauges, SVG valve simulations, quiz engine, and certificate generator — cannot execute natively inside a SharePoint modern page.

The platform solves this constraint with a Two-Tier Architecture:

**Tier 1: Native SharePoint Modern Pages** — Five professionally structured pages built using SharePoint's native web parts (Text, Image, Video, List, Quick Links). These pages provide organizational discoverability, search indexing, and the professional "front door" experience that IT departments expect. The five pages are: Home (landing page with executive summary and hero image), Procedure Guide (four-phase step-by-step instructions with safety warnings), Media and Resources (slide gallery and embedded video), Assessment (quiz instructions and compliance checklist), and Field Logs (connected to a SharePoint List for service record tracking).

**Tier 2: Interactive HTML Single-Page Application (SPA)** — A self-contained HTML5/CSS3/JavaScript application uploaded to the SharePoint Document Library. When users click the "Launch Interactive Training App" button on the SharePoint pages, the application opens in a new browser tab. Because it loads from the site's own HTTPS domain (not from a file:/// protocol), all features work perfectly: the YouTube video embeds, the fullscreen slide viewer, the SVG simulator, the quiz grading engine, and the print-ready certificate generator.

### 2.2 How the Tiers Connect

The native SharePoint pages reference the interactive app through direct hyperlinks to the document library URL. For example, the Home page contains a prominent call-to-action button that links to: `https://[tenant].sharepoint.com/sites/[site-name]/Training Assets/[module-name]/app/index.html`. When clicked, the full glassmorphic application loads in a new tab, rendering identically to the local development version because the browser's rendering engine processes the same HTML, CSS, and JavaScript regardless of whether the file is served from a local disk or a SharePoint document library.

---

## SECTION 3: THE INTERACTIVE TRAINING APPLICATION — DEEP TECHNICAL BREAKDOWN

### 3.1 Design System and Visual Architecture

The interactive training application uses a glassmorphic dark-theme design system. The background color is a deep space black (#030712) with radial gradient highlights in cyan (#00f0ff) and royal blue (#0072ff). All content panels use translucent backgrounds with CSS backdrop-filter blur effects (backdrop-filter: blur(12px)) and thin luminescent borders (1px solid rgba(255, 255, 255, 0.08)). This creates a layered depth effect where panels appear to float above the dark background.

Typography uses the Google Font "Outfit" for all body text and headings, and "JetBrains Mono" for monospaced data displays like pressure readings, timestamps, and system states. The color palette is carefully designed: cyan (#00f0ff) for primary accents and active states, green (#10b981) for success and safe conditions, amber (#f59e0b) for warnings and transitional states, and red (#ef4444) for critical alerts and safety violations.

All interactive elements feature smooth CSS transitions using cubic-bezier easing curves (0.4, 0, 0.2, 1) for a premium, fluid feel. Hover states on buttons and cards include subtle glow effects using box-shadow with colored alpha channels.

### 3.2 The SVG Pressure Gauge and Valve Simulation Engine

The core educational component is an interactive SVG diagram of the water filtration manifold system. This diagram contains two controllable valves, a removable filter housing, a replaceable cartridge with an O-ring gasket, animated water drip effects, air bubble animations, and a real-time pressure readout.

The simulation operates as a finite state machine with four phases:

Phase 1 (Isolate and Depressurize): The trainee clicks the red main inlet valve to rotate it to the closed position. Then they click the blue relief valve to open it. JavaScript runs a setInterval loop that decrements the pressure value from 125 PSI down to 0 PSI in 5 PSI increments every 50 milliseconds. As the pressure drops, the pressure readout changes color from red to amber to green. CSS animations trigger water drip effects from the relief valve. When pressure reaches zero, the state machine unlocks Phase 2.

Phase 2 (Extract): The trainee clicks the clear plastic housing, which animates downward using CSS transform translateY. The spent cartridge is visually extracted from the housing. The housing state indicator changes to "REMOVED" in red.

Phase 3 (Install and Verify): This phase contains a critical safety check. The trainee must choose the correct orientation for the new cartridge. If they select "O-Ring DOWN" (incorrect), the application displays an alert dialog explaining the critical orientation error and blocks further progress. If they select "O-Ring UP" (correct), the cartridge is placed inside the housing, the housing screws back on with an animation, and Phase 4 unlocks.

Phase 4 (Recommission): The trainee opens the main inlet valve slowly. CSS-animated air bubbles appear inside the housing and float upward. The relief valve remains open during the initial fill to allow air to escape. After a 3-second delay simulating the air purge, the relief valve closes automatically, and a setInterval loop increases the pressure from 0 PSI to 75 PSI. Upon reaching 75 PSI, the system state changes to "Active (Protected)" and the simulation is complete.

### 3.3 The Slide Carousel and Video Player

The slide carousel dynamically loads 18 PNG images extracted from the original PowerPoint presentation. Images are stored in the assets/slides/ directory and named sequentially (slide_01.png through slide_18.png). The JavaScript generates an array of slide objects from a count variable and renders them into an image container. Navigation buttons advance forward and backward through the carousel with a wrap-around loop. Clicking any slide image triggers the Fullscreen API (element.requestFullscreen()) to display the slide at native resolution.

The video player uses a native HTML5 video element with an MP4 source file. The video was originally hosted on YouTube but was downloaded locally using yt-dlp to avoid cross-origin security issues when the page is loaded from a file:/// protocol. A fullscreen toggle button calls the same Fullscreen API used by the slide viewer.

### 3.4 The Quiz Assessment Engine

The quiz module contains five multiple-choice questions derived directly from the SOP procedure content. Each question has four answer options, one correct answer index, and an explanation string. The quiz enforces a 100% pass requirement — all five questions must be answered correctly to generate a completion certificate.

When a trainee selects an answer, JavaScript immediately evaluates it against the correct index. Correct answers highlight the selected option in green with a checkmark icon and display the explanation. Incorrect answers highlight the selection in red, reveal the correct answer in green, and display the explanation. After all five questions are answered, the results screen shows the score. If the score is 5 out of 5, a "Generate Certificate" button appears.

### 3.5 The Certificate Generator and Print System

The certificate module renders the trainee's name (entered via a text input field), the completion date (automatically set to the current date), and a formatted certificate layout. The certificate is styled to look professional with a border, centered text, signature lines, and an official shield icon.

The print system uses CSS @media print rules to hide all page content except the certificate div. The certificate-print-view element is positioned absolutely to fill the entire print page. Background colors are overridden to white with black text for clean printer output. The trainee clicks "Print/Save Certificate PDF" which calls window.print(), allowing them to save a PDF or send to a physical printer.

### 3.6 The Field Verification Logger

The logger component provides a compliance checklist (four items that must be verified after completing the physical maintenance procedure) and a maintenance log form. When the form is submitted, JavaScript creates a JSON record object and stores it in the browser's localStorage under a dedicated key. The application reads localStorage on page load and renders all stored records in an HTML table, providing a persistent local audit trail that survives browser refreshes.

---

## SECTION 4: THE POWERSHELL DEPLOYMENT AUTOMATION ENGINE

### 4.1 Script Inventory and Execution Flow

The deployment engine consists of seven PowerShell scripts totaling 3,597 lines of production code. The scripts are designed for Windows 11 with PowerShell 7.2 or higher and the PnP.PowerShell module.

The execution flow is: The batch deployer (05_Batch_Deploy.ps1) reads the CSV manifest and loops through each training module. For each module, it calls the master orchestrator (01_Deploy_Training_Site.ps1), which first runs the prerequisites checker (00_Prerequisites.ps1) to validate the environment. If checks pass, it calls the asset uploader (03_Upload_Assets.ps1) to create document libraries, upload slide images, video files, and the interactive HTML application, and create compliance tracking SharePoint Lists. Next, it calls the page builder (02_Create_SharePoint_Pages.ps1) to construct five native SharePoint modern pages with text sections, image web parts, video embeds, and list connections. Finally, it calls the branding script (04_Apply_Branding.ps1) to apply the dark theme, configure site navigation, set the logo, and designate the home page.

All scripts share common utility functions from Deploy-Helpers.ps1, which provides color-coded console logging, configuration file parsing, connection validation, and HTML deployment report generation.

### 4.2 The Batch Deployment System for 100+ Modules

The batch deployment system reads a CSV manifest file (config/training_modules.csv) where each row defines a training module with its name, SharePoint site URL suffix, title, description, content folder path, video source, owner, category, and priority level. The batch script iterates through each row, invoking the master orchestrator with the extracted parameters.

The batch system supports a -DryRun flag for preview mode (no changes made), a -ContinueOnError flag to skip failed modules and continue processing, and a configurable delay between module deployments to avoid SharePoint API rate limiting. After completion, it generates an HTML dashboard report showing the status of each module deployment.

---

## SECTION 5: THE AI-POWERED SCALING SYSTEM

### 5.1 The 7-Prompt Pipeline

The AI Prompt Playbook provides seven sequential copy-paste prompts that any operator can use with an AI coding assistant to generate a new training module from scratch. The prompts cover: extracting slides from a PowerPoint file as PNG images, downloading a training video, generating the interactive glassmorphic HTML application with all components, creating the SharePoint module configuration JSON, setting up the content folder structure, running the PowerShell deployment, and performing quality assurance verification.

### 5.2 Time Budget and Annual Capacity

Each module takes approximately 52 minutes to produce: 10 minutes for content extraction, 15 minutes for HTML site generation, 5 minutes for SharePoint configuration, 5 minutes for automated deployment, 15 minutes for quality verification, and 2 minutes for registry updates. At a sustainable pace of 2 modules per week, this system can produce over 100 training modules in a single year, requiring only approximately 87 total hours of production time.

### 5.3 Quality Consistency Guarantees

Design consistency across all modules is enforced through four mechanisms: JSON page templates that define identical SharePoint page layouts, a global branding theme applied automatically by the deployment scripts, a self-contained CSS design system with documented color tokens and typography rules, and AI-driven quality checklists that verify visual design, responsiveness, print formatting, and simulation logic before each module is marked ready for production.

---

## SECTION 6: ENTERPRISE DEPLOYMENT CONSIDERATIONS

### 6.1 Authentication and Security

The platform supports both interactive browser-based authentication (suitable for manual deployments with MFA support) and unattended certificate-based authentication via Entra ID app registration (required for CI/CD pipelines and fully automated batch deployments).

### 6.2 Required Permissions

Deploying accounts need Site Creator or Admin permissions at the tenant level to provision new site collections, and Site Collection Administrator permissions on the target site to modify pages, upload files, apply branding, and manage lists.

### 6.3 SharePoint Limitations and Workarounds

SharePoint Online blocks custom JavaScript execution on modern pages for security. The platform works around this by hosting the interactive application as a standalone file in the document library, accessed via direct URL. This approach is industry-standard and supported by Microsoft's own documentation for custom single-page applications.

---

## SECTION 7: THE REFERENCE TRAINING MODULE — SS-10 SCALESTICK SOP

The repository includes one complete, production-ready training module as a reference implementation. The SS-10 ScaleStick Maintenance SOP covers the procedure for replacing scale inhibition filter cartridges in commercial water treatment systems. The module includes 18 high-resolution slides extracted from the original PowerPoint presentation, a 5-megabyte MP4 procedure walkthrough video, a complete interactive training application with pressure gauge simulation, four-phase interactive procedure walkthrough, five-question compliance assessment quiz, printable completion certificate generator, and field service verification logger with local storage persistence.

This reference module demonstrates the full capabilities of the platform and serves as the template that all future modules are modeled after. The design system, component architecture, quiz format, and certification workflow are all documented in the AI Scale Blueprint (docs/AI_SCALE_BLUEPRINT.md) with sufficient technical detail for an AI system to reproduce the identical level of quality for any new SOP topic.

---

## SECTION 8: HOW TO USE THIS REPOSITORY

### Step 1: Clone the Repository
Clone the GitHub repository to your local Windows 11 machine.

### Step 2: Configure Your SharePoint Tenant
Edit config/deployment_config.json and replace the placeholder tenant URL with your organization's SharePoint Online URL.

### Step 3: Install Prerequisites
Run scripts/00_Prerequisites.ps1 in PowerShell 7 to validate your environment and install the PnP.PowerShell module if needed.

### Step 4: Deploy the Reference Module
Run scripts/01_Deploy_Training_Site.ps1 with the parameter -ModuleName "scalestick_sop" to deploy the included ScaleStick SOP training site to your SharePoint tenant.

### Step 5: Create New Modules
Follow the AI Prompt Playbook (AI_PROMPT_PLAYBOOK.md) to generate new training modules from PowerPoint presentations and demonstration videos. Each new module follows the same folder structure, configuration format, and deployment workflow as the reference module.

### Step 6: Batch Deploy
Add new modules to config/training_modules.csv and run scripts/05_Batch_Deploy.ps1 to deploy multiple training sites in a single automated operation.

---

*This document contains the complete technical specification, architectural design, operational workflow, and scaling strategy for the SharePoint Training Site Deployer platform. It is designed to be consumed by AI systems (including Google NotebookLM) to generate comprehensive training materials, audio overviews, presentation slides, and infographic summaries with maximum technical depth and accuracy.*
