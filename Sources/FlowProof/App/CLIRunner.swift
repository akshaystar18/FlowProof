import Foundation

/// Command-line interface for running workflows without GUI
class CLIRunner {
    let database: DatabaseManager

    init() throws {
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("flowproof-cli.db").path
        self.database = try DatabaseManager(path: dbPath)
    }

    /// Main entry point for CLI mode
    func run(arguments: [String]) async throws {
        guard arguments.count > 0 else {
            printUsage()
            exit(0)
        }

        let command = arguments[0]

        switch command {
        case "run":
            try await runCommand(Array(arguments.dropFirst()))
        case "validate":
            try validateCommand(Array(arguments.dropFirst()))
        case "list-actions":
            listActionsCommand()
        case "version":
            versionCommand()
        case "--help", "-h", "help":
            printUsage()
        default:
            printColored("Unknown command: \(command)", color: .red)
            printUsage()
            exit(1)
        }
    }

    /// Run a workflow and output results
    private func runCommand(_ arguments: [String]) async throws {
        var workflowPath: String?
        var timeout: TimeInterval?
        var outputFormat: OutputFormat = .text
        var screenshotsDir: String?

        var i = 0
        while i < arguments.count {
            let arg = arguments[i]
            switch arg {
            case "--timeout":
                i += 1
                if i < arguments.count, let value = TimeInterval(arguments[i]) {
                    timeout = value
                }
            case "--output":
                i += 1
                if i < arguments.count, let format = OutputFormat(rawValue: arguments[i]) {
                    outputFormat = format
                }
            case "--screenshots-dir":
                i += 1
                if i < arguments.count {
                    screenshotsDir = arguments[i]
                }
            case "--help", "-h":
                printRunUsage()
                exit(0)
            default:
                if !arg.hasPrefix("-") && workflowPath == nil {
                    workflowPath = arg
                }
            }
            i += 1
        }

        guard let path = workflowPath else {
            printColored("Error: workflow path is required", color: .red)
            printRunUsage()
            exit(1)
        }

        try await runWorkflow(path: path, timeout: timeout, outputFormat: outputFormat, screenshotsDir: screenshotsDir)
    }

    /// Validate a workflow file without running it
    private func validateCommand(_ arguments: [String]) throws {
        guard arguments.count > 0 else {
            printColored("Error: workflow path is required", color: .red)
            printValidateUsage()
            exit(1)
        }

        let path = arguments[0]
        try validateWorkflow(path: path)
    }

    /// List all supported action types
    private func listActionsCommand() {
        let actions = [
            ("click", "Click on a UI element"),
            ("drag", "Drag from one element to another"),
            ("type", "Type text into a field or globally"),
            ("key", "Press a keyboard shortcut (e.g., cmd+s)"),
            ("scroll", "Scroll at a position or element"),
            ("wait", "Wait for element, text, or condition"),
            ("upload", "Upload a file via dialog or drag-drop"),
            ("download", "Wait for a file to appear at a path"),
            ("assert", "Validate state (visual, text, file, timing)"),
            ("screenshot", "Capture evidence screenshot"),
            ("launch", "Launch or activate an application"),
            ("conditional", "Branch based on element presence"),
            ("loop", "Repeat steps N times or until condition"),
            ("sub_workflow", "Execute another workflow inline"),
            ("set_variable", "Set or update a runtime variable"),
            ("clipboard", "Copy to or paste from clipboard"),
            ("menu", "Navigate app menu bar"),
        ]

        printColored("Supported Actions:", color: .bold)
        print("")

        for (name, description) in actions {
            printColored("  \(name)", color: .blue)
            print("    \(description)")
        }

        print("")
    }

    /// Print version information
    private func versionCommand() {
        print("FlowProof CLI v1.0.0")
        print("Automated workflow testing framework for macOS")
    }

