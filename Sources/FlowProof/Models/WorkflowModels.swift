import Foundation

// MARK: - Workflow Definition
/// Top-level workflow structure parsed from YAML
struct Workflow: Codable, Identifiable {
    let id: UUID
    var name: String
    var version: String
    var targetApp: TargetApp
    var variables: [String: String]?
    var setup: [WorkflowStep]?
    var steps: [WorkflowStep]
    var teardown: [WorkflowStep]?
    var onFailure: FailureStrategy?
    var timeout: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case name, version, variables, setup, steps, teardown, timeout
        case targetApp = "target_app"
        case onFailure = "on_failure"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.name = try container.decode(String.self, forKey: .name)
        self.version = try container.decode(String.self, forKey: .version)
        self.targetApp = try container.decode(TargetApp.self, forKey: .targetApp)
        self.variables = try container.decodeIfPresent([String: String].self, forKey: .variables)
        self.setup = try container.decodeIfPresent([WorkflowStep].self, forKey: .setup)
        self.steps = try container.decode([WorkflowStep].self, forKey: .steps)
        self.teardown = try container.decodeIfPresent([WorkflowStep].self, forKey: .teardown)
        self.onFailure = try container.decodeIfPresent(FailureStrategy.self, forKey: .onFailure)
        self.timeout = try container.decodeIfPresent(TimeInterval.self, forKey: .timeout)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(version, forKey: .version)
        try container.encode(targetApp, forKey: .targetApp)
        try container.encodeIfPresent(variables, forKey: .variables)
        try container.encodeIfPresent(setup, forKey: .setup)
        try container.encode(steps, forKey: .steps)
        try container.encodeIfPresent(teardown, forKey: .teardown)
        try container.encodeIfPresent(onFailure, forKey: .onFailure)
        try container.encodeIfPresent(timeout, forKey: .timeout)
    }
}

struct TargetApp: Codable {
    let name: String
    let bundleId: String?
    let launch: Bool?

    enum CodingKeys: String, CodingKey {
        case name
        case bundleId = "bundle_id"
        case launch
    }
}

enum FailureStrategy: String, Codable {
    case abort, skip, retry
}

// MARK: - WorkflowStep
struct WorkflowStep: Codable, Identifiable {
    let id: UUID
    var name: String?
    var action: ActionType

    // Element targeting
    var target: ElementTarget?
    var from: ElementTarget?
    var to: ElementTarget?

    // Text input
    var text: String?
    var combo: String?

    // Timing and conditions
    var duration: TimeInterval?
    var condition: WaitCondition?
    var timeout: TimeInterval?
    var interval: TimeInterval?
    var delayPerKey: TimeInterval?

    // File operations
    var filePath: String?
    var expectedPath: String?

    // Assertions
    var assertType: AssertionType?
    var expected: String?
    var region: ScreenRegion?

    // App launching
    var bundleId: String?
    var args: [String]?

    // Conditionals and loops
    var ifCondition: WaitCondition?
    var thenSteps: [WorkflowStep]?
    var elseSteps: [WorkflowStep]?
    var count: Int?
    var loopSteps: [WorkflowStep]?

    // Sub-workflows and variables
    var subWorkflowPath: String?
    var variableName: String?
    var variableValue: String?

    // Clipboard
    var clipboardAction: ClipboardAction?
    var clipboardValue: String?

    // Menu
    var menuPath: String?

    // Scroll
    var direction: ScrollDirection?
    var amount: Int?

    // Keyboard modifiers
    var modifiers: [String]?
    var clickCount: Int?
    var `repeat`: Int?

    // Error handling
    var onFailure: FailureStrategy?

    // Utilities
    var screenshot: Bool?
    var description: String?

