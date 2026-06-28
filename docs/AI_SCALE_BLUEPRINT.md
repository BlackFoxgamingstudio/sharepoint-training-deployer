# SCALE-UP BLUEPRINT: Autonomous Interactive Training Site Synthesis Engine
## Version 1.0.0 (SOP-SST-2026)

---

## 1. Executive Summary & System Intent

This document serves as the master engineering blueprint and scale-up playbook for the **SS-10 ScaleStick™ Maintenance SOP Interactive Training Hub**. It is designed to be read, parsed, and executed by agentic AI systems (and human systems architects) to duplicate the identical level of high-fidelity visual design, interactive states, telemetry simulation, and compliance verification for future maintenance procedures, hardware deployments, or technical standard operating procedures (SOPs).

### 1.1 The Core Mission
A common pitfall of training materials is that they are passive: PDFs are read but not absorbed; slide decks are clicked through but not simulated. The **ScaleStick™ SOP Training Hub** shifts this paradigm by building a self-contained, high-fidelity interactive dashboard that links **knowledge acquisition** (the slide deck), **procedural simulation** (the phase-by-phase simulator), and **compliance validation** (the quiz and print-ready certification log).

### 1.2 Architectural Constraints
To enable seamless distribution and offline accessibility, the solution is designed with the following constraints:
1. **Self-Contained Execution**: All styles (CSS) and logic (JavaScript) are housed in a single file (`index.html`) with zero external compiler or framework dependencies (no Tailwind, React, or Vue). This guarantees that the page can run locally, offline, or within any iframe wrapper.
2. **Deterministic State Machine**: Every user action (acknowledging safety, staging tools, opening valves) updates an internal state object that dynamically re-computes visual feedback, pressure readings, and UI accessibility locks.
3. **No-Database Persistence**: User training records are persisted locally via `localStorage` and formatted for clean table serialization, bypassing the need for an active SQL backend while maintaining a high-fidelity audit trail.

---

## 2. Global UI/UX Design System Tokens

For future projects to maintain design parity, the following CSS design system tokens must be enforced. The style is characterized by a "glassmorphic dark-theme dashboard" utilizing vibrant HSL border highlights and modern sans-serif typography.

### 2.1 CSS Custom Properties (Variables)
These properties must be declared in the `:root` pseudo-class:

```css
:root {
    /* Color Palette - Cyberpunk Dark Theme */
    --bg-dark: #030712;          /* Rich space black */
    --bg-panel: rgba(17, 24, 39, 0.7); /* Translucent charcoal */
    --border: rgba(255, 255, 255, 0.08); /* Faint white border */
    
    /* Active State Highlights */
    --accent-cyan: #00f0ff;       /* Primary glow / cyan */
    --accent-blue: #3b82f6;       /* Secondary glow / blue */
    --accent-green: #10b981;      /* Success / system operational */
    --accent-warning: #f59e0b;    /* Warning / caution state */
    --accent-red: #ef4444;        /* Critical / alert / safety */
    
    /* Text Hierarchy */
    --text-main: #f3f4f6;         /* Off-white readable text */
    --text-muted: #9ca3af;        /* Slate gray text */
    
    /* Borders & Glassmorphic variables */
    --glass-border: rgba(255, 255, 255, 0.05);
    --glass-border-cyan: rgba(0, 240, 255, 0.2);
    --glass-border-green: rgba(16, 185, 129, 0.2);
    --glass-border-red: rgba(239, 68, 68, 0.2);
    --glass-bg: rgba(10, 15, 30, 0.7);
    --card-glow: 0 0 15px rgba(0, 240, 255, 0.05);
    
    /* Layout Tokens */
    --radius-lg: 16px;
    --radius-md: 12px;
    --radius-sm: 8px;
    --transition-smooth: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
}
```

### 2.2 Global Layout Constraints
- **Global Reset**: Box-sizing must be set to `border-box`. Margins and paddings should be cleared.
- **Typography**: The primary typeface is `Outfit` or `Inter`, falling back to system sans-serif. Monospaced indicators (pressure logs, JSON database keys, timestamps) must use `JetBrains Mono` or `Consolas` at a slightly smaller scale (0.75rem - 0.8rem).
- **Glassmorphism Rule**: All panel containers must have `backdrop-filter: blur(12px)` and a thin border of `1px solid var(--glass-border)`. This ensures readability over dark background gradients and maintains depth hierarchy.

