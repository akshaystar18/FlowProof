import SwiftUI

struct WorkflowListView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("All Workflows")
                        .font(.title)
                        .fontWeight(.bold)
                    Spacer()
                    Button(action: { appState.showImportPanel = true }) {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                }

                if appState.workflows.isEmpty {
                    EmptyStateView(icon: "doc.badge.plus", title: "No workflows", message: "Import a YAML or JSON workflow file to get started")
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(appState.workflows) { entry in
                            WorkflowCard(entry: entry)
                                .onTapGesture {
                                    appState.sidebarSelection = .workflow(entry.workflow.id)
                                }
                        }
                    }
                }
            }
            .padding(24)
        }
    }
}

struct WorkflowCard: View {
    let entry: WorkflowEntry
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.workflow.name)
                    .font(.headline)
                HStack(spacing: 8) {
                    Label(entry.workflow.targetApp.name, systemImage: "app")
                    Label("\(entry.workflow.steps.count) steps", systemImage: "list.number")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            PassRateBadge(rate: entry.passRate)

            Button(action: { appState.runWorkflow(entry) }) {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.small)
            .disabled(appState.isRunning)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }
}
