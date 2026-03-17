import XCTest
@testable import FlowProof

final class WorkflowParserTests: XCTestCase {

    // MARK: - YAML Parsing

    func testParseMinimalWorkflow() throws {
        let yaml = """
        name: "Test Workflow"
        version: "1.0"
        target_app:
          name: "Safari"
          bundle_id: "com.apple.Safari"
        steps:
          - action: click
            target:
              text_ocr: "Submit"
        """
        let workflow = try WorkflowParser.parseYAML(yaml)
        XCTAssertEqual(workflow.name, "Test Workflow")
        XCTAssertEqual(workflow.version, "1.0")
        XCTAssertEqual(workflow.targetApp.name, "Safari")
        XCTAssertEqual(workflow.targetApp.bundleId, "com.apple.Safari")
        XCTAssertEqual(workflow.steps.count, 1)
        XCTAssertEqual(workflow.steps[0].action, .click)
    }

    func testParseWorkflowWithVariables() throws {
        let yaml = """
        name: "Variable Test"
        version: "1.0"
        target_app:
          name: "App"
        variables:
          username: "testuser"
          channel: "general"
        steps:
          - action: type
            text: "${username}"
        """
        let workflow = try WorkflowParser.parseYAML(yaml)
        XCTAssertNotNil(workflow.variables)
        XCTAssertEqual(workflow.variables?["username"], "testuser")
        XCTAssertEqual(workflow.variables?["channel"], "general")
    }

    func testParseAllActionTypes() throws {
        let yaml = """
        name: "All Actions"
        version: "1.0"
        target_app:
          name: "Test"
        steps:
          - action: click
            target:
              coordinates: { x: 100, y: 200 }
          - action: type
            text: "hello"
          - action: key
            combo: "cmd+s"
          - action: wait
            timeout: 5
          - action: screenshot
            name: "test"
          - action: assert
            type: element_visible
            target:
              text_ocr: "OK"
          - action: scroll
            direction: down
            amount: 3
          - action: launch
            bundle_id: "com.app.test"
        """
        let workflow = try WorkflowParser.parseYAML(yaml)
        XCTAssertEqual(workflow.steps.count, 8)
        XCTAssertEqual(workflow.steps[0].action, .click)
        XCTAssertEqual(workflow.steps[1].action, .type)
        XCTAssertEqual(workflow.steps[2].action, .key)
        XCTAssertEqual(workflow.steps[3].action, .wait)
        XCTAssertEqual(workflow.steps[4].action, .screenshot)
        XCTAssertEqual(workflow.steps[5].action, .assert)
        XCTAssertEqual(workflow.steps[6].action, .scroll)
        XCTAssertEqual(workflow.steps[7].action, .launch)
    }

    func testParseTargetStrategies() throws {
        let yaml = """
        name: "Targeting"
        version: "1.0"
        target_app:
          name: "Test"
        steps:
          - action: click
            target:
              accessibility:
                role: "button"
                label: "Submit"
          - action: click
            target:
              text_ocr: "Cancel"
          - action: click
            target:
              image_match:
                template: "icon.png"
                threshold: 0.9
          - action: click
            target:
              coordinates: { x: 300, y: 400 }
          - action: click
            target:
              relative:
                relative_to:
                  text_ocr: "Email"
                offset: { x: 200, y: 0 }
        """
        let workflow = try WorkflowParser.parseYAML(yaml)
        XCTAssertEqual(workflow.steps.count, 5)
        XCTAssertNotNil(workflow.steps[0].target?.accessibility)
        XCTAssertEqual(workflow.steps[0].target?.accessibility?.role, "button")
        XCTAssertEqual(workflow.steps[1].target?.textOcr, "Cancel")
        XCTAssertNotNil(workflow.steps[2].target?.imageMatch)
        XCTAssertEqual(workflow.steps[2].target?.imageMatch?.threshold, 0.9)
        XCTAssertNotNil(workflow.steps[3].target?.coordinates)
        XCTAssertNotNil(workflow.steps[4].target?.relative)
    }

    func testParseSetupAndTeardown() throws {
        let yaml = """
        name: "With Phases"
        version: "1.0"
        target_app:
          name: "App"
        setup:
          - action: launch
            bundle_id: "com.test.app"
        steps:
          - action: click
            target:
              text_ocr: "OK"
        teardown:
          - action: screenshot
            name: "final"
        """
        let workflow = try WorkflowParser.parseYAML(yaml)
        XCTAssertEqual(workflow.setup?.count, 1)
        XCTAssertEqual(workflow.steps.count, 1)
        XCTAssertEqual(workflow.teardown?.count, 1)
    }