---

## 3. Core Component Walkthrough & Data Models

### 3.1 Simulated Manifold and Dial Gauge State Machine
A key element of this SOP dashboard is the live visual feedback showing system state. The dial gauge visualizes the current internal manifold water pressure, which changes dynamically based on the state of the isolation and flush valves.

```
       [Main Water Valve] (Parallel = ON, Perpendicular = OFF)
              |
              v
     [Manifold Core Chamber] <--- Venting --- [Pressure Relief Valve]
              |
              +---> [Water Pressure Gauge] (Current PSI)
```

#### The Physics Engine & Gauge State Model:
The system pressure is governed by three primary states:
1. **Normal Operating State**: Input valve open, flush valve closed. System pressure is stable at **125 PSI**.
2. **Isolated & Depressurized State**: Input valve closed, flush valve open. System pressure falls dynamically to **0 PSI**.
3. **Recharged State**: Input valve slowly opened, flush valve closed. System pressure rises back to a balanced operating range of **75 - 80 PSI**.

#### JS implementation pattern for Gauge Animation:
```javascript
let currentPressure = 125;
let targetPressure = 125;

function updateGaugeDisplay() {
    const needle = document.getElementById('gauge-needle');
    const label = document.getElementById('pressure-value');
    
    // Smooth interpolator loop (runs on frame tick)
    if (Math.abs(currentPressure - targetPressure) > 0.5) {
        currentPressure += (targetPressure - currentPressure) * 0.1;
        
        // Map PSI (0 - 150) to rotational degrees (-90deg to +90deg)
        const degrees = ((currentPressure / 150) * 180) - 90;
        needle.style.transform = `rotate(${degrees}deg)`;
        label.textContent = `${Math.round(currentPressure)} PSI`;
        
        // Dynamically shift gauge color based on safety thresholds
        if (currentPressure > 100) {
            label.style.color = 'var(--accent-red)';
        } else if (currentPressure > 5) {
            label.style.color = 'var(--accent-warning)';
        } else {
            label.style.color = 'var(--accent-green)';
        }
    }
}
```

---

### 3.2 Tooling Staging validation logic
Before starting the physical replacement steps of the SOP, the operator must stage their tool deck. This introduces a validation step: the checklist is represented as interactive cards that toggle a boolean state.

#### Data Model:
```javascript
const toolState = {
    ss10: false,  // New ScaleStick cartridge
    bin: false,   // Large Catch Bin
    label: false, // Blank Label & Marker
    towel: false  // Clean Towel
};
```

When a user clicks on a tool card:
1. The corresponding boolean in `toolState` toggles.
2. The UI card receives an `.active` class showing a checkmark and green boundary glow.
3. The validation engine checks if `Object.values(toolState).every(Boolean)` is true.
4. Once true, the UI unlocks the **Safety Switch** container.

---

### 3.3 Phase-by-Phase Interactive SOP Simulator
This is the core educational engine. The procedure is broken down into four distinct phases, each representing a key step of the SOP. The manifold system is drawn using responsive vector SVG layers. This allows the valves, water levels, and bubble animations to dynamically update via CSS transitions.

```
       [SVG Manifold Layout]
     +--------------------------+
     |   [Valve 1: Input]       | <-- Rotates 90 deg based on state
     |   [Chamber Water Level]  | <-- Opacity/height transition
     |   [Cartridge Slot]       | <-- Toggles old/new visibility
     |   [Valve 2: Flush]       | <-- Controls water drips
     +--------------------------+
```

#### SVG Interactive Elements:
- **Valve Rotations**: Managed using CSS transforms. A class `.off` rotates the group element:
  ```css
  #main-valve-handle {
      transition: transform 0.6s ease;
      transform-origin: center;
  }
  #main-valve-handle.off {
      transform: rotate(90deg); /* Parallel to perpendicular */
  }
  ```
- **Water Level & Bubbles**: SVGs are styled using selectors. For example, `#water-line` changes opacity from `0` to `1` as pressure returns.
- **Cartridge Alignment Checker**: When the user drags or selects the cartridge, the system checks if the orientation is correct. If the O-ring is set to face down, the manifold blocks insertion and prompts: `❌ ERROR: O-Ring orientation must face UP. Check standard guidelines.`

