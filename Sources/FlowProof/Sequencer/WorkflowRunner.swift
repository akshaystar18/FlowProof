import AppKit
import Foundation

class WorkflowRunner: ObservableObject {
    let database: Database

    @Published var currentRun: WorkflowRun?
    @Published var stepResults: [StepResult] = []
    @Published var isRunning: Bool = false
    @Published var progress: Double = 0

    private var cancellationTask: Task<Void, Never>?
    private let locator: ElementLocator
    private let input: InputEngine
    private let accessibility: AccessibilityEngine
    private let vision: VisionEngine
    private let assertions: AssertionEngine
    private let executor: StepExecutor
    private var shouldCancel = false

    init(database: Database = Database.shared) {
        self.database = database

        self.accessibility = AccessibilityEngine()
        self.input = InputEngine()
        self.vision = VisionEngine()
        self.locator = ElementLocator(accessibility: accessibility, input: input, vision: vision)
        self.assertions = AssertionEngine(accessibilityEngine: accessibility, visionEngine: vision)
        self.executor = StepExecutor(
            locator: locator,
            input: input,
            accessibility: accessibility,
            vision: vision,
            assertions: assertions
        )
    }

    func run(workflow: Workflow) async throws -> WorkflowRun {
        shouldCancel = false
        DispatchQueue.main.async {
            self.isRunning = true
        }

        let runId = UUID().uuidString
        let screenshotDir = NSTemporaryDirectory() + "flowproof_\(runId)"
        try FileManager.default.createDirectory(atPath: screenshotDir, withIntermediateDirectories: true)

        let startTime = Date()
        var workflowRun = WorkflowRun(
            workflowId: workflow.id.uuidString,
            workflowName: workflow.name,
            status: .running,
            startedAt: startTime,
            totalSteps: workflow.steps.count,
            passedSteps: 0,
            failedSteps: 0,
            skippedSteps: 0
        )

        try database.insertRun(&workflowRun)

        guard let runDatabaseId = workflowRun.id else {
            throw NSError(domain: "WorkflowRunner", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create workflow run"])
        }

        DispatchQueue.main.async {
            self.currentRun = workflowRun
        }

        var context = ExecutionContext(
            variables: workflow.variables ?? [:],
            runId: runDatabaseId,
            screenshotDir: screenshotDir,
            stepStartTime: startTime,
            runStartTime: startTime,
            currentAppPid: 0
        )

        var targetAppPid: pid_t = 0
        let failureStrategy = workflow.onFailure ?? .abort

        do {
            if let targetApp = workflow.targetApp.launch == true ? workflow.targetApp : nil {
                targetAppPid = try await launchTargetApp(targetApp)
                context.currentAppPid = targetAppPid
            }

            if let setupSteps = workflow.setup, !shouldCancel {
                try await executeSetup(setupSteps, pid: targetAppPid, context: &context)
            }

            if !shouldCancel {
                try await executeSteps(
                    workflow.steps,
                    pid: targetAppPid,
                    context: &context,
                    failureStrategy: failureStrategy
                )
            }

            if let teardownSteps = workflow.teardown {
                try? await executeTeardown(teardownSteps, pid: targetAppPid, context: &context)
            }

            let endTime = Date()
            let duration = endTime.timeIntervalSince(startTime)

            workflowRun.status = (workflowRun.failedSteps == 0 && !shouldCancel) ? .passed : (shouldCancel ? .aborted : .failed)
            workflowRun.endedAt = endTime
            workflowRun.durationMs = Int64(duration * 1000)

            try database.updateRun(workflowRun)

            DispatchQueue.main.async {
                self.currentRun = workflowRun
                self.isRunning = false
                self.progress = 1.0
            }

            return workflowRun
        } catch {
            let endTime = Date()
            let duration = endTime.timeIntervalSince(startTime)

            workflowRun.status = .failed
            workflowRun.errorMessage = error.localizedDescription
            workflowRun.endedAt = endTime
            workflowRun.durationMs = Int64(duration * 1000)

            try database.updateRun(workflowRun)

            DispatchQueue.main.async {
                self.currentRun = workflowRun
                self.isRunning = false
            }

            throw error
        }
    }

    func cancel() {
        shouldCancel = true
        cancellationTask?.cancel()
    }

    private func executeSetup(_ steps: [WorkflowStep], pid: pid_t, context: inout ExecutionContext) async throws {
        for (index, step) in steps.enumerated() {
            if shouldCancel { break }

            let result = try await executor.execute(step: step, appPid: pid, context: &context)
            try saveStepResult(stepIndex: index, stepName: step.name, action: step.action.rawValue, status: result.status, runId: context.runId, screenshotPath: result.screenshotPath, errorMessage: result.errorMessage)

            if result.status == .failed {
                throw NSError(domain: "WorkflowRunner", code: -1, userInfo: [NSLocalizedDescriptionKey: "Setup failed: \(result.errorMessage ?? "Unknown error")"])
            }
        }
    }

    private func executeSteps(_ steps: [WorkflowStep], pid: pid_t, context: inout ExecutionContext, failureStrategy: FailureStrategy) async throws {
        let totalSteps = steps.count
        var passedCount = 0
        var failedCount = 0
        var skippedCount = 0

        for (index, step) in steps.enumerated() {
            if shouldCancel { break }

            if step.action == .conditional {
                try await handleConditional(step: step, pid: pid, context: &context)
            } else if step.action == .loop {
                try await handleLoop(step: step, pid: pid, context: &context)
            } else {
                let maxRetries = (failureStrategy == .retry) ? 3 : 0
                let result = try await handleRetry(step: step, pid: pid, context: &context, maxRetries: maxRetries)

                try saveStepResult(
                    stepIndex: index,
                    stepName: step.name,
                    action: step.action.rawValue,
                    status: result.status,
                    runId: context.runId,
                    screenshotPath: result.screenshotPath,
                    errorMessage: result.errorMessage
                )

                switch result.status {
                case .passed:
                    passedCount += 1
                case .failed:
                    failedCount += 1
                    switch failureStrategy {
                    case .abort:
                        throw NSError(domain: "WorkflowRunner", code: -1, userInfo: [NSLocalizedDescriptionKey: "Step failed: \(result.errorMessage ?? "Unknown error")"])
                    case .skip:
                        skippedCount += 1
                    case .retry:
                        failedCount += 1
                    }
                case .skipped:
                    skippedCount += 1
                default:
                    break
                }
            }

            DispatchQueue.main.async {
                self.progress = Double(index + 1) / Double(totalSteps)
            }
        }

        if var run = try database.fetchRun(byId: context.runId) {
            run.passedSteps = passedCount
            run.failedSteps = failedCount
            run.skippedSteps = skippedCount

            try database.updateRun(run)
            DispatchQueue.main.async {
                self.currentRun = run
            }
        }
    }

    private func executeTeardown(_ steps: [WorkflowStep], pid: pid_t, context: inout ExecutionContext) async {
        for (index, step) in steps.enumerated() {
            do {
                let result = try await executor.execute(step: step, appPid: pid, context: &context)
                try? saveStepResult(stepIndex: index, stepName: step.name, action: step.action.rawValue, status: result.status, runId: context.runId, screenshotPath: result.screenshotPath, errorMessage: result.errorMessage)
            } catch {
            }
        }
    }

    private func handleConditional(step: WorkflowStep, pid: pid_t, context: inout ExecutionContext) async throws {
        guard let ifCondition = step.ifCondition else {
            return
        }

        var conditionMet = false

        if let element = ifCondition.element {
            do {
                let located = try await locator.locate(element, in: pid)
                if ifCondition.state == "visible" {
                    conditionMet = true
                } else if ifCondition.state == "enabled" {
                    conditionMet = located.axElement != nil
                }
            } catch {
                conditionMet = false
            }
        } else if let text = ifCondition.text {
            let screenshot = try vision.captureWindow(pid: pid)
            let matches = try vision.findText(text, in: screenshot, matchMode: .contains)
            conditionMet = !matches.isEmpty
        }

        if conditionMet, let thenSteps = step.thenSteps {
            try await executeSteps(thenSteps, pid: pid, context: &context, failureStrategy: .abort)
        } else if !conditionMet, let elseSteps = step.elseSteps {
            try await executeSteps(elseSteps, pid: pid, context: &context, failureStrategy: .abort)
        }
    }

    private func handleLoop(step: WorkflowStep, pid: pid_t, context: inout ExecutionContext) async throws {
        guard let loopCount = step.count, let loopSteps = step.loopSteps else {
            return
        }

        for _ in 0..<loopCount {
            if shouldCancel { break }
            try await executeSteps(loopSteps, pid: pid, context: &context, failureStrategy: .abort)
        }
    }

    private func handleRetry(step: WorkflowStep, pid: pid_t, context: inout ExecutionContext, maxRetries: Int) async throws -> StepExecutionResult {
        var lastResult: StepExecutionResult?

        for attempt in 0...maxRetries {
            if shouldCancel {
                return StepExecutionResult(
                    stepIndex: 0,
                    stepName: step.name,
                    action: step.action.rawValue,
                    status: .aborted,
                    durationMs: 0,
                    screenshotPath: nil,
                    errorMessage: "Execution cancelled",
                    assertionEvaluation: nil,
                    retryCount: attempt
                )
            }

            let result = try await executor.execute(step: step, appPid: pid, context: &context)

            if result.status == .passed {
                return result
            }

            lastResult = result

            if attempt < maxRetries {
                try? await Task.sleep(for: .milliseconds(1000))
            }
        }

        return lastResult ?? StepExecutionResult(
            stepIndex: 0,
            stepName: step.name,
            action: step.action.rawValue,
            status: .failed,
            durationMs: 0,
            screenshotPath: nil,
            errorMessage: "Step failed after \(maxRetries) retries",
            assertionEvaluation: nil,
            retryCount: maxRetries
        )
    }

    private func captureStepScreenshot(pid: pid_t, stepIndex: Int, context: ExecutionContext) throws -> String? {
        let screenshot = try vision.captureWindow(pid: pid)

        let filename = String(format: "step_%d_%d.png", Int(context.runId), stepIndex)
        let screenshotPath = (context.screenshotDir as NSString).appendingPathComponent(filename)

        if let tiffRepresentation = screenshot.tiffRepresentation,
           let bitmapImage = NSBitmapImageRep(data: tiffRepresentation),
           let pngData = bitmapImage.representation(using: .png, properties: [:]) {
            try pngData.write(to: URL(fileURLWithPath: screenshotPath))
            return screenshotPath
        }

        return nil
    }

    private func launchTargetApp(_ targetApp: TargetApp) async throws -> pid_t {
        let workspace = NSWorkspace.shared

        guard let bundleId = targetApp.bundleId else {
            throw NSError(domain: "WorkflowRunner", code: -1, userInfo: [NSLocalizedDescriptionKey: "Target app bundle ID required"])
        }

        guard let appURL = workspace.urlForApplication(withBundleIdentifier: bundleId) else {
            throw NSError(domain: "WorkflowRunner", code: -1, userInfo: [NSLocalizedDescriptionKey: "No application found for bundle ID: \(bundleId)"])
        }

        let config = NSWorkspace.OpenConfiguration()

        return try await withCheckedThrowingContinuation { continuation in
            workspace.openApplication(at: appURL, configuration: config) { app, error in
                if let error = error {
                    continuation.resume(throwing: NSError(domain: "WorkflowRunner", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to launch app '\(targetApp.name)': \(error.localizedDescription)"]))
                } else if let app = app {
                    continuation.resume(returning: app.processIdentifier)
                } else {
                    continuation.resume(throwing: NSError(domain: "WorkflowRunner", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to launch app '\(targetApp.name)'"]))
                }
            }
        }
    }

    private func resolveVariablesInStep(_ step: WorkflowStep, resolver: VariableResolver.Type, context: ExecutionContext) -> WorkflowStep {
        var resolvedStep = step

        if let text = step.text {
            do {
                resolvedStep.text = try resolver.resolve(text, with: context.variables)
            } catch {
            }
        }

        if let expected = step.expected {
            do {
                resolvedStep.expected = try resolver.resolve(expected, with: context.variables)
            } catch {
            }
        }

        if let filePath = step.filePath {
            do {
                resolvedStep.filePath = try resolver.resolve(filePath, with: context.variables)
            } catch {
            }
        }

        return resolvedStep
    }

    private func saveStepResult(stepIndex: Int, stepName: String?, action: String, status: RunStatus, runId: Int64, screenshotPath: String?, errorMessage: String?) throws {
        var stepResult = StepResult(
            runId: runId,
            stepIndex: stepIndex,
            stepName: stepName,
            action: action,
            status: status,
            startedAt: Date(),
            endedAt: Date(),
            durationMs: 0,
            screenshotPath: screenshotPath,
            errorMessage: errorMessage,
            retryCount: 0
        )

        try database.insertStepResult(&stepResult)
    }
}