    /// Run a workflow and output results
    private func runWorkflow(
        path: String,
        timeout: TimeInterval?,
        outputFormat: OutputFormat,
        screenshotsDir: String?
    ) async throws {
        let expandedPath = (path as NSString).expandingTildeInPath

        guard FileManager.default.fileExists(atPath: expandedPath) else {
            printColored("Error: workflow file not found: \(path)", color: .red)
            exit(1)
        }

        print("Loading workflow from \(path)...")

        do {
            let url = URL(fileURLWithPath: expandedPath)
            var workflow = try WorkflowParser.parse(from: url)

            // Override timeout if specified via CLI
            if let timeout = timeout {
                workflow.timeout = timeout
            }

            print("Starting workflow: \(workflow.name)")
            print("  Target: \(workflow.targetApp.name)")
            print("  Steps: \(workflow.steps.count)")
            print("")

            let runner = WorkflowRunner(database: database)
            let run = try await runner.run(workflow: workflow)

            // Fetch step results for reporting
            let stepResults = (try? database.fetchStepResults(forRunId: run.id ?? 0)) ?? []

            printResults(run, steps: stepResults, format: outputFormat)

            let exitCode: Int32 = run.status == .passed ? 0 : 1
            exit(exitCode)

        } catch {
            printColored("Error: \(error.localizedDescription)", color: .red)
            exit(1)
        }
    }

    /// Validate a workflow file without running it
    private func validateWorkflow(path: String) throws {
        let expandedPath = (path as NSString).expandingTildeInPath

        guard FileManager.default.fileExists(atPath: expandedPath) else {
            printColored("Error: workflow file not found: \(path)", color: .red)
            exit(1)
        }

        do {
            let url = URL(fileURLWithPath: expandedPath)
            let workflow = try WorkflowParser.parse(from: url)

            printColored("✓ Workflow is valid", color: .green)
            print("  Name: \(workflow.name)")
            print("  Target: \(workflow.targetApp.name)")
            print("  Steps: \(workflow.steps.count)")
            exit(0)

        } catch {
            printColored("✗ Workflow validation failed:", color: .red)
            print("  \(error.localizedDescription)")
            exit(1)
        }
    }

    /// Print results in the requested format
    private func printResults(_ run: WorkflowRun, steps: [StepResult], format: OutputFormat) {
        switch format {
        case .json:
            let json = generateJSON(run, steps: steps)
            print(json)
        case .html:
            let html = generateHTML(run, steps: steps)
            print(html)
        case .text:
            let report = generateTextReport(run, steps: steps)
            print(report)
        }
    }

    /// Generate JSON output
    private func generateJSON(_ run: WorkflowRun, steps: [StepResult]) -> String {
        let iso = ISO8601DateFormatter()
        var json = "{\n"
        json += "  \"workflow\": \"\(run.workflowName)\",\n"
        json += "  \"status\": \"\(run.status.rawValue)\",\n"
        json += "  \"startedAt\": \"\(iso.string(from: run.startedAt))\",\n"

        if let duration = run.durationMs {
            json += "  \"durationMs\": \(duration),\n"
        }

        json += "  \"summary\": {\n"
        json += "    \"total\": \(run.totalSteps),\n"
        json += "    \"passed\": \(run.passedSteps),\n"
        json += "    \"failed\": \(run.failedSteps),\n"
        json += "    \"skipped\": \(run.skippedSteps)\n"
        json += "  },\n"

        json += "  \"steps\": [\n"
        for (index, step) in steps.enumerated() {
            let name = (step.stepName ?? "Step \(step.stepIndex + 1)").replacingOccurrences(of: "\"", with: "\\\"")
            json += "    {\n"
            json += "      \"index\": \(step.stepIndex + 1),\n"
            json += "      \"name\": \"\(name)\",\n"
            json += "      \"action\": \"\(step.action)\",\n"
            json += "      \"status\": \"\(step.status.rawValue)\",\n"
            json += "      \"durationMs\": \(step.durationMs ?? 0)"

            if let errorMsg = step.errorMessage, !errorMsg.isEmpty {
                json += ",\n      \"error\": \"\(errorMsg.replacingOccurrences(of: "\"", with: "\\\""))\""
            }