---

### 3.4 Slide carousel image rendering pipeline
To display PowerPoint presentations exactly as they were created by the designer, slide images are extracted as high-resolution PNGs and rendered using a responsive image element that matches the scale of the card layout.

#### Slide Data Structure:
```javascript
const slidesCount = 18;
const slidesData = Array.from({ length: slidesCount }, (_, i) => ({
    imgSrc: `assets/slides/slide_${String(i + 1).padStart(2, '0')}.png`
}));
```

#### Dynamic Rendering:
```javascript
function updateSlide() {
    const currentSlide = slidesData[currentSlideIndex];
    document.getElementById('slide-body-container').innerHTML = `
        <img src="${currentSlide.imgSrc}" 
             alt="SOP Slide ${currentSlideIndex + 1}" 
             style="width: 100%;
                    height: 100%;
                    object-fit: contain;
                    display: block;
                    max-height: 280px;
                    border-radius: var(--radius-sm);">
    `;
    document.getElementById('slide-page-num').textContent = `Slide ${currentSlideIndex + 1} of ${slidesData.length}`;
}
```

---

### 3.5 Compliance Assessment Engine (Stateful Quiz)
The certification engine contains five randomized or fixed multiple-choice questions designed to test knowledge of safety guidelines, valve orientations, and replacement criteria.

#### Quiz Schema:
```json
[
  {
    "q": "What is the primary operational consequence of mineral scale build-up inside commercial water lines?",
    "opts": [
      "Decreases water pressure to 0 PSI immediately",
      "Acts as a thermal insulator, increasing energy consumption and causing potential equipment failure",
      "Changes the water taste to highly acidic",
      "Increases filter cartridge lifespan by trapping sediment"
    ],
    "correct": 1
  },
  {
    "q": "Why is the use of wrenches or channel locks strictly prohibited when tightening the clear ScaleStick housing cup?",
    "opts": [
      "It makes the cup too tight to ever unscrew again",
      "It strips the threads on the brass copper supply inlet",
      "Mechanical tools can cause micro-fractures in the plastic housing, leading to catastrophic failure under pressure",
      "Wrenches cause the cartridge to align upside down"
    ],
    "correct": 2
  }
]
```

#### Quiz Logic & Flow:
1. **Answer Selection**: Once an option is chosen, the engine checks it against the `correct` index.
2. **Instant Visual Feedback**: Options receive success (green) or failure (red) highlights.
3. **Locking & Progress**: Users cannot proceed until they selection is checked, updating the progress bar.
4. **Final Scoring**: Scoring a perfect **5 / 5 (100%)** is required to unlock the **Compliance Certificate** and enable download.

---

### 3.6 LocalStorage Activity Log Database
All completed maintenance procedures must be recorded. Since the site is designed to run standalone, it uses the browser's `localStorage` as a lightweight database.

#### Log Data Structure:
```json
{
  "id": 1782674400000,
  "technician": "Sarah Connor",
  "cartridge_serial": "SS10-99824-A",
  "service_date": "2026-06-28",
  "next_service": "2026-12-28",
  "verified": "Yes"
}
```

#### Database Helper Methods:
- **Save Log Record**:
  ```javascript
  function saveMaintenanceRecord(record) {
      const records = JSON.parse(localStorage.getItem('ss10_logs') || '[]');
      records.unshift(record); // Add to beginning of array
      localStorage.setItem('ss10_logs', JSON.stringify(records));
  }
  ```
- **Read & Render Table**:
  ```javascript
  function loadMaintenanceLogs() {
      const records = JSON.parse(localStorage.getItem('ss10_logs') || '[]');
      const tbody = document.getElementById('log-table-body');
      tbody.innerHTML = '';
      if (records.length === 0) {
          tbody.innerHTML = '<tr><td colspan="5" class="no-records">No maintenance records submitted.</td></tr>';
          return;
      }
      records.forEach(rec => {
          tbody.innerHTML += `
              <tr>
                  <td>${rec.service_date}</td>
                  <td>${rec.technician}</td>
                  <td><code>${rec.cartridge_serial}</code></td>
                  <td>${rec.next_service}</td>
                  <td style="color:var(--accent-green); font-weight:bold;">✓ Verified</td>
              </tr>
          `;
      });
  }
  ```

