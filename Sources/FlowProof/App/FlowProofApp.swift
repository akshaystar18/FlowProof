import SwiftUI

@main
struct FlowProofApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Import Workflow...") {
                    appState.showImportPanel = true
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("New Workflow") {
                    appState.showNewWorkflow = true
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

// MARK: - App State

@MainActor
class AppState: ObservableObject {
    @Published var workflows: [WorkflowEntry] = []
    @Published var selectedWorkflow: WorkflowEntry?
    @Published var selectedRun: WorkflowRun?
    @Published var isRunning = false
    @Published var showImportPanel = false
    @Published var showNewWorkflow = false
    @Published var sidebarSelection: SidebarItem? = .dashboard

    let database: DatabaseManager
    let runner: WorkflowRunner

    init() {
        let dbPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("FlowProof", isDirectory: true)
        try? FileManager.default.createDirectory(at: dbPath, withIntermediateDirectories: true)
        self.database = try! DatabaseManager(path: dbPath.appendingPathComponent("flowproof.db").path)
        self.runner = WorkflowRunner(database: database)
    }

    func loadWorkflows() {
        // Scan workflows directory for YAML files
        let workflowsDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("FlowProof/Workflows", isDirectory: true)
        try? FileManager.default.createDirectory(at: workflowsDir, withIntermediateDirectories: true)

        let files = (try? FileManager.default.contentsOfDirectory(at: workflowsDir, includingPropertiesForKeys: nil))?.filter {
            $0.pathExtension == "yaml" || $0.pathExtension == "yml" || $0.pathExtension == "json"
        } ?? []

        workflows = files.compactMap { url in
            guard let workflow = try? WorkflowParser.parse(from: url) else { return nil }
            let runs = (try? database.fetchRunsForWorkflow(workflowId: workflow.id.uuidString, limit: 1)) ?? []
            let lastRun = runs.first
            return WorkflowEntry(
                workflow: workflow,
                fileURL: url,
                lastRun: lastRun,
                passRate: calculatePassRate(workflowId: workflow.id.uuidString)
            )
        }
    }

    func importWorkflow(from url: URL) throws {
        let workflowsDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("FlowProof/Workflows", isDirectory: true)
        try? FileManager.default.createDirectory(at: workflowsDir, withIntermediateDirectories: true)
        let dest = workflowsDir.appendingPathComponent(url.lastPathComponent)
        try FileManager.default.copyItem(at: url, to: dest)
        loadWorkflows()
    }

    func runWorkflow(_ entry: WorkflowEntry) {
        guard !isRunning else { return }
        isRunning = true

        Task {
            do {
                let run = try await runner.run(workflow: entry.workflow)
                await MainActor.run {
                    self.selectedRun = run
                    self.isRunning = false
                    self.loadWorkflows()
                }
            } catch {
                await MainActor.run {
                    self.isRunning = false
                }
            }
        }
    }

    private func calculatePassRate(workflowId: String) -> Double {
        let total = (try? database.countRunsForWorkflow(workflowId: workflowId)) ?? 0
        guard total > 0 else { return 0 }
        let passed = (try? database.countPassedRunsForWorkflow(workflowId: workflowId)) ?? 0
        return Double(passed) / Double(total)
    }
}

// MARK: - Supporting Types

struct WorkflowEntry: Identifiable {
    let id = UUID()
    let workflow: Workflow
    let fileURL: URL
    let lastRun: WorkflowRun?
    let passRate: Double
}

enum SidebarItem: Hashable {
    case dashboard
    case workflows
    case history
    case recorder
    case settings
    case workflow(UUID)
    case runDetail(Int64)
}
