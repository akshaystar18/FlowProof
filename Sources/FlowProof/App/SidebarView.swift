import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        List(selection: $appState.sidebarSelection) {
            Section("Overview") {
                Label("Dashboard", systemImage: "chart.bar.fill")
                    .tag(SidebarItem.dashboard)
                Label("All Workflows", systemImage: "list.bullet.rectangle")
                    .tag(SidebarItem.workflows)
                Label("Run History", systemImage: "clock.arrow.circlepath")
                    .tag(SidebarItem.history)
                Label("Recorder", systemImage: "record.circle")
                    .tag(SidebarItem.recorder)
            }

            Section("Workflows") {
                ForEach(appState.workflows) { entry in
                    HStack {
                        Image(systemName: statusIcon(for: entry))
                            .foregroundColor(statusColor(for: entry))
                        Text(entry.workflow.name)
                            .lineLimit(1)
                    }
                    .tag(SidebarItem.workflow(entry.workflow.id))
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
        .toolbar {
            ToolbarItem {
                Button(action: { appState.showImportPanel = true }) {
                    Image(systemName: "plus")
                }
                .help("Import Workflow")
            }
        }
    }

    private func statusIcon(for entry: WorkflowEntry) -> String {
        guard let run = entry.lastRun else { return "circle.dashed" }
        switch run.status {
        case .passed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .running: return "arrow.triangle.2.circlepath"
        default: return "circle.dashed"
        }
    }

    private func statusColor(for entry: WorkflowEntry) -> Color {
        guard let run = entry.lastRun else { return .secondary }
        switch run.status {
        case .passed: return .green
        case .failed: return .red
        case .running: return .blue
        default: return .secondary
        }
    }
}
