import SwiftUI

struct RunDetailView: View {
    let run: WorkflowRun
    @EnvironmentObject var appState: AppState
    @State private var stepResults: [StepResult] = []
    @State private var selectedStep: StepResult?
    @State private var showScreenshotGallery = false

    var body: some View {
        VStack(spacing: 0) {
            // Top: Run summary header bar
            summaryHeader
                .background(Color(.controlBackgroundColor))
                .border(Color.gray.opacity(0.2), width: 1)

            // Middle: HSplitView with timeline and detail
            HSplitView {
                // Left panel: Step timeline
                stepTimelinePanel

                // Right panel: Selected step detail
                stepDetailPanel
            }
            .frame(minWidth: 300, minHeight: 300)

            // Bottom: Export buttons
            exportButtonsBar
                .background(Color(.controlBackgroundColor))
                .border(Color.gray.opacity(0.2), width: 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            loadStepResults()
        }
    }

    // MARK: - Components

    private var summaryHeader: some View {
        HStack(spacing: 20) {
            // Status icon
            Image(systemName: statusIconName)
                .font(.system(size: 24))
                .foregroundColor(Color.forRunStatus(run.status))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    Text(run.workflowName)
                        .font(.headline)

                    StatusBadge(status: run.status)
                }

                HStack(spacing: 16) {
                    Label(run.startedAt.shortDisplay, systemImage: "calendar")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let durationMs = run.durationMs {
                        Label(durationMs.durationDisplay, systemImage: "clock")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // Step counts
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 16) {
                    StepCountBadge(
                        count: stepResults.filter { $0.status == .passed }.count,
                        status: .passed
                    )
                    StepCountBadge(
                        count: stepResults.filter { $0.status == .failed }.count,
                        status: .failed
                    )
                    StepCountBadge(
                        count: stepResults.filter { $0.status == .skipped }.count,
                        status: .skipped
                    )
                }

                Text("\(stepResults.count) steps")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
    }

    private var stepTimelinePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Steps")
                .font(.headline)
                .padding(12)
                .background(Color(.controlBackgroundColor))
                .border(Color.gray.opacity(0.2), width: 1)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(stepResults.enumerated()), id: \.element.id) { index, step in
                        StepTimelineRow(
                            step: step,
                            index: index + 1,
                            isSelected: selectedStep?.id == step.id,
                            onTap: {
                                selectedStep = step
                                showScreenshotGallery = false
                            }
                        )
                        .border(Color.gray.opacity(0.1), width: 1)
                    }
                }
            }
        }
    }

    private var stepDetailPanel: some View {
        ZStack {
            if let selected = selectedStep {
                StepDetailContent(
                    step: selected,
                    showScreenshotGallery: $showScreenshotGallery
                )
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "rectangle.and.pencil.and.ellipsis")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("Select a step to view details")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.controlBackgroundColor))
            }
        }
    }

    private var exportButtonsBar: some View {
        HStack(spacing: 12) {
            Spacer()

            Button(action: exportAsJSON) {
                Label("JSON", systemImage: "doc.text")
            }
            .buttonStyle(.bordered)

            Button(action: exportAsHTML) {
                Label("HTML Report", systemImage: "doc.richtext")
            }
            .buttonStyle(.bordered)

            Button(action: exportAsPDF) {
                Label("PDF", systemImage: "doc.pdf")
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
    }

    // MARK: - Helper Methods

    private func loadStepResults() {
        Task {
            do {
                if let runId = run.id {
                    self.stepResults = try appState.database.fetchStepResults(forRunId: runId)
                }
            } catch {
                print("Error loading step results: \(error)")
            }
        }
    }

    private func exportAsJSON() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(run.workflowName)-report.json"

        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }

            Task {
                do {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let jsonData = try encoder.encode(run)
                    try jsonData.write(to: url)
                    NSWorkspace.shared.open(url)
                } catch {
                    showExportError("Failed to export JSON: \(error.localizedDescription)")
                }
            }
        }
    }

    private func exportAsHTML() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = "\(run.workflowName)-report.html"

        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }

            do {
                if let runId = run.id {
                    let generator = ReportGenerator()
                    let html = try generator.generateHTMLReport(runId: runId)
                    try html.write(to: url, atomically: true, encoding: .utf8)
                    NSWorkspace.shared.open(url)
                } else {
                    showExportError("Cannot export: Run ID is missing")
                }
            } catch {
                showExportError("Failed to export HTML: \(error.localizedDescription)")
            }
        }
    }

    private func exportAsPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(run.workflowName)-report.pdf"

        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }

            do {
                if let runId = run.id {
                    let generator = ReportGenerator()
                    let html = try generator.generateHTMLReport(runId: runId)
                    try generator.saveReport(html, to: url.path)
                    NSWorkspace.shared.open(url)
                } else {
                    showExportError("Cannot export: Run ID is missing")
                }
            } catch {
                showExportError("Failed to export PDF: \(error.localizedDescription)")
            }
        }
    }

    private func showExportError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Export Failed"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private var statusIconName: String {
        switch run.status {
        case .passed:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        case .running:
            return "hourglass.circle.fill"
        case .skipped:
            return "circle.slash.fill"
        case .pending:
            return "circle.dashed"
        case .aborted:
            return "stop.circle.fill"
        }
    }
}

