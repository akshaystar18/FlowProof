import XCTest
@testable import FlowProof

final class WorkflowModelTests: XCTestCase {

    // MARK: - ActionType

    func testAllActionTypesDecodable() throws {
        let actions = ["click", "drag", "type", "key", "scroll", "wait", "upload",
                       "download", "assert", "screenshot", "launch", "conditional",
                       "loop", "sub_workflow", "set_variable", "clipboard", "menu"]
        for action in actions {
            let data = "\"\(action)\"".data(using: .utf8)!
            let decoded = try JSONDecoder().decode(ActionType.self, from: data)
            XCTAssertEqual(decoded.rawValue, action, "Failed to decode action: \(action)")
        }
    }

    // MARK: - AssertionType

    func testAllAssertionTypesDecodable() throws {
        let types = ["screenshot_match", "pixel_diff", "region_compare",
                     "text_equals", "text_contains", "text_regex", "text_not_contains",
                     "element_visible", "element_enabled", "element_focused", "element_value",
                     "file_exists", "file_size", "file_content", "file_count",
                     "clipboard_contains", "notification_appeared", "process_running",
                     "step_duration_under", "total_duration_under"]
        for type in types {
            let data = "\"\(type)\"".data(using: .utf8)!
            let decoded = try JSONDecoder().decode(AssertionType.self, from: data)
            XCTAssertEqual(decoded.rawValue, type, "Failed to decode assertion: \(type)")
        }
    }

    // MARK: - FailureStrategy

    func testFailureStrategies() throws {
        for strategy in ["abort", "skip", "retry"] {
            let data = "\"\(strategy)\"".data(using: .utf8)!
            let decoded = try JSONDecoder().decode(FailureStrategy.self, from: data)
            XCTAssertEqual(decoded.rawValue, strategy)
        }
    }

    // MARK: - ScrollDirection

    func testScrollDirections() throws {
        for dir in ["up", "down", "left", "right"] {
            let data = "\"\(dir)\"".data(using: .utf8)!
            let decoded = try JSONDecoder().decode(ScrollDirection.self, from: data)
            XCTAssertEqual(decoded.rawValue, dir)
        }
    }

    // MARK: - RunStatus

    func testRunStatuses() throws {
        for status in ["pending", "running", "passed", "failed", "aborted", "skipped"] {
            let data = "\"\(status)\"".data(using: .utf8)!
            let decoded = try JSONDecoder().decode(RunStatus.self, from: data)
            XCTAssertEqual(decoded.rawValue, status)
        }
    }

    // MARK: - ElementTarget

    func testAccessibilityTargetDecoding() throws {
        let json = """
        {"accessibility": {"role": "button", "label": "OK"}}
        """
        let target = try JSONDecoder().decode(ElementTarget.self, from: json.data(using: .utf8)!)
        XCTAssertNotNil(target.accessibility)
        XCTAssertEqual(target.accessibility?.role, "button")
        XCTAssertEqual(target.accessibility?.label, "OK")
    }

    func testCoordinateTargetDecoding() throws {
        let json = """
        {"coordinates": {"x": 100.5, "y": 200.0}}
        """
        let target = try JSONDecoder().decode(ElementTarget.self, from: json.data(using: .utf8)!)
        XCTAssertNotNil(target.coordinates)
        XCTAssertEqual(target.coordinates?.x, 100.5)
        XCTAssertEqual(target.coordinates?.y, 200.0)
    }

