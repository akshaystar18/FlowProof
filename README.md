# FlowProof

**Automated Workflow Testing for macOS Applications**

FlowProof lets you define, record, execute, and validate automated workflow tests against any desktop app on macOS. Upload a YAML workflow, hit Run, and get a detailed pass/fail dashboard with per-step screenshots.

## Quick Start

```bash
# Build
swift build

# Run CLI
swift run FlowProof run Examples/test-slack-message.yaml --output text

# Validate a workflow without running it
swift run FlowProof validate Examples/test-figma-export.yaml
```

## Requirements

- macOS 13 Ventura or later
- Accessibility permission (System Settings > Privacy & Security > Accessibility)
- Swift 5.9+

## Project Structure

```
FlowProof/
├── Package.swift
├── Sources/FlowProof/
│   ├── App/                    # SwiftUI app entry + content view + CLI
│   ├── Models/                 # Data models, DB schema, GRDB persistence
│   ├── Parser/                 # YAML/JSON workflow parser + variable resolver
│   ├── Engine/                 # Automation: AX, CGEvent, Vision, hybrid locator
│   ├── Assertions/             # 21 assertion types across 6 categories
│   ├── Sequencer/              # Step executor, workflow runner, report generator
│   ├── Recorder/               # Event capture, action inference, YAML generation
│   ├── Dashboard/              # SwiftUI views: dashboard, detail, recorder
│   └── Utils/                  # Extensions and helpers
├── Tests/FlowProofTests/       # Unit tests
└── Examples/                   # Sample workflow YAML files
```

## Architecture

Three-tier automation engine with automatic fallback:

1. **Accessibility API** (AXUIElement) — Primary. Works with native Cocoa/AppKit apps.
2. **Vision Framework** (OCR + Template Matching) — Fallback for Electron/web apps.
3. **CGEvent** (Raw Input) — Universal fallback for any app.

## Defining Workflows

Workflows are YAML files with a clean schema:

```yaml
name: "My Workflow"
version: "1.0"
target_app:
  name: "Safari"
  bundle_id: "com.apple.Safari"
  launch: true
variables:
  url: "https://example.com"
steps:
  - name: "Navigate to URL"
    action: key
    combo: "cmd+l"
  - action: type
    text: "${url}"
  - action: key
    combo: "return"
  - name: "Verify page loaded"
    action: assert
    type: text_contains
    target:
      text_ocr: "Example Domain"
    expected: "Example Domain"
```

## Supported Actions

click, drag, type, key, scroll, wait, upload, download, assert, screenshot, launch, conditional, loop, sub_workflow, set_variable, clipboard, menu

## License

Proprietary. All rights reserved.
