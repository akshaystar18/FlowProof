import Foundation
import GRDB

typealias DatabaseManager = Database

class Database {
    static let shared = Database()

    private let dbQueue: DatabaseQueue

    private init() {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dbURL = documentsDirectory.appendingPathComponent("flowproof.db")

        do {
            self.dbQueue = try DatabaseQueue(path: dbURL.path)
            try self.createTables()
        } catch {
            fatalError("Failed to initialize database: \(error)")
        }
    }

    /// Initialize with a specific path (for AppState and CLI usage)
    init(path: String) throws {
        self.dbQueue = try DatabaseQueue(path: path)
        try self.createTables()
    }

    // MARK: - Table Creation

    private func createTables() throws {
        try dbQueue.write { db in
            // workflow_runs table
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS workflow_runs (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    workflow_id TEXT NOT NULL,
                    workflow_name TEXT NOT NULL,
                    status TEXT NOT NULL,
                    started_at DATETIME NOT NULL,
                    ended_at DATETIME,
                    duration_ms INTEGER,
                    total_steps INTEGER NOT NULL,
                    passed_steps INTEGER NOT NULL,
                    failed_steps INTEGER NOT NULL,
                    skipped_steps INTEGER NOT NULL,
                    error_message TEXT,
                    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
                )
                """)

            // step_results table
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS step_results (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    run_id INTEGER NOT NULL,
                    step_index INTEGER NOT NULL,
                    step_name TEXT,
                    action TEXT NOT NULL,
                    status TEXT NOT NULL,
                    started_at DATETIME NOT NULL,
                    ended_at DATETIME,
                    duration_ms INTEGER,
                    screenshot_path TEXT,
                    error_message TEXT,
                    retry_count INTEGER DEFAULT 0,
                    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                    FOREIGN KEY (run_id) REFERENCES workflow_runs(id) ON DELETE CASCADE
                )
                """)

            // assertion_results table
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS assertion_results (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    step_result_id INTEGER NOT NULL,
                    assertion_type TEXT NOT NULL,
                    expected TEXT,
                    actual TEXT,
                    passed INTEGER NOT NULL,
                    message TEXT,
                    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                    FOREIGN KEY (step_result_id) REFERENCES step_results(id) ON DELETE CASCADE
                )
                """)

            // baselines table
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS baselines (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    workflow_id TEXT NOT NULL,
                    step_index INTEGER NOT NULL,
                    screenshot_path TEXT NOT NULL,
                    created_at DATETIME NOT NULL,
                    UNIQUE(workflow_id, step_index)
                )
                """)

