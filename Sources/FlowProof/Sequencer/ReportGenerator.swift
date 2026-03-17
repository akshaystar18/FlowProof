import Foundation

class ReportGenerator {
    let database: Database

    init(database: Database = Database.shared) {
        self.database = database
    }

    func generateHTMLReport(runId: Int64) throws -> String {
        guard let run = try database.fetchRun(byId: runId) else {
            throw NSError(domain: "ReportGenerator", code: -1, userInfo: [NSLocalizedDescriptionKey: "Workflow run not found"])
        }

        let stepResults = try database.fetchStepResults(forRunId: runId)

        let html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>FlowProof Test Report - \(run.workflowName)</title>
            <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
            <style>
                * {
                    margin: 0;
                    padding: 0;
                    box-sizing: border-box;
                }

                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', 'Oxygen', 'Ubuntu', 'Cantarell', 'Fira Sans', 'Droid Sans', 'Helvetica Neue', sans-serif;
                    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                    min-height: 100vh;
                    padding: 20px;
                }

                .container {
                    max-width: 1200px;
                    margin: 0 auto;
                    background: white;
                    border-radius: 12px;
                    box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3);
                    overflow: hidden;
                }

                .header {
                    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                    color: white;
                    padding: 40px;
                    text-align: center;
                }

                .header h1 {
                    font-size: 2.5em;
                    margin-bottom: 10px;
                }

                .header p {
                    font-size: 1.1em;
                    opacity: 0.9;
                }

                .summary {
                    display: grid;
                    grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
                    gap: 20px;
                    padding: 40px;
                    background: #f8f9fa;
                    border-bottom: 1px solid #e9ecef;
                }

                .summary-card {
                    text-align: center;
                    padding: 20px;
                    background: white;
                    border-radius: 8px;
                    border-left: 4px solid #667eea;
                }

                .summary-card.passed {
                    border-left-color: #28a745;
                }

                .summary-card.failed {
                    border-left-color: #dc3545;
                }

                .summary-card.skipped {
                    border-left-color: #ffc107;
                }

                .summary-card.aborted {
                    border-left-color: #6c757d;
                }

                .summary-value {
                    font-size: 2.5em;
                    font-weight: bold;
                    color: #667eea;
                    margin-bottom: 5px;
                }

                .summary-label {
                    font-size: 0.9em;
                    color: #6c757d;
                    text-transform: uppercase;
                    letter-spacing: 1px;
                }

                .timeline {
                    padding: 40px;
                }

                .timeline-title {
                    font-size: 1.8em;
                    color: #333;
                    margin-bottom: 30px;
                    border-bottom: 2px solid #667eea;
                    padding-bottom: 15px;
                }

                .step-item {
                    display: flex;
                    gap: 20px;
                    margin-bottom: 20px;
                    padding: 20px;
                    background: #f8f9fa;
                    border-radius: 8px;
                    border-left: 4px solid #e9ecef;
                }

                .step-item.passed {
                    border-left-color: #28a745;
                    background: rgba(40, 167, 69, 0.05);
                }

                .step-item.failed {
                    border-left-color: #dc3545;
                    background: rgba(220, 53, 69, 0.05);
                }

                .step-item.skipped {
                    border-left-color: #ffc107;
                    background: rgba(255, 193, 7, 0.05);
                }

                .step-item.aborted {
                    border-left-color: #6c757d;
                    background: rgba(108, 117, 125, 0.05);
                }

                .step-status {
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    min-width: 60px;
                    height: 60px;
                    border-radius: 50%;
                    font-weight: bold;
                    color: white;
                    font-size: 0.9em;
                }

                .step-status.passed {
                    background: #28a745;
                }

                .step-status.failed {
                    background: #dc3545;
                }

                .step-status.skipped {
                    background: #ffc107;
                }

                .step-status.aborted {
                    background: #6c757d;
                }

                .step-details {
                    flex: 1;
                }

                .step-name {
                    font-size: 1.1em;
                    font-weight: 600;
                    color: #333;
                    margin-bottom: 8px;
                }

                .step-action {
                    display: inline-block;
                    background: #667eea;
                    color: white;
                    padding: 4px 12px;
                    border-radius: 20px;
                    font-size: 0.85em;
                    margin-bottom: 8px;
                }

                .step-info {
                    font-size: 0.9em;
                    color: #6c757d;
                }

                .step-error {
                    margin-top: 12px;
                    padding: 12px;
                    background: #ffe5e5;
                    border-left: 3px solid #dc3545;
                    color: #721c24;
                    border-radius: 4px;
                    font-size: 0.9em;
                }

                .step-screenshot {
                    margin-top: 12px;
                }

                .step-screenshot img {
                    max-width: 300px;
                    max-height: 300px;
                    border-radius: 4px;
                    border: 1px solid #ddd;
                }

                .chart-container {
                    padding: 40px;
                    background: #f8f9fa;
                    border-bottom: 1px solid #e9ecef;
                }

                .chart-title {
                    font-size: 1.5em;
                    color: #333;
                    margin-bottom: 30px;
                    text-align: center;
                }

                .chart-grid {
                    display: grid;
                    grid-template-columns: repeat(auto-fit, minmax(400px, 1fr));
                    gap: 30px;
                }

                .chart-box {
                    background: white;
                    padding: 20px;
                    border-radius: 8px;
                    box-shadow: 0 2px 8px rgba(0, 0, 0, 0.1);
                }

                .chart-box canvas {
                    max-height: 300px;
                }

                .footer {
                    padding: 30px;
                    background: #f8f9fa;
                    text-align: center;
                    color: #6c757d;
                    font-size: 0.9em;
                    border-top: 1px solid #e9ecef;
                }

                .footer-logo {
                    font-weight: bold;
                    color: #667eea;
                    margin-right: 10px;
                }

                @media (max-width: 768px) {
                    .header h1 {
                        font-size: 1.8em;
                    }

                    .summary {
                        grid-template-columns: 1fr;
                    }

                    .chart-grid {
                        grid-template-columns: 1fr;
                    }

                    .step-item {
                        flex-direction: column;
                    }
                }

                @media print {
                    body {
                        background: white;
                        padding: 0;
                    }

                    .container {
                        box-shadow: none;
                        border-radius: 0;
                    }

                    page-break-after: auto;
                }
            </style>
        </head>
        <body>
            <div class="container">
                <div class="header">
                    <h1>\(htmlEncode(run.workflowName))</h1>
                    <p>Test Execution Report</p>
                </div>

                <div class="summary">
                    <div class="summary-card passed">
                        <div class="summary-value">\(run.passedSteps)</div>
                        <div class="summary-label">Passed</div>
                    </div>
                    <div class="summary-card failed">
                        <div class="summary-value">\(run.failedSteps)</div>
                        <div class="summary-label">Failed</div>
                    </div>
                    <div class="summary-card skipped">
                        <div class="summary-value">\(run.skippedSteps)</div>
                        <div class="summary-label">Skipped</div>
                    </div>
                    <div class="summary-card \(run.status.rawValue)">
                        <div class="summary-value">\(run.status.rawValue.uppercased())</div>
                        <div class="summary-label">Status</div>
                    </div>
                </div>

                <div class="chart-container">
                    <div class="chart-title">Execution Metrics</div>
                    <div class="chart-grid">
                        <div class="chart-box">
                            <canvas id="statusChart"></canvas>
                        </div>
                        <div class="chart-box">
                            <canvas id="timingChart"></canvas>
                        </div>
                    </div>
                </div>

                <div class="timeline">
                    <div class="timeline-title">Step-by-Step Timeline</div>
                    \(generateStepsHTML(stepResults))
                </div>

                <div class="footer">
                    <span class="footer-logo">FlowProof</span> - Automated Workflow Testing
                    <br>
                    Report Generated: \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .medium))
                </div>
            </div>

            <script>
                const statusCtx = document.getElementById('statusChart').getContext('2d');
                const statusChart = new Chart(statusCtx, {
                    type: 'doughnut',
                    data: {
                        labels: ['Passed', 'Failed', 'Skipped'],
                        datasets: [{
                            data: [\(run.passedSteps), \(run.failedSteps), \(run.skippedSteps)],
                            backgroundColor: ['#28a745', '#dc3545', '#ffc107'],
                            borderColor: '#fff',
                            borderWidth: 2
                        }]
                    },
                    options: {
                        responsive: true,
                        maintainAspectRatio: true,
                        plugins: {
                            legend: {
                                position: 'bottom'
                            }
                        }
                    }
                });

                const timingCtx = document.getElementById('timingChart').getContext('2d');
                const timingChart = new Chart(timingCtx, {
                    type: 'bar',
                    data: {
                        labels: ['Total Duration'],
                        datasets: [{
                            label: 'Execution Time (ms)',
                            data: [\(run.durationMs ?? 0)],
                            backgroundColor: '#667eea',
                            borderColor: '#667eea',
                            borderWidth: 1
                        }]
                    },
                    options: {
                        responsive: true,
                        maintainAspectRatio: true,
                        indexAxis: 'y',
                        plugins: {
                            legend: {
                                display: true,
                                position: 'top'
                            }
                        },
                        scales: {
                            x: {
                                beginAtZero: true
                            }
                        }
                    }
                });
            </script>
        </body>
        </html>
        """

        return html
    }

    func generateSummaryHTML(workflowId: String, limit: Int = 20) throws -> String {
        let runs = try database.fetchLatestRunsForWorkflow(workflowId: workflowId, limit: limit)

        let totalRuns = runs.count
        let passedRuns = runs.filter { $0.status == .passed }.count
        let failedRuns = runs.filter { $0.status == .failed }.count
        let averageDuration = try database.averageDurationForWorkflow(workflowId: workflowId) ?? 0

        let html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>FlowProof Summary Report</title>
            <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
            <style>
                * {
                    margin: 0;
                    padding: 0;
                    box-sizing: border-box;
                }

                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', 'Oxygen', 'Ubuntu', 'Cantarell', 'Fira Sans', 'Droid Sans', 'Helvetica Neue', sans-serif;
                    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                    min-height: 100vh;
                    padding: 20px;
                }

                .container {
                    max-width: 1200px;
                    margin: 0 auto;
                    background: white;
                    border-radius: 12px;
                    box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3);
                    overflow: hidden;
                }

                .header {
                    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                    color: white;
                    padding: 40px;
                    text-align: center;
                }

                .header h1 {
                    font-size: 2.5em;
                    margin-bottom: 10px;
                }

                .metrics {
                    display: grid;
                    grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
                    gap: 20px;
                    padding: 40px;
                    background: #f8f9fa;
                }

                .metric-card {
                    text-align: center;
                    padding: 20px;
                    background: white;
                    border-radius: 8px;
                    border-top: 4px solid #667eea;
                }

                .metric-value {
                    font-size: 2.5em;
                    font-weight: bold;
                    color: #667eea;
                    margin-bottom: 5px;
                }

                .metric-label {
                    font-size: 0.9em;
                    color: #6c757d;
                    text-transform: uppercase;
                }

                .pass-rate {
                    font-size: 1.5em;
                    color: #28a745;
                    margin-top: 10px;
                }

                .runs-table {
                    padding: 40px;
                }

                .runs-title {
                    font-size: 1.8em;
                    color: #333;
                    margin-bottom: 20px;
                    border-bottom: 2px solid #667eea;
                    padding-bottom: 15px;
                }

                table {
                    width: 100%;
                    border-collapse: collapse;
                }

                thead {
                    background: #f8f9fa;
                }

                th {
                    padding: 15px;
                    text-align: left;
                    font-weight: 600;
                    color: #333;
                    border-bottom: 2px solid #e9ecef;
                }

                td {
                    padding: 12px 15px;
                    border-bottom: 1px solid #e9ecef;
                }

                tr:hover {
                    background: #f8f9fa;
                }

                .status-badge {
                    display: inline-block;
                    padding: 4px 12px;
                    border-radius: 20px;
                    font-size: 0.85em;
                    font-weight: 600;
                }

                .status-badge.passed {
                    background: rgba(40, 167, 69, 0.1);
                    color: #28a745;
                }

                .status-badge.failed {
                    background: rgba(220, 53, 69, 0.1);
                    color: #dc3545;
                }

                .status-badge.aborted {
                    background: rgba(108, 117, 125, 0.1);
                    color: #6c757d;
                }

                .footer {
                    padding: 30px;
                    background: #f8f9fa;
                    text-align: center;
                    color: #6c757d;
                    border-top: 1px solid #e9ecef;
                }

                @media (max-width: 768px) {
                    .header h1 {
                        font-size: 1.8em;
                    }

                    .metrics {
                        grid-template-columns: 1fr;
                    }

                    table {
                        font-size: 0.9em;
                    }
                }
            </style>
        </head>
        <body>
            <div class="container">
                <div class="header">
                    <h1>Test Summary Report</h1>
                    <p>Last \(limit) Workflow Runs</p>
                </div>

                <div class="metrics">
                    <div class="metric-card">
                        <div class="metric-value">\(totalRuns)</div>
                        <div class="metric-label">Total Runs</div>
                    </div>
                    <div class="metric-card">
                        <div class="metric-value">\(passedRuns)</div>
                        <div class="metric-label">Passed Runs</div>
                        <div class="pass-rate">\(totalRuns > 0 ? String(format: "%.1f%%", Double(passedRuns) / Double(totalRuns) * 100) : "0%")</div>
                    </div>
                    <div class="metric-card">
                        <div class="metric-value">\(failedRuns)</div>
                        <div class="metric-label">Failed Runs</div>
                    </div>
                    <div class="metric-card">
                        <div class="metric-value">\(averageDuration)</div>
                        <div class="metric-label">Avg Duration (ms)</div>
                    </div>
                </div>

                <div class="runs-table">
                    <div class="runs-title">Recent Runs</div>
                    <table>
                        <thead>
                            <tr>
                                <th>Run Date</th>
                                <th>Status</th>
                                <th>Passed/Total</th>
                                <th>Duration (ms)</th>
                            </tr>
                        </thead>
                        <tbody>
                            \(generateRunsTableRows(runs))
                        </tbody>
                    </table>
                </div>

                <div class="footer">
                    <strong>FlowProof</strong> - Automated Workflow Testing Summary
                    <br>
                    Generated: \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .medium))
                </div>
            </div>
        </body>
        </html>
        """

        return html
    }

    func saveReport(_ html: String, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        try html.write(to: url, atomically: true, encoding: .utf8)
    }

    private func generateStepsHTML(_ stepResults: [StepResult]) -> String {
        return stepResults.map { step in
            let statusClass = step.status.rawValue
            let statusDisplay = step.status.rawValue.uppercased()

            var html = """
            <div class="step-item \(statusClass)">
                <div class="step-status \(statusClass)">\(String(statusDisplay.prefix(1)))</div>
                <div class="step-details">
                    <div class="step-name">\(htmlEncode(step.stepName ?? "Step \(step.stepIndex)"))</div>
                    <span class="step-action">\(htmlEncode(step.action))</span>
                    <div class="step-info">Duration: \(step.durationMs ?? 0)ms</div>
            """

            if let errorMessage = step.errorMessage {
                html += """
                    <div class="step-error">\(htmlEncode(errorMessage))</div>
                """
            }

            if let screenshotPath = step.screenshotPath, FileManager.default.fileExists(atPath: screenshotPath) {
                html += """
                    <div class="step-screenshot">
                        <img src="\(htmlEncode(screenshotPath))" alt="Step screenshot">
                    </div>
                """
            }

            html += """
                </div>
            </div>
            """

            return html
        }.joined(separator: "\n")
    }

    private func generateRunsTableRows(_ runs: [WorkflowRun]) -> String {
        return runs.map { run in
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .short
            dateFormatter.timeStyle = .short
            let dateString = dateFormatter.string(from: run.startedAt)

            let statusClass = run.status.rawValue
            let statusDisplay = run.status.rawValue.uppercased()

            return """
            <tr>
                <td>\(dateString)</td>
                <td><span class="status-badge \(statusClass)">\(statusDisplay)</span></td>
                <td>\(run.passedSteps)/\(run.totalSteps)</td>
                <td>\(run.durationMs ?? 0)</td>
            </tr>
            """
        }.joined(separator: "\n")
    }

    private func htmlEncode(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
