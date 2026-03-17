import SwiftUI

struct RunHistoryView: View {
    @EnvironmentObject var appState: AppState
    @State private var runs: [WorkflowRun] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Run History")
                    .font(.title)
                    .fontWeight(.bold)

                if runs.isEmpty {
                    EmptyStateView(icon: "clock", title: "No history", message: "Run a workflow to see results here")
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(runs, id: \.id) { run in
                            RunRowView(run: run)
                        }
                    }
                }
            }
            .padding(24)
        }
        .onAppear {
            runs = (try? appState.database.fetchLatestRuns(limit: 50)) ?? []
        }
    }
}