---

## 4. Asset Pipeline & Page Extraction Guide

To ensure future slide decks are hosted with absolute visual fidelity, follow this workflow to extract presentation pages as high-resolution images.

```
  [PowerPoint PPTX] 
        |  (Save As)
        v
    [PDF Deck] 
        |  (PyMuPDF / fitz Python Script)
        v
  [High-Resolution PNGs] ---> [Optimized Web Assets]
```

### 4.1 PyMuPDF Page Extraction Script
Use the following Python script inside your virtual environment to extract high-resolution, crisp slide images from a PDF presentation:

```python
import os
import sys
import argparse

def extract_pdf_slides(pdf_path, output_dir, zoom_factor=2.0):
    try:
        import fitz  # PyMuPDF
    except ImportError:
        print("[!] PyMuPDF (fitz) is not installed.")
        print("[!] Install it with: pip install pymupdf")
        sys.exit(1)
        
    if not os.path.exists(pdf_path):
        print(f"[!] PDF not found: {pdf_path}")
        sys.exit(1)
        
    os.makedirs(output_dir, exist_ok=True)
    doc = fitz.open(pdf_path)
    print(f"[*] Processing: {pdf_path} ({len(doc)} pages)")
    
    for i in range(len(doc)):
        page = doc.load_page(i)
        # Set matrix for scaling to increase image DPI/resolution
        mat = fitz.Matrix(zoom_factor, zoom_factor)
        pix = page.get_pixmap(matrix=mat)
        
        # Save slides as two-digit index (e.g. slide_01.png)
        output_path = os.path.join(output_dir, f"slide_{i+1:02d}.png")
        pix.save(output_path)
        print(f"[+] Saved slide {i+1} to {output_path}")
        
    doc.close()
    print("[*] Page extraction successfully complete.")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Extract PDF pages to crisp web-ready PNGs.")
    parser.add_argument("--pdf", required=True, help="Path to input PDF file")
    parser.add_argument("--out", required=True, help="Directory to save extracted images")
    parser.add_argument("--zoom", type=float, default=2.0, help="Resolution scaling factor (default: 2.0)")
    args = parser.parse_args()
    
    extract_pdf_slides(args.pdf, args.out, args.zoom)
```

---

## 5. AI Playbook & Automation Instruction Set for Future Decks

When you are tasked with generating the next interactive training SOP website, use this structured system prompt to orchestrate the generation agent.

### 5.1 The System Prompt for Generator Agents
Copy and paste this prompt to prime the AI assistant for building a new interactive procedure module:

```markdown
You are an expert Frontend Architect specializing in high-fidelity, interactive, glassmorphic UI dashboards for engineering systems.
Your task is to build a self-contained training website for a technical Standard Operating Procedure (SOP) based on the user's instructions and assets.

### CRITICAL CORE PRINCIPLES:
1. **Single-File Architecture**: Output a single, self-contained HTML file containing all structural markup, inline styles (CSS), and logic (JS).
2. **Glassmorphic Aesthetic**: Use dark mode as the base (#030712). Apply glass-like panels using:
   - `background: rgba(255, 255, 255, 0.02);`
   - `backdrop-filter: blur(12px);`
   - `border: 1px solid rgba(255, 255, 255, 0.08);`
3. **No Placeholders**: Do not write comments like "insert script here". Code every feature completely (checklists, quizzes, states, databases).
4. **Print Optimization**: Add `@media print` rules to ensure that completion certificates print cleanly onto a single standard US Letter or A4 sheet with clean margins and background-graphics enabled.

### COMPONENTS TO ALWAYS GENERATE:
1. **Navbar**: Standard navigation links pointing to local anchor divs. No external page links.
2. **Telemetry Gauge**: An interactive SVG gauge displaying pressure, temperature, or flow rate that changes dynamically based on simulated valve inputs.
3. **Tool Deck Checklist**: Interactive cards for staging required tools. Must validate tool completion before letting the user proceed.
4. **Multi-Phase Procedural Simulator**: A step-by-step interactive walkthrough utilizing dynamic SVG manifold layers. Animate valves, level indicators, and indicators.
5. **Slide Carousel**: Displays slide deck pages. Store slides in an array and render them sequentially using standard next/prev controllers.
6. **Stateful Quiz**: Generate 5 multiple-choice questions on safety and execution logic. Require a 100% score to generate the certificate.
7. **Certificate Generator**: Dynamic print-ready layout that updates with the user's name and completion date.
8. **Compliance Logger**: Input forms for technician registration, logging records to `localStorage` and rendering them in an activity table on the page.
```