    func testTextOcrTargetDecoding() throws {
        let json = """
        {"text_ocr": "Submit"}
        """
        let target = try JSONDecoder().decode(ElementTarget.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(target.textOcr, "Submit")
    }

    func testImageMatchTargetDecoding() throws {
        let json = """
        {"image_match": {"template": "icon.png", "threshold": 0.85}}
        """
        let target = try JSONDecoder().decode(ElementTarget.self, from: json.data(using: .utf8)!)
        XCTAssertNotNil(target.imageMatch)
        XCTAssertEqual(target.imageMatch?.template, "icon.png")
        XCTAssertEqual(target.imageMatch?.threshold, 0.85)
    }

    // MARK: - TargetApp

    func testTargetAppDecoding() throws {
        let json = """
        {"name": "Safari", "bundle_id": "com.apple.Safari", "launch": true}
        """
        let app = try JSONDecoder().decode(TargetApp.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(app.name, "Safari")
        XCTAssertEqual(app.bundleId, "com.apple.Safari")
        XCTAssertEqual(app.launch, true)
    }

    func testTargetAppMinimal() throws {
        let json = """
        {"name": "MyApp"}
        """
        let app = try JSONDecoder().decode(TargetApp.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(app.name, "MyApp")
        XCTAssertNil(app.bundleId)
        XCTAssertNil(app.launch)
    }

    // MARK: - WaitCondition

    func testWaitConditionDecoding() throws {
        let json = """
        {"element": {"text_ocr": "Loading..."}, "text": "Ready"}
        """
        let condition = try JSONDecoder().decode(WaitCondition.self, from: json.data(using: .utf8)!)
        XCTAssertNotNil(condition.element)
        XCTAssertEqual(condition.element?.textOcr, "Loading...")
        XCTAssertEqual(condition.text, "Ready")
    }

    // MARK: - ScreenRegion

    func testScreenRegionDecoding() throws {
        let json = """
        {"x": 0, "y": 0, "width": 1920, "height": 1080}
        """
        let region = try JSONDecoder().decode(ScreenRegion.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(region.width, 1920)
        XCTAssertEqual(region.height, 1080)
    }
}

// MARK: - Database Tests

final class DatabaseTests: XCTestCase {
    var database: DatabaseManager!

    override func setUp() async throws {
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("flowproof-test-\(UUID().uuidString).db").path
        database = try DatabaseManager(path: tempPath)
    }

    func testInsertAndFetchRun() throws {
        var run = WorkflowRun(
            id: nil,
            workflowId: UUID().uuidString,
            workflowName: "Test Workflow",
            status: .running,
            startedAt: Date(),
            endedAt: nil,
            durationMs: nil,
            totalSteps: 5,
            passedSteps: 0,
            failedSteps: 0,
            skippedSteps: 0,
            errorMessage: nil
        )

        let insertedRun = try database.insertRun(&run)
        XCTAssertNotNil(insertedRun.id)

        let fetched = try database.fetchLatestRuns(limit: 10)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].workflowName, "Test Workflow")
        XCTAssertEqual(fetched[0].status, .running)
    }

    func testInsertStepResult() throws {
        var run = WorkflowRun(
            id: nil, workflowId: "wf1", workflowName: "Test",
            status: .running, startedAt: Date(), endedAt: nil,
            durationMs: nil, totalSteps: 1, passedSteps: 0,
            failedSteps: 0, skippedSteps: 0, errorMessage: nil
        )
        run = try database.insertRun(&run)

        var step = StepResult(
            id: nil, runId: run.id!, stepIndex: 0,
            stepName: "Click button", action: "click",
            status: .passed, startedAt: Date(), endedAt: Date(),
            durationMs: 150, screenshotPath: "/tmp/screen.png",
            errorMessage: nil, retryCount: 0
        )
        step = try database.insertStepResult(&step)
        XCTAssertNotNil(step.id)

        let steps = try database.fetchStepResults(runId: run.id!)
        XCTAssertEqual(steps.count, 1)
        XCTAssertEqual(steps[0].stepName, "Click button")
        XCTAssertEqual(steps[0].durationMs, 150)
    }

    func testRunCounting() throws {
        let wfId = "counting-test"

        for i in 0..<5 {
            var run = WorkflowRun(
                id: nil, workflowId: wfId, workflowName: "Counter",
                status: i < 3 ? .passed : .failed, startedAt: Date(),
                endedAt: Date(), durationMs: Int64(i * 100),
                totalSteps: 1, passedSteps: i < 3 ? 1 : 0,
                failedSteps: i < 3 ? 0 : 1, skippedSteps: 0,
                errorMessage: nil
            )
            _ = try database.insertRun(&run)
        }

        let total = try database.countRunsForWorkflow(workflowId: wfId)
        XCTAssertEqual(total, 5)

        let passed = try database.countPassedRunsForWorkflow(workflowId: wfId)
        XCTAssertEqual(passed, 3)
    }
}
