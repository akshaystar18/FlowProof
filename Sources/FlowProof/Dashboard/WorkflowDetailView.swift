import SwiftUI

// MARK: - Workflow Detail View

struct WorkflowDetailView: View {
    let entry: WorkflowEntry
    @EnvironmentObject var appState: AppState
    @State private var runs: [WorkflowRun] = []
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.workflow.name)
                        .font(.title)
                        .fontWeight(.bold)
                    HStack(spacing: 12) {
                        Label(entry.workflow.targetApp.name, systemImage: "app.fill")
                        Label("\(entry.workflow.steps.count) steps", systemImage: "list.number")
                        if let timeout = entry.workflow.timeout {
                            Label("\(Int(timeout))s timeout", systemImage: "clock")
                        }
                        Label("v\(entry.workflow.version)", systemImage: "tag")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                Spacer()

                // Pass rate badge
                PassRateBadge(rate: entry.passRate)

                Button(action: { appState.runWorkflow(entry) }) {
                    Label("Run", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(appState.isRunning)
            }
            .padding(20)

            Divider()

            // Tabs
            Picker("Tab", selection: $selectedTab) {
                Text("Steps").tag(0)
                Text("Run History").tag(1)
                Text("Configuration").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)

            // Tab content
            switch selectedTab {
            case 0:
                StepsListView(steps: entry.workflow.steps)
            case 1:
                WorkflowRunsView(runs: runs)
            case 2:
                WorkflowConfigView(workflow: entry.workflow)
            default:
                EmptyView()
            }
        }
        .onAppear {
            runs = (try? appState.database.fetchLatestRunsForWorkflow(workflowId: entry.workflow.id.uuidString, limit: 20)) ?? []
        }
    }
}

// MARK: - Steps List

struct StepsListView: View {
    let steps: [WorkflowStep]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    StepRowView(index: index, step: step)
                }
            }
            .padding(16)
        }
    }
}

struct StepRowView: View {
    let index: Int
    let step: WorkflowStep

    var body: some View {
        HStack(spacing: 12) {
            // Step number
            Text("\(index + 1)")
                .font(.system(.body, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(actionColor)
                .cornerRadius(6)

            VStack(alignment: .leading, spacing: 2) {
                Text(step.name ?? "\(step.action.rawValue) action")
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    Text(step.action.rawValue.uppercased())
                        .font(.system(.caption2, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(actionColor.opacity(0.15))
                        .foregroundColor(actionColor)
                        .cornerRadius(3)

                    if let target = step.target {
                        Text(targetDescription(target))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let timeout = step.timeout {
                        Label("\(Int(timeout))s", systemImage: "clock")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
    }

    private var actionColor: Color {
        switch step.action {
        case .click: return .blue
        case .type, .key: return .purple
        case .wait: return .orange
        case .assert: return .green
        case .screenshot: return .indigo
        case .launch: return .teal
        case .drag, .scroll: return .cyan
        case .upload, .download: return .brown
        case .conditional, .loop: return .pink
        case .subWorkflow, .setVariable: return .gray
        case .clipboard, .menu: return .gray
        }
    }

    private func targetDescription(_ target: ElementTarget) -> String {
        if let ax = target.accessibility {
            var parts: [String] = []
            if let role = ax.role { parts.append("role: \(role)") }
            if let label = ax.label { parts.append("label: \"\(label)\"") }
            return "AX(\(parts.joined(separator: ", ")))"
        }
        if let text = target.textOcr {
            return "OCR(\"\(text)\")"
        }
        if let img = target.imageMatch {
            return "Image(\(img.template))"
        }
        if let coords = target.coordinates {
            return "(\(Int(coords.x)), \(Int(coords.y)))"
        }
        return "hybrid"
    }
}

// MARK: - Workflow Runs

struct WorkflowRunsView: View {
    let runs: [WorkflowRun]

    var body: some View {
        ScrollView {
            if runs.isEmpty {
                EmptyStateView(icon: "clock", title: "No runs yet", message: "Run this workflow to see results here")
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(runs, id: \.id) { run in
                        RunRowView(run: run)
                    }
                }
                .padding(16)
            }
        }
    }
}

// MARK: - Config View

struct WorkflowConfigView: View {
    let workflow: Workflow

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                configSection("General") {
                    configRow("Name", workflow.name)
                    configRow("Version", workflow.version)
                    configRow("Timeout", workflow.timeout.map { "\(Int($0))s" } ?? "300s (default)")
                    configRow("On Failure", workflow.onFailure?.rawValue ?? "abort (default)")
                }

                configSection("Target Application") {
                    configRow("App Name", workflow.targetApp.name)
                    configRow("Bundle ID", workflow.targetApp.bundleId ?? "N/A")
                    configRow("Auto Launch", workflow.targetApp.launch == true ? "Yes" : "No")
                }

                if let vars = workflow.variables, !vars.isEmpty {
                    configSection("Variables") {
                        ForEach(Array(vars.keys.sorted()), id: \.self) { key in
                            configRow("${\(key)}", vars[key] ?? "")
                        }
                    }
                }

                configSection("Steps") {
                    configRow("Setup", "\(workflow.setup?.count ?? 0) steps")
                    configRow("Main", "\(workflow.steps.count) steps")
                    configRow("Teardown", "\(workflow.teardown?.count ?? 0) steps")
                }
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private func configSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            VStack(spacing: 0) {
                content()
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    private func configRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 140, alignment: .trailing)
            Text(value)
                .fontWeight(.medium)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