---

### 5.2 Step-by-Step Prompt Flow to Drive Synthesis
Follow this sequence of requests to guide the AI assistant through construction:

```
    [Step 1: Scaffolding] -> [Step 2: Physics Engine] -> [Step 3: Quiz & Logs] -> [Step 4: Media Sync]
```

#### Step 1: Base Scaffolding & Design System Setup
> *"Create a single-file interactive training dashboard for the [PROCEDURE NAME] using a dark glassmorphic design system. Define CSS custom properties for cyber-theme highlights (cyan, blue, green, amber, red). Scaffold the navbar, dashboard header, and the core grid panel sections. Do not include javascript yet, focus entirely on structural HTML and design layouts."*

#### Step 2: Interactive SVG Simulator & Pressure Engine
> *"Add the interactive simulation manifold to the page using SVG. I want two main valves: [VALVE 1] and [VALVE 2]. Create a JavaScript state engine that controls system state variables (pressure, flow rate, isolation). Make an SVG circular dial gauge that interpolates system values smoothly. Unify this with the checklist cards: when the user checks all tools off, unlock the safety override."*

#### Step 3: Quiz Assessment & LocalStorage Database
> *"Implement the stateful quiz module (5 questions with instant green/red feedback on answer selection). Score metric must block certificate unlocking until 100% is reached. Add a technician registration form that commits logs to localStorage under the namespace [PROJECT_KEY]_logs and populates a historical table below."*

#### Step 4: Slide Carousel & Asset Binding
> *"Configure the slide deck component. Assume slides are located at assets/slides/slide_01.png through slide_XX.png. Bind the slide carousel controller buttons to display the images. Add clean fallback styling for when images are missing."*

---

## 6. Directory Structure & Distribution Manifest

To distribute this training solution independently, package the files using this exact directory structure:

```
scalestick_sop_training/
│
├── index.html                  # Self-contained training page (reconstructed)
├── solution_blueprint.md        # This master architecture guide
│
└── assets/                     # Media & asset resources
    │
    ├── favicon.svg             # Page tab icon
    ├── dashboard.png           # Video fallback poster image
    │
    └── slides/                 # High-resolution PowerPoint slides
        ├── slide_01.png
        ├── slide_02.png
        ├── slide_03.png
        ├── slide_04.png
        ├── slide_05.png
        ├── slide_06.png
        ├── slide_07.png
        ├── slide_08.png
        ├── slide_09.png
        ├── slide_10.png
        ├── slide_11.png
        ├── slide_12.png
        ├── slide_13.png
        ├── slide_14.png
        ├── slide_15.png
        ├── slide_16.png
        ├── slide_17.png
        └── slide_18.png
```

### 6.1 Distribution Instructions
- **Compression**: Zip the entire `scalestick_sop_training/` folder to distribute it as a lightweight training package.
- **Hosting**: The folder can be uploaded to any static hosting service (Netlify, Vercel, AWS S3, GitHub Pages) or served locally by simply double-clicking `index.html`.
- **Custom Video Integration**: When a procedure video becomes available, drop the video file into the `assets/` folder named `procedure_video.mp4` to automatically link it to the interface player.

---

## 7. Troubleshooting & Verification Log

| Symptom | Root Cause | Solution Pattern |
| :--- | :--- | :--- |
| Slides show broken image icons | Path mismatch or images not extracted | Verify PNG names inside `assets/slides/` are zero-padded (`slide_01.png`). |
| Certificate does not fit page when printing | Page scale issues in browser print settings | Set print margins to "Default" or "None" in the print dialog and ensure "Background graphics" is checked. |
| Quiz resets on page refresh | State is volatile by design | Quiz state is memory-only to enforce assessment validation. Completed service logs are persistent. |
| Gauge needle rotates wildly | CSS transform-origin point is unaligned | Ensure `#gauge-needle` has `transform-origin: center bottom` or matches the rotation anchor. |

---
*End of Blueprint. Engineered for scalability, automation, and platform reliability.*