    enum CodingKeys: String, CodingKey {
        case name, action, target, text, combo, from, to, duration, condition, timeout, interval
        case filePath = "file_path"
        case expectedPath = "expected_path"
        case assertType = "assert_type"
        case expected, region, bundleId = "bundle_id"
        case args
        case ifCondition = "if_condition"
        case thenSteps = "then_steps"
        case elseSteps = "else_steps"
        case count
        case loopSteps = "loop_steps"
        case subWorkflowPath = "sub_workflow_path"
        case variableName = "variable_name"
        case variableValue = "variable_value"
        case clipboardAction = "clipboard_action"
        case clipboardValue = "clipboard_value"
        case menuPath = "menu_path"
        case direction, amount, modifiers, clickCount = "click_count"
        case delayPerKey = "delay_per_key"
        case `repeat`
        case onFailure = "on_failure"
        case screenshot, description
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.action = try container.decode(ActionType.self, forKey: .action)
        self.target = try container.decodeIfPresent(ElementTarget.self, forKey: .target)
        self.from = try container.decodeIfPresent(ElementTarget.self, forKey: .from)
        self.to = try container.decodeIfPresent(ElementTarget.self, forKey: .to)
        self.text = try container.decodeIfPresent(String.self, forKey: .text)
        self.combo = try container.decodeIfPresent(String.self, forKey: .combo)
        self.duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
        self.condition = try container.decodeIfPresent(WaitCondition.self, forKey: .condition)
        self.timeout = try container.decodeIfPresent(TimeInterval.self, forKey: .timeout)
        self.interval = try container.decodeIfPresent(TimeInterval.self, forKey: .interval)
        self.filePath = try container.decodeIfPresent(String.self, forKey: .filePath)
        self.expectedPath = try container.decodeIfPresent(String.self, forKey: .expectedPath)
        self.assertType = try container.decodeIfPresent(AssertionType.self, forKey: .assertType)
        self.expected = try container.decodeIfPresent(String.self, forKey: .expected)
        self.region = try container.decodeIfPresent(ScreenRegion.self, forKey: .region)
        self.bundleId = try container.decodeIfPresent(String.self, forKey: .bundleId)
        self.args = try container.decodeIfPresent([String].self, forKey: .args)
        self.ifCondition = try container.decodeIfPresent(WaitCondition.self, forKey: .ifCondition)
        self.thenSteps = try container.decodeIfPresent([WorkflowStep].self, forKey: .thenSteps)
        self.elseSteps = try container.decodeIfPresent([WorkflowStep].self, forKey: .elseSteps)
        self.count = try container.decodeIfPresent(Int.self, forKey: .count)
        self.loopSteps = try container.decodeIfPresent([WorkflowStep].self, forKey: .loopSteps)
        self.subWorkflowPath = try container.decodeIfPresent(String.self, forKey: .subWorkflowPath)
        self.variableName = try container.decodeIfPresent(String.self, forKey: .variableName)
        self.variableValue = try container.decodeIfPresent(String.self, forKey: .variableValue)
        self.clipboardAction = try container.decodeIfPresent(ClipboardAction.self, forKey: .clipboardAction)
        self.clipboardValue = try container.decodeIfPresent(String.self, forKey: .clipboardValue)
        self.menuPath = try container.decodeIfPresent(String.self, forKey: .menuPath)
        self.direction = try container.decodeIfPresent(ScrollDirection.self, forKey: .direction)
        self.amount = try container.decodeIfPresent(Int.self, forKey: .amount)
        self.modifiers = try container.decodeIfPresent([String].self, forKey: .modifiers)
        self.clickCount = try container.decodeIfPresent(Int.self, forKey: .clickCount)
        self.delayPerKey = try container.decodeIfPresent(TimeInterval.self, forKey: .delayPerKey)
        self.`repeat` = try container.decodeIfPresent(Int.self, forKey: .repeat)
        self.onFailure = try container.decodeIfPresent(FailureStrategy.self, forKey: .onFailure)
        self.screenshot = try container.decodeIfPresent(Bool.self, forKey: .screenshot)
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encode(action, forKey: .action)
        try container.encodeIfPresent(target, forKey: .target)
        try container.encodeIfPresent(from, forKey: .from)
        try container.encodeIfPresent(to, forKey: .to)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encodeIfPresent(combo, forKey: .combo)
        try container.encodeIfPresent(duration, forKey: .duration)
        try container.encodeIfPresent(condition, forKey: .condition)
        try container.encodeIfPresent(timeout, forKey: .timeout)
        try container.encodeIfPresent(interval, forKey: .interval)
        try container.encodeIfPresent(filePath, forKey: .filePath)
        try container.encodeIfPresent(expectedPath, forKey: .expectedPath)
        try container.encodeIfPresent(assertType, forKey: .assertType)
        try container.encodeIfPresent(expected, forKey: .expected)
        try container.encodeIfPresent(region, forKey: .region)
        try container.encodeIfPresent(bundleId, forKey: .bundleId)
        try container.encodeIfPresent(args, forKey: .args)
        try container.encodeIfPresent(ifCondition, forKey: .ifCondition)
        try container.encodeIfPresent(thenSteps, forKey: .thenSteps)
        try container.encodeIfPresent(elseSteps, forKey: .elseSteps)
        try container.encodeIfPresent(count, forKey: .count)
        try container.encodeIfPresent(loopSteps, forKey: .loopSteps)
        try container.encodeIfPresent(subWorkflowPath, forKey: .subWorkflowPath)
        try container.encodeIfPresent(variableName, forKey: .variableName)
        try container.encodeIfPresent(variableValue, forKey: .variableValue)
        try container.encodeIfPresent(clipboardAction, forKey: .clipboardAction)
        try container.encodeIfPresent(clipboardValue, forKey: .clipboardValue)
        try container.encodeIfPresent(menuPath, forKey: .menuPath)
        try container.encodeIfPresent(direction, forKey: .direction)
        try container.encodeIfPresent(amount, forKey: .amount)
        try container.encodeIfPresent(modifiers, forKey: .modifiers)
        try container.encodeIfPresent(clickCount, forKey: .clickCount)
        try container.encodeIfPresent(delayPerKey, forKey: .delayPerKey)
        try container.encodeIfPresent(`repeat`, forKey: .repeat)
        try container.encodeIfPresent(onFailure, forKey: .onFailure)
        try container.encodeIfPresent(screenshot, forKey: .screenshot)
        try container.encodeIfPresent(description, forKey: .description)
    }
}

