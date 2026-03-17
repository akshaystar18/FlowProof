import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            switch appState.sidebarSelection {
            case .dashboard:
                DashboardView()
            case .workflows:
                WorkflowListView()
            case .history:
                RunHistoryView()
            case .recorder:
                RecorderView()
            case .settings:
                SettingsView()
            case .workflow(let id):
                if let entry = appState.workflows.first(where: { $0.workflow.id == id }) {
                    WorkflowDetailView(entry: entry)
                } else {
                    Text("Workflow not found")
                        .foregroundColor(.secondary)
                }
            case .runDetail(let runId):
                if let run = appState.selectedRun, run.id == runId {
                    RunDetailView(run: run)
                } else {
                    Text("Run not found")
                        .foregroundColor(.secondary)
                }
            case nil:
                DashboardView()
            }
        }
        .onAppear {
            appState.loadWorkflows()
        }
        .fileImporter(
            isPresented: $appState.showImportPanel,
            allowedContentTypes: [.yaml, .json],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                for url in urls {
                    try? appState.importWorkflow(from: url)
                }
            }
        }
    }
}