// MARK: - Supporting Views

struct StepTimelineRow: View {
    let step: StepResult
    let index: Int
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Step number
            Text("\(index)")
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.semibold)
                .frame(width: 24)
                .foregroundColor(.white)
                .background(Circle().fill(Color.forRunStatus(step.status)))

            // Action type badge
            ActionTypeBadge(actionType: step.action)

            // Step name
            VStack(alignment: .leading, spacing: 2) {
                Text(step.stepName ?? step.action)
                    .font(.body)
                    .lineLimit(1)

                if let errorMsg = step.errorMessage, !errorMsg.isEmpty {
                    Text(errorMsg)
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Duration
            if let durationMs = step.durationMs {
                Text(durationMs.durationDisplay)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Status icon
            Image(systemName: step.status.iconName)
                .foregroundColor(Color.forRunStatus(step.status))
        }
        .padding(12)
        .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

struct StepDetailContent: View {
    let step: StepResult
    @Binding var showScreenshotGallery: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Screenshot section
                if let screenshotPath = step.screenshotPath,
                   let image = NSImage.fromPath(screenshotPath) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Screenshot")
                                .font(.headline)
                            Spacer()
                            Button(action: { showScreenshotGallery.toggle() }) {
                                Label("Gallery", systemImage: "photo.fill")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                        }

                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 300)
                            .border(Color.gray.opacity(0.3))
                    }
                }


                // Error details
                if let errorMsg = step.errorMessage, !errorMsg.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Error")
                            .font(.headline)
                            .foregroundColor(.red)

                        Text(errorMsg)
                            .font(.caption)
                            .foregroundColor(.red)
                            .textSelection(.enabled)
                    }
                    .padding(12)
                    .background(Color.red.opacity(0.05))
                    .border(Color.red.opacity(0.2), width: 1)
                    .cornerRadius(6)
                }

                // Timing info
                VStack(alignment: .leading, spacing: 8) {
                    Text("Timing")
                        .font(.headline)

                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Started")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(step.startedAt.shortDisplay)
                                .font(.body)
                        }

                        Divider()

                        if let durationMs = step.durationMs {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Duration")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(durationMs.durationDisplay)
                                    .font(.body)
                            }
                        }
                    }
                }
                .padding(12)
                .background(Color(.controlBackgroundColor))
                .cornerRadius(6)
            }
            .padding(16)
        }
    }
}


struct StatusBadge: View {
    let status: RunStatus

    var body: some View {
        Label(status.rawValue.capitalized, systemImage: status.iconName)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.forRunStatus(status).opacity(0.15))
            .foregroundColor(Color.forRunStatus(status))
            .cornerRadius(4)
    }
}

struct StepCountBadge: View {
    let count: Int
    let status: RunStatus

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.iconName)
            Text("\(count)")
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.forRunStatus(status).opacity(0.15))
        .foregroundColor(Color.forRunStatus(status))
        .cornerRadius(4)
    }
}

struct ActionTypeBadge: View {
    let actionType: String

    var body: some View {
        Text(actionType.uppercased())
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.blue.opacity(0.15))
            .foregroundColor(.blue)
            .cornerRadius(3)
    }
}

#Preview {
    let run = WorkflowRun(
        id: 1,
        workflowId: "preview-workflow",
        workflowName: "Login Flow",
        status: .passed,
        startedAt: Date(),
        durationMs: 12500,
        totalSteps: 5,
        passedSteps: 5,
        failedSteps: 0,
        skippedSteps: 0
    )

    RunDetailView(run: run)
        .environmentObject(AppState())
        .frame(width: 1000, height: 600)
}

// MARK: - Extensions

extension RunStatus {
    var iconName: String {
        switch self {
        case .passed:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        case .running:
            return "hourglass.circle.fill"
        case .pending:
            return "circle"
        case .aborted:
            return "stop.circle.fill"
        case .skipped:
            return "circle.slash.fill"
        }
    }
}