            json += "\n    }"
            if index < steps.count - 1 { json += "," }
            json += "\n"
        }
        json += "  ]\n"
        json += "}\n"

        return json
    }

    /// Generate HTML output
    private func generateHTML(_ run: WorkflowRun, steps: [StepResult]) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short

        var html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <title>FlowProof Report - \(run.workflowName)</title>
            <style>
                body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 20px; background: #f5f5f5; }
                .container { max-width: 900px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
                h1 { margin-top: 0; color: #333; }
                .summary { display: grid; grid-template-columns: repeat(4, 1fr); gap: 10px; margin: 20px 0; }
                .summary-item { padding: 15px; border-radius: 4px; text-align: center; }
                .summary-item h3 { margin: 0; font-size: 24px; }
                .summary-item p { margin: 5px 0 0 0; color: #666; }
                .passed { background: #e8f5e9; color: #2e7d32; }
                .failed { background: #ffebee; color: #c62828; }
                .skipped { background: #fff3e0; color: #e65100; }
                .total { background: #e3f2fd; color: #1565c0; }
                .status { font-weight: bold; padding: 4px 8px; border-radius: 3px; }
                .step { padding: 12px; margin: 8px 0; border-left: 4px solid #ddd; background: #fafafa; }
                .step.passed { border-left-color: #4caf50; }
                .step.failed { border-left-color: #f44336; }
                .step-header { display: flex; justify-content: space-between; margin-bottom: 8px; }
                .step-name { font-weight: bold; }
                .step-action { display: inline-block; padding: 2px 6px; background: #e3f2fd; color: #1565c0; border-radius: 2px; font-size: 12px; }
                .error { color: #c62828; margin-top: 8px; padding: 8px; background: #ffebee; border-radius: 3px; }
                footer { margin-top: 30px; text-align: center; color: #999; font-size: 12px; }
            </style>
        </head>
        <body>
            <div class="container">
                <h1>FlowProof Test Report</h1>
                <p><strong>Workflow:</strong> \(run.workflowName)</p>
                <p><strong>Date:</strong> \(df.string(from: run.startedAt))</p>
        """

        if let durationMs = run.durationMs {
            let secs = Double(durationMs) / 1000.0
            html += "<p><strong>Duration:</strong> \(String(format: "%.1fs", secs))</p>\n"
        }

        html += """
            <div class="summary">
                <div class="summary-item total"><h3>\(run.totalSteps)</h3><p>Total</p></div>
                <div class="summary-item passed"><h3>\(run.passedSteps)</h3><p>Passed</p></div>
                <div class="summary-item failed"><h3>\(run.failedSteps)</h3><p>Failed</p></div>
                <div class="summary-item skipped"><h3>\(run.skippedSteps)</h3><p>Skipped</p></div>
            </div>
            <div class="steps"><h2>Steps</h2>
        """

        for step in steps {
            let name = step.stepName ?? "Step \(step.stepIndex + 1)"
            let statusClass = step.status.rawValue
            let dur = step.durationMs.map { "\($0)ms" } ?? ""

            html += """
            <div class="step \(statusClass)">
                <div class="step-header">
                    <span class="step-name">\(step.stepIndex + 1). \(name)</span>
                    <span class="status \(statusClass)">\(step.status.rawValue.uppercased())</span>
                </div>
                <div><span class="step-action">\(step.action.uppercased())</span>
                <span style="color:#666;font-size:12px;">\(dur)</span></div>
            """

            if let err = step.errorMessage, !err.isEmpty {
                html += "<div class=\"error\"><strong>Error:</strong> \(err)</div>"
            }
            html += "</div>\n"
        }

        html += """
            </div>
            <footer><p>Generated by FlowProof CLI</p></footer>
            </div>
        </body></html>
        """
        return html
    }

    /// Generate text output
    private func generateTextReport(_ run: WorkflowRun, steps: [StepResult]) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short

        var report = "\n"
        report += "╔════════════════════════════════════════════════════════════╗\n"
        report += "║                    FlowProof Test Report                    ║\n"
        report += "╚════════════════════════════════════════════════════════════╝\n"
        report += "\n"

        report += "Workflow: \(run.workflowName)\n"
        report += "Date:     \(df.string(from: run.startedAt))\n"

        if let durationMs = run.durationMs {
            let secs = Double(durationMs) / 1000.0
            report += "Duration: \(String(format: "%.1fs", secs))\n"
        }

        report += "\n"
        report += "┌────────────────────────────────────────────────────────────┐\n"
        report += "│ SUMMARY                                                    │\n"
        report += "├────────────────────────────────────────────────────────────┤\n"
        report += "│  Total: \(run.totalSteps)  Passed: \(run.passedSteps)  Failed: \(run.failedSteps)  Skipped: \(run.skippedSteps)\n"
        report += "└────────────────────────────────────────────────────────────┘\n"
        report += "\n"

        if !steps.isEmpty {
            report += "┌────────────────────────────────────────────────────────────┐\n"
            report += "│ STEPS                                                      │\n"
            report += "├────────────────────────────────────────────────────────────┤\n"

            for step in steps {
                let statusSymbol: String
                let statusColor: TerminalColor

                switch step.status {
                case .passed:
                    statusSymbol = "✓"
                    statusColor = .green
                case .failed:
                    statusSymbol = "✗"
                    statusColor = .red
                case .skipped:
                    statusSymbol = "⊝"
                    statusColor = .yellow
                default:
                    statusSymbol = "⧖"
                    statusColor = .blue
                }

                let name = step.stepName ?? "Step \(step.stepIndex + 1)"
                let coloredStatus = "\(statusColor.rawValue)\(statusSymbol)\(TerminalColor.reset.rawValue)"
                let dur = step.durationMs.map { "\($0)ms" } ?? "—"

                report += "│ \(step.stepIndex + 1). \(coloredStatus) \(name)  \(dur)\n"

                if let errorMsg = step.errorMessage, !errorMsg.isEmpty {
                    report += "│   \(TerminalColor.red.rawValue)Error: \(errorMsg)\(TerminalColor.reset.rawValue)\n"
                }
            }

            report += "└────────────────────────────────────────────────────────────┘\n"
        }

        report += "\n"
        return report
    }

    /// Print colored text to terminal
    private func printColored(_ text: String, color: TerminalColor) {
        print("\(color.rawValue)\(text)\(TerminalColor.reset.rawValue)")
    }

    // MARK: - Usage Prints

    private func printUsage() {
        print("""
        FlowProof CLI - Automated Workflow Testing

        USAGE:
            flowproof <command> [options]

        COMMANDS:
            run              Run a workflow
            validate         Validate a workflow file
            list-actions     List all supported action types
            version          Print version information
            help             Show this help message

        OPTIONS:
            --help           Show command-specific help

        EXAMPLES:
            flowproof run workflow.yaml
            flowproof run workflow.yaml --timeout 60 --output json
            flowproof run workflow.yaml --screenshots-dir ./screenshots
            flowproof validate workflow.yaml
            flowproof list-actions

        For more help on a specific command:
            flowproof <command> --help
        """)
    }

    private func printRunUsage() {
        print("""
        USAGE:
            flowproof run <workflow.yaml> [options]

        OPTIONS:
            --timeout N              Maximum execution time in seconds
            --output json|html|text  Output format (default: text)
            --screenshots-dir PATH   Directory to save screenshots
            --help                   Show this help message

        EXAMPLES:
            flowproof run workflow.yaml
            flowproof run workflow.yaml --timeout 60
            flowproof run workflow.yaml --output json > results.json
            flowproof run workflow.yaml --screenshots-dir ./screenshots
        """)
    }

    private func printValidateUsage() {
        print("""
        USAGE:
            flowproof validate <workflow.yaml>

        OPTIONS:
            --help    Show this help message

        EXAMPLES:
            flowproof validate workflow.yaml
        """)
    }
}

enum OutputFormat: String {
    case json
    case html
    case text
}

enum TerminalColor: String {
    case red = "\u{001B}[31m"
    case green = "\u{001B}[32m"
    case yellow = "\u{001B}[33m"
    case blue = "\u{001B}[34m"
    case reset = "\u{001B}[0m"
    case bold = "\u{001B}[1m"
}