    func testParseFailureStrategy() throws {
        let yaml = """
        name: "Retry"
        version: "1.0"
        target_app:
          name: "App"
        on_failure: retry
        timeout: 120
        steps:
          - action: click
            target:
              text_ocr: "OK"
        """
        let workflow = try WorkflowParser.parseYAML(yaml)
        XCTAssertEqual(workflow.onFailure, .retry)
        XCTAssertEqual(workflow.timeout, 120)
    }

    func testParseConditionalStep() throws {
        let yaml = """
        name: "Conditional"
        version: "1.0"
        target_app:
          name: "App"
        steps:
          - action: conditional
            if_condition:
              element:
                text_ocr: "Login"
            then_steps:
              - action: click
                target:
                  text_ocr: "Login"
            else_steps:
              - action: click
                target:
                  text_ocr: "Dashboard"
        """
        let workflow = try WorkflowParser.parseYAML(yaml)
        XCTAssertEqual(workflow.steps[0].action, .conditional)
        XCTAssertNotNil(workflow.steps[0].ifCondition)
        XCTAssertNotNil(workflow.steps[0].thenSteps)
        XCTAssertNotNil(workflow.steps[0].elseSteps)
    }

    // MARK: - Error Cases

    func testParseMissingName() {
        let yaml = """
        version: "1.0"
        target_app:
          name: "App"
        steps:
          - action: click
        """
        XCTAssertThrowsError(try WorkflowParser.parseYAML(yaml))
    }

    func testParseMissingSteps() {
        let yaml = """
        name: "No Steps"
        version: "1.0"
        target_app:
          name: "App"
        """
        XCTAssertThrowsError(try WorkflowParser.parseYAML(yaml))
    }

    func testParseInvalidYAML() {
        let yaml = """
        this is not: [valid yaml
        """
        XCTAssertThrowsError(try WorkflowParser.parseYAML(yaml))
    }
}

// MARK: - Variable Resolver Tests

final class VariableResolverTests: XCTestCase {

    func testBasicResolution() {
        let resolver = VariableResolver(variables: ["name": "FlowProof", "version": "1.0"])
        XCTAssertEqual(resolver.resolve("App: ${name} v${version}"), "App: FlowProof v1.0")
    }

    func testNoVariables() {
        let resolver = VariableResolver(variables: [:])
        XCTAssertEqual(resolver.resolve("No variables here"), "No variables here")
    }

    func testBuiltInVariables() {
        let resolver = VariableResolver(variables: [:])
        let result = resolver.resolve("Home: ${home_dir}")
        XCTAssertFalse(result.contains("${home_dir}"))
        XCTAssertTrue(result.contains("/"))
    }

    func testDesktopVariable() {
        let resolver = VariableResolver(variables: [:])
        let result = resolver.resolve("${desktop}")
        XCTAssertTrue(result.contains("Desktop"))
    }

    func testDateVariable() {
        let resolver = VariableResolver(variables: [:])
        let result = resolver.resolve("${date}")
        XCTAssertFalse(result.contains("${date}"))
        // Should contain year
        XCTAssertTrue(result.contains("202"))
    }

    func testTimestampVariable() {
        let resolver = VariableResolver(variables: [:])
        let result = resolver.resolve("${timestamp}")
        XCTAssertFalse(result.contains("${timestamp}"))
    }

    func testEnvironmentVariable() {
        let resolver = VariableResolver(variables: [:])
        let result = resolver.resolve("${env.PATH}")
        XCTAssertFalse(result.contains("${env.PATH}"))
        XCTAssertTrue(result.contains("/"))
    }

    func testMixedVariables() {
        let resolver = VariableResolver(variables: ["channel": "general"])
        let result = resolver.resolve("${channel} at ${date}")
        XCTAssertTrue(result.hasPrefix("general"))
        XCTAssertFalse(result.contains("${date}"))
    }

    func testUndefinedVariable() {
        let resolver = VariableResolver(variables: [:])
        let result = resolver.resolve("${undefined_var}")
        // Should either leave as-is or return empty
        XCTAssertTrue(result.contains("${undefined_var}") || result.isEmpty || !result.contains("$"))
    }

    func testMultipleOccurrences() {
        let resolver = VariableResolver(variables: ["x": "hello"])
        let result = resolver.resolve("${x} and ${x} again")
        XCTAssertEqual(result, "hello and hello again")
    }
}
