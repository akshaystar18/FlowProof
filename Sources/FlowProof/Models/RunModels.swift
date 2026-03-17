import Foundation
import GRDB

// MARK: - RunStatus
enum RunStatus: String, Codable, DatabaseValueConvertible {
    case pending, running, passed, failed, aborted, skipped

    var databaseValue: DatabaseValue {
        rawValue.databaseValue
    }

    static func fromDatabaseValue(_ value: DatabaseValue) -> RunStatus? {
        guard let rawValue = String.fromDatabaseValue(value) else { return nil }
        return RunStatus(rawValue: rawValue)
    }
}

// MARK: - WorkflowRun
struct WorkflowRun: Codable, Identifiable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var workflowId: String
    var workflowName: String
    var status: RunStatus
    var startedAt: Date
    var endedAt: Date?
    var durationMs: Int64?
    var totalSteps: Int
    var passedSteps: Int
    var failedSteps: Int
    var skippedSteps: Int
    var errorMessage: String?

    static var databaseTableName = "workflow_runs"

    enum Columns: String, ColumnExpression {
        case id
        case workflowId = "workflow_id"
        case workflowName = "workflow_name"
        case status
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case durationMs = "duration_ms"
        case totalSteps = "total_steps"
        case passedSteps = "passed_steps"
        case failedSteps = "failed_steps"
        case skippedSteps = "skipped_steps"
        case errorMessage = "error_message"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case workflowId = "workflow_id"
        case workflowName = "workflow_name"
        case status
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case durationMs = "duration_ms"
        case totalSteps = "total_steps"
        case passedSteps = "passed_steps"
        case failedSteps = "failed_steps"
        case skippedSteps = "skipped_steps"
        case errorMessage = "error_message"
    }

    init(
        id: Int64? = nil,
        workflowId: String,
        workflowName: String,
        status: RunStatus,
        startedAt: Date,
        endedAt: Date? = nil,
        durationMs: Int64? = nil,
        totalSteps: Int,
        passedSteps: Int,
        failedSteps: Int,
        skippedSteps: Int,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.workflowId = workflowId
        self.workflowName = workflowName
        self.status = status
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationMs = durationMs
        self.totalSteps = totalSteps
        self.passedSteps = passedSteps
        self.failedSteps = failedSteps
        self.skippedSteps = skippedSteps
        self.errorMessage = errorMessage
    }
}

// MARK: - StepResult
struct StepResult: Codable, Identifiable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var runId: Int64
    var stepIndex: Int
    var stepName: String?
    var action: String
    var status: RunStatus
    var startedAt: Date
    var endedAt: Date?
    var durationMs: Int64?
    var screenshotPath: String?
    var errorMessage: String?
    var retryCount: Int

    static var databaseTableName = "step_results"

    enum Columns: String, ColumnExpression {
        case id
        case runId = "run_id"
        case stepIndex = "step_index"
        case stepName = "step_name"
        case action
        case status
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case durationMs = "duration_ms"
        case screenshotPath = "screenshot_path"
        case errorMessage = "error_message"
        case retryCount = "retry_count"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case runId = "run_id"
        case stepIndex = "step_index"
        case stepName = "step_name"
        case action
        case status
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case durationMs = "duration_ms"
        case screenshotPath = "screenshot_path"
        case errorMessage = "error_message"
        case retryCount = "retry_count"
    }

    init(
        id: Int64? = nil,
        runId: Int64,
        stepIndex: Int,
        stepName: String? = nil,
        action: String,
        status: RunStatus,
        startedAt: Date,
        endedAt: Date? = nil,
        durationMs: Int64? = nil,
        screenshotPath: String? = nil,
        errorMessage: String? = nil,
        retryCount: Int = 0
    ) {
        self.id = id
        self.runId = runId
        self.stepIndex = stepIndex
        self.stepName = stepName
        self.action = action
        self.status = status
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationMs = durationMs
        self.screenshotPath = screenshotPath
        self.errorMessage = errorMessage
        self.retryCount = retryCount
    }
}

// MARK: - AssertionResult
struct AssertionResult: Codable, Identifiable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var stepResultId: Int64
    var assertionType: String
    var expected: String?
    var actual: String?
    var passed: Bool
    var message: String?

    static var databaseTableName = "assertion_results"

    enum Columns: String, ColumnExpression {
        case id
        case stepResultId = "step_result_id"
        case assertionType = "assertion_type"
        case expected
        case actual
        case passed
        case message
    }

    enum CodingKeys: String, CodingKey {
        case id
        case stepResultId = "step_result_id"
        case assertionType = "assertion_type"
        case expected
        case actual
        case passed
        case message
    }

    init(
        id: Int64? = nil,
        stepResultId: Int64,
        assertionType: String,
        expected: String? = nil,
        actual: String? = nil,
        passed: Bool,
        message: String? = nil
    ) {
        self.id = id
        self.stepResultId = stepResultId
        self.assertionType = assertionType
        self.expected = expected
        self.actual = actual
        self.passed = passed
        self.message = message
    }
}

// MARK: - Baseline
struct Baseline: Codable, Identifiable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var workflowId: String
    var stepIndex: Int
    var screenshotPath: String
    var createdAt: Date

    static var databaseTableName = "baselines"

    enum Columns: String, ColumnExpression {
        case id
        case workflowId = "workflow_id"
        case stepIndex = "step_index"
        case screenshotPath = "screenshot_path"
        case createdAt = "created_at"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case workflowId = "workflow_id"
        case stepIndex = "step_index"
        case screenshotPath = "screenshot_path"
        case createdAt = "created_at"
    }

    init(
        id: Int64? = nil,
        workflowId: String,
        stepIndex: Int,
        screenshotPath: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.workflowId = workflowId
        self.stepIndex = stepIndex
        self.screenshotPath = screenshotPath
        self.createdAt = createdAt
    }
}

// MARK: - WorkflowSchedule
struct WorkflowSchedule: Codable, Identifiable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var workflowId: String
    var cronExpression: String?
    var enabled: Bool
    var lastRunAt: Date?
    var nextRunAt: Date?

    static var databaseTableName = "schedules"

    enum Columns: String, ColumnExpression {
        case id
        case workflowId = "workflow_id"
        case cronExpression = "cron_expression"
        case enabled
        case lastRunAt = "last_run_at"
        case nextRunAt = "next_run_at"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case workflowId = "workflow_id"
        case cronExpression = "cron_expression"
        case enabled
        case lastRunAt = "last_run_at"
        case nextRunAt = "next_run_at"
    }

    init(
        id: Int64? = nil,
        workflowId: String,
        cronExpression: String? = nil,
        enabled: Bool = false,
        lastRunAt: Date? = nil,
        nextRunAt: Date? = nil
    ) {
        self.id = id
        self.workflowId = workflowId
        self.cronExpression = cronExpression
        self.enabled = enabled
        self.lastRunAt = lastRunAt
        self.nextRunAt = nextRunAt
    }
}