// MARK: - ActionType
enum ActionType: String, Codable {
    case click
    case drag
    case type
    case key
    case scroll
    case wait
    case upload
    case download
    case assert
    case screenshot
    case launch
    case conditional
    case loop
    case subWorkflow = "sub_workflow"
    case setVariable = "set_variable"
    case clipboard
    case menu
}

// MARK: - Element Targeting
struct ElementTarget: Codable {
    var accessibility: AccessibilityTarget?
    var textOcr: String?
    var imageMatch: ImageMatchTarget?
    var coordinates: Coordinates?
    var relative: RelativeTarget?
    var hybrid: [ElementTarget]?

    enum CodingKeys: String, CodingKey {
        case accessibility
        case textOcr = "text_ocr"
        case imageMatch = "image_match"
        case coordinates, relative, hybrid
    }
}

struct AccessibilityTarget: Codable {
    var role: String?
    var label: String?
    var value: String?
    var identifier: String?
}

struct ImageMatchTarget: Codable {
    var template: String
    var threshold: Double?
}

struct Coordinates: Codable {
    var x: Double
    var y: Double
}

final class RelativeTarget: Codable {
    var relativeTo: ElementTarget
    var offset: Coordinates

    init(relativeTo: ElementTarget, offset: Coordinates) {
        self.relativeTo = relativeTo
        self.offset = offset
    }

    enum CodingKeys: String, CodingKey {
        case relativeTo = "relative_to"
        case offset
    }
}

struct WaitCondition: Codable {
    var element: ElementTarget?
    var text: String?
    var state: String?
}

struct ScreenRegion: Codable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

// MARK: - Assertions
enum AssertionType: String, Codable {
    // Visual
    case screenshotMatch = "screenshot_match"
    case pixelDiff = "pixel_diff"
    case regionCompare = "region_compare"

    // Textual
    case textEquals = "text_equals"
    case textContains = "text_contains"
    case textRegex = "text_regex"
    case textNotContains = "text_not_contains"

    // Element
    case elementVisible = "element_visible"
    case elementEnabled = "element_enabled"
    case elementFocused = "element_focused"
    case elementValue = "element_value"

    // File
    case fileExists = "file_exists"
    case fileSize = "file_size"
    case fileContent = "file_content"
    case fileCount = "file_count"

    // System
    case clipboardContains = "clipboard_contains"
    case notificationAppeared = "notification_appeared"
    case processRunning = "process_running"

    // Timing
    case stepDurationUnder = "step_duration_under"
    case totalDurationUnder = "total_duration_under"
}

// MARK: - Enums
enum ClipboardAction: String, Codable {
    case copy, paste, clear
}

enum ScrollDirection: String, Codable {
    case up, down, left, right
}
