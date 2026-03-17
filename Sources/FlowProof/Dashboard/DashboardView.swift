import SwiftUI

// MARK: - Dashboard View

struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @State private var recentRuns: [WorkflowRun] = []
    @State private var totalWorkflows = 0
    @State private var totalRuns = 0
    @State private var overallPassRate: Double = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack {
                    VStack(alignment: .leading) {
                        Text("FlowProof Dashboard")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Text("Automated Workflow Testing")
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if appState.isRunning {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Running...")
                            .foregroundColor(.blue)
                    }
                }
                .padding(.bottom, 8)

                // Summary Cards
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4), spacing: 16) {
                    SummaryCard(title: "Workflows", value: "\(totalWorkflows)", icon: "doc.text.fill", color: .blue)
                    SummaryCard(title: "Total Runs", value: "\(totalRuns)", icon: "play.circle.fill", color: .purple)
                    SummaryCard(title: "Pass Rate", value: "\(Int(overallPassRate * 100))%", icon: "checkmark.seal.fill", color: overallPassRate >= 0.8 ? .green : .orange)
                    SummaryCard(title: "Active", value: appState.isRunning ? "1" : "0", icon: "bolt.fill", color: appState.isRunning ? .green : .secondary)
                }

                // Accessibility Warning
                if !AccessibilityEngine.isAccessibilityEnabled() {
                    AccessibilityWarningBanner()
                }

                // Recent Runs
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recent Runs")
                        .font(.title2)
                        .fontWeight(.semibold)

                    if recentRuns.isEmpty {
                        EmptyStateView(
                            icon: "play.slash",
                            title: "No runs yet",
                            message: "Import a workflow and hit Run to get started"
                        )
                    } else {
                        ForEach(recentRuns, id: \.id) { run in
                            RunRowView(run: run)
                                .onTapGesture {
                                    appState.selectedRun = run
                                }
                        }
                    }
                }

                // Quick Actions
                VStack(alignment: .leading, spacing: 12) {
                    Text("Quick Actions")
                        .font(.title2)
                        .fontWeight(.semibold)

                    HStack(spacing: 16) {
                        QuickActionButton(title: "Import Workflow", icon: "square.and.arrow.down", color: .blue) {
                            appState.showImportPanel = true
                        }
                        QuickActionButton(title: "Run All", icon: "play.fill", color: .green) {
                            // Run all workflows sequentially
                        }
                        QuickActionButton(title: "View Reports", icon: "chart.bar.doc.horizontal", color: .purple) {
                            appState.sidebarSelection = .history
                        }
                    }
                }
            }
            .padding(24)
        }
        .onAppear { refreshStats() }
    }

    private func refreshStats() {
        totalWorkflows = appState.workflows.count
        recentRuns = (try? appState.database.fetchLatestRuns(limit: 10)) ?? []
        totalRuns = recentRuns.count
        let passed = recentRuns.filter { $0.status == .passed }.count
        overallPassRate = totalRuns > 0 ? Double(passed) / Double(totalRuns) : 0
    }
}