            // schedules table
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS schedules (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    workflow_id TEXT NOT NULL UNIQUE,
                    cron_expression TEXT,
                    enabled INTEGER DEFAULT 0,
                    last_run_at DATETIME,
                    next_run_at DATETIME,
                    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
                )
                """)

            // Create indexes for common queries
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_workflow_runs_workflow_id
                ON workflow_runs(workflow_id)
                """)

            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_workflow_runs_status
                ON workflow_runs(status)
                """)

            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_workflow_runs_started_at
                ON workflow_runs(started_at DESC)
                """)

            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_step_results_run_id
                ON step_results(run_id)
                """)

            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_assertion_results_step_result_id
                ON assertion_results(step_result_id)
                """)

            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_baselines_workflow_id
                ON baselines(workflow_id)
                """)
        }
    }

    // MARK: - Query Helpers

    func insertRun(_ run: inout WorkflowRun) throws -> WorkflowRun {
        try dbQueue.write { db in
            try run.insert(db)
        }
        return run
    }

    func updateRun(_ run: WorkflowRun) throws {
        try dbQueue.write { db in
            try run.update(db)
        }
    }

    func insertStepResult(_ result: inout StepResult) throws -> StepResult {
        try dbQueue.write { db in
            try result.insert(db)
        }
        return result
    }

    func updateStepResult(_ result: StepResult) throws {
        try dbQueue.write { db in
            try result.update(db)
        }
    }

    func insertAssertionResult(_ result: inout AssertionResult) throws {
        try dbQueue.write { db in
            try result.insert(db)
        }
    }

    func insertBaseline(_ baseline: inout Baseline) throws {
        try dbQueue.write { db in
            try baseline.insert(db)
        }
    }

    func fetchRunsForWorkflow(workflowId: String, limit: Int = 50) throws -> [WorkflowRun] {
        try dbQueue.read { db in
            try WorkflowRun
                .filter(WorkflowRun.Columns.workflowId == workflowId)
                .order(WorkflowRun.Columns.startedAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func fetchLatestRuns(limit: Int = 20) throws -> [WorkflowRun] {
        try dbQueue.read { db in
            try WorkflowRun
                .order(WorkflowRun.Columns.startedAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func fetchLatestRunsForWorkflow(workflowId: String, limit: Int = 10) throws -> [WorkflowRun] {
        try dbQueue.read { db in
            try WorkflowRun
                .filter(WorkflowRun.Columns.workflowId == workflowId)
                .order(WorkflowRun.Columns.startedAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func fetchStepResults(forRunId runId: Int64) throws -> [StepResult] {
        try dbQueue.read { db in
            try StepResult
                .filter(StepResult.Columns.runId == runId)
                .order(StepResult.Columns.stepIndex.asc)
                .fetchAll(db)
        }
    }

    func fetchAssertionResults(forStepResultId stepResultId: Int64) throws -> [AssertionResult] {
        try dbQueue.read { db in
            try AssertionResult
                .filter(AssertionResult.Columns.stepResultId == stepResultId)
                .fetchAll(db)
        }
    }

    func fetchRun(byId id: Int64) throws -> WorkflowRun? {
        try dbQueue.read { db in
            try WorkflowRun.fetchOne(db, key: id)
        }
    }

    func fetchStepResult(byId id: Int64) throws -> StepResult? {
        try dbQueue.read { db in
            try StepResult.fetchOne(db, key: id)
        }
    }

    func fetchBaselines(forWorkflowId workflowId: String) throws -> [Baseline] {
        try dbQueue.read { db in
            try Baseline
                .filter(Baseline.Columns.workflowId == workflowId)
                .order(Baseline.Columns.stepIndex.asc)
                .fetchAll(db)
        }
    }

    func fetchBaseline(workflowId: String, stepIndex: Int) throws -> Baseline? {
        try dbQueue.read { db in
            try Baseline
                .filter(Baseline.Columns.workflowId == workflowId && Baseline.Columns.stepIndex == stepIndex)
                .fetchOne(db)
        }
    }

    func deleteBaseline(id: Int64) throws {
        try dbQueue.write { db in
            try Baseline.deleteOne(db, key: id)
        }
    }

    func deleteRun(id: Int64) throws {
        try dbQueue.write { db in
            try WorkflowRun.deleteOne(db, key: id)
        }
    }

    func fetchSchedule(forWorkflowId workflowId: String) throws -> WorkflowSchedule? {
        try dbQueue.read { db in
            try WorkflowSchedule
                .filter(WorkflowSchedule.Columns.workflowId == workflowId)
                .fetchOne(db)
        }
    }

    func insertSchedule(_ schedule: inout WorkflowSchedule) throws {
        try dbQueue.write { db in
            try schedule.insert(db)
        }
    }

    func updateSchedule(_ schedule: WorkflowSchedule) throws {
        try dbQueue.write { db in
            try schedule.update(db)
        }
    }

    func fetchAllSchedules() throws -> [WorkflowSchedule] {
        try dbQueue.read { db in
            try WorkflowSchedule.fetchAll(db)
        }
    }

    func fetchEnabledSchedules() throws -> [WorkflowSchedule] {
        try dbQueue.read { db in
            try WorkflowSchedule
                .filter(WorkflowSchedule.Columns.enabled == true)
                .fetchAll(db)
        }
    }

    func fetchRunsWithStatus(_ status: RunStatus, limit: Int = 50) throws -> [WorkflowRun] {
        try dbQueue.read { db in
            try WorkflowRun
                .filter(WorkflowRun.Columns.status == status.rawValue)
                .order(WorkflowRun.Columns.startedAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func countRunsForWorkflow(workflowId: String) throws -> Int {
        try dbQueue.read { db in
            try WorkflowRun
                .filter(WorkflowRun.Columns.workflowId == workflowId)
                .fetchCount(db)
        }
    }

    func countPassedRunsForWorkflow(workflowId: String) throws -> Int {
        try dbQueue.read { db in
            try WorkflowRun
                .filter(WorkflowRun.Columns.workflowId == workflowId && WorkflowRun.Columns.status == RunStatus.passed.rawValue)
                .fetchCount(db)
        }
    }

    func countFailedRunsForWorkflow(workflowId: String) throws -> Int {
        try dbQueue.read { db in
            try WorkflowRun
                .filter(WorkflowRun.Columns.workflowId == workflowId && WorkflowRun.Columns.status == RunStatus.failed.rawValue)
                .fetchCount(db)
        }
    }

    func averageDurationForWorkflow(workflowId: String) throws -> Int64? {
        try dbQueue.read { db in
            try WorkflowRun
                .filter(WorkflowRun.Columns.workflowId == workflowId)
                .select(sql: "AVG(duration_ms) as avg_duration")
                .asRequest(of: Row.self)
                .fetchOne(db)
                .flatMap { row in row["avg_duration"] as? Int64 }
        }
    }

    func deleteOldRuns(olderThanDays days: Int) throws -> Int {
        let cutoffDate = Date().addingTimeInterval(-TimeInterval(days * 24 * 3600))

        return try dbQueue.write { db in
            try WorkflowRun
                .filter(WorkflowRun.Columns.startedAt < cutoffDate)
                .deleteAll(db)
        }
    }

    func clearDatabase() throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM assertion_results")
            try db.execute(sql: "DELETE FROM step_results")
            try db.execute(sql: "DELETE FROM workflow_runs")
            try db.execute(sql: "DELETE FROM baselines")
            try db.execute(sql: "DELETE FROM schedules")
        }
    }

    // MARK: - Raw Query Access

    func read<T>(_ block: @escaping (GRDB.Database) throws -> T) throws -> T {
        try dbQueue.read(block)
    }

    func write<T>(_ block: @escaping (GRDB.Database) throws -> T) throws -> T {
        try dbQueue.write(block)
    }
}
