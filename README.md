# FlowProof

**FlowProof** is a macOS app for defining and running automated UI test workflows using simple YAML files and the macOS Accessibility API. No coding required — describe what to click, type, and assert, and FlowProof does the rest.

---

## Features

- **YAML-based workflows** — Human-readable test scripts, version-controllable
- **macOS Accessibility API** — Native element targeting by role, label, and identifier
- **Vision Engine** — Text detection and screenshot capture via Vision framework
- **Run History** — Every run is stored with step-by-step results and screenshots
- **Recorder** *(experimental)* — Record clicks and keystrokes to generate workflow YAML
- **Retry & failure strategies** — Abort, skip, or retry on step failure

---

## Requirements

- macOS 13 Ventura or later
- Xcode 15+ / Swift 5.9+ (to build from source)
- Accessibility permission (Settings → Privacy & Security → Accessibility)

---

## Building

```bash
./BUILD_AND_RUN.command
```

Or manually:

```bash
swift build -c release
```

---

## Quick Start

1. Launch **FlowProof.app**
2. Grant **Accessibility** permission when prompted
3. Click **Import Workflow** and open one of the example YAML files from `Examples/`
4. Click **Run** — watch the steps execute in real time
5. View pass/fail results and screenshots in the Run History panel

---

## Workflow YAML Format

```yaml
name: My Test Workflow
description: What this workflow does
version: "1.0"

target_app:
  name: Safari
  bundle_id: com.apple.Safari
  launch: true   # launch the app automatically

on_failure: abort   # abort | skip | retry

variables:
  username: testuser
  password: secret123

setup:          # runs before main steps, failures abort the run
  - name: Wait for app
    action: wait
    duration: 2

steps:
  - name: Click Login button
    action: click
    element:
      role: AXButton
      label: Login

  - name: Type username
    action: type
    text: "{{username}}"

  - name: Assert welcome message
    action: assert_text
    expected: "Welcome, testuser"
    match_mode: contains

teardown:       # runs after steps regardless of pass/fail
  - name: Close app
    action: key_combo
    key: cmd+q
```

---

## Available Actions

| Action | Description |
|---|---|
| `click` | Click a UI element by role/label |
| `type` | Type text into focused field |
| `key_combo` | Press keyboard shortcut (e.g., `cmd+s`) |
| `wait` | Wait N seconds |
| `assert_text` | Assert text is visible on screen |
| `assert_element` | Assert a UI element exists with given attributes |
| `screenshot` | Capture a screenshot of the target app window |
| `scroll` | Scroll in a direction |
| `set_variable` | Set a variable for use in later steps |
| `launch` | Launch an application by bundle ID |
| `conditional` | If/else branching based on element or text presence |
| `loop` | Repeat a set of steps N times |

---

## Example Workflows

See the [`Examples/`](Examples/) directory:

| File | Description |
|---|---|
| `01_safari_google_search.yaml` | Opens Safari, performs a Google search, asserts results appear |
| `02_textedit_create_document.yaml` | Creates a TextEdit document, types content, verifies text |
| `03_calculator_basic_math.yaml` | Opens Calculator, computes 42 + 58, asserts result is 100 |

---

## Use Cases

- **QA regression testing** for macOS apps without writing Swift test code
- **Automated UI checks** in CI/CD (run headlessly via command line)
- **Onboarding validation** — verify new machine setup completes correctly
- **Accessibility auditing** — confirm elements are reachable by Accessibility APIs
- **Demo automation** — run scripted product demos repeatably

---

## Project Structure

```
FlowProof/
├── Sources/FlowProof/
│   ├── App/              # App entry point, AppState
│   ├── Dashboard/        # SwiftUI views (main UI)
│   ├── Engine/           # AccessibilityEngine, InputEngine, VisionEngine
│   ├── Models/           # Workflow, Run, Database models
│   ├── Parser/           # YAML → Workflow parsing
│   ├── Recorder/         # Event capture & action inference
│   └── Sequencer/        # WorkflowRunner, StepExecutor
├── Examples/             # Sample YAML workflows
├── Package.swift
└── BUILD_AND_RUN.command
```

---

## License

MIT
