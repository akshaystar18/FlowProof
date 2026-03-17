import AppKit
import Foundation

struct ExecutionContext {
    var variables: [String: String]
    var runId: Int64
    var screenshotDir: String
    var stepStartTime: Date
    var runStartTime: Date
    var currentAppPid: pid_t
}

struct StepExecutionResult {
    let stepIndex: Int
    let stepName: String?
    let action: String
    let status: RunStatus
    let durationMs: Int64
    let screenshotPath: String?
    let errorMessage: String?
    let assertionEvaluation: AssertionEvaluation?
    let retryCount: Int
}

class StepExecutor {
    let locator: ElementLocator
    let input: InputEngine
    let accessibility: AccessibilityEngine
    let vision: VisionEngine
    let assertions: AssertionEngine
    let variableResolver = VariableResolver.self

    init(
        locator: ElementLocator,
        input: InputEngine,
        accessibility: AccessibilityEngine,
        vision: VisionEngine,
        assertions: AssertionEngine
    ) {
        self.locator = locator
        self.input = input
        self.accessibility = accessibility
        self.vision = vision
        self.assertions = assertions
    }

    func execute(step: WorkflowStep, appPid: pid_t, context: inout ExecutionContext) async throws -> StepExecutionResult {
        let startTime = Date()
        let resolvedStep = try resolveVariablesInStep(step, resolver: variableResolver, context: context)

        do {
            let actionStr = resolvedStep.action.rawValue
            var screenshotPath: String? = nil
            var assertionEvaluation: AssertionEvaluation? = nil

            switch resolvedStep.action {
            case .click:
                try await executeClick(step: resolvedStep, pid: appPid)

            case .drag:
                try await executeDrag(step: resolvedStep, pid: appPid)

            case .type:
                try await executeType(step: resolvedStep, pid: appPid)

            case .key:
                try executeKey(step: resolvedStep)

            case .scroll:
                try await executeScroll(step: resolvedStep, pid: appPid)

            case .wait:
                try await executeWait(step: resolvedStep, pid: appPid)

            case .upload:
                try await executeUpload(step: resolvedStep, pid: appPid)

            case .download:
                try await executeDownload(step: resolvedStep)

            case .assert:
                assertionEvaluation = try await executeAssert(step: resolvedStep, pid: appPid, context: context)

            case .screenshot:
                screenshotPath = try executeScreenshot(step: resolvedStep, pid: appPid, context: context)

            case .launch:
                let pid = try await executeLaunch(step: resolvedStep)
                context.currentAppPid = pid

            case .setVariable:
                executeSetVariable(step: resolvedStep, context: &context)

            case .clipboard:
                try executeClipboard(step: resolvedStep)

            case .menu:
                try executeMenu(step: resolvedStep, pid: appPid)

            case .conditional, .loop, .subWorkflow:
                throw NSError(domain: "StepExecutor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Control flow actions should be handled by WorkflowRunner"])
            }

            let elapsed = Date().timeIntervalSince(startTime)
            let durationMs = Int64(elapsed * 1000)

            let status: RunStatus = assertionEvaluation != nil ? (assertionEvaluation!.passed ? .passed : .failed) : .passed

            return StepExecutionResult(
                stepIndex: abs(step.id.hashValue) % 1000,
                stepName: step.name,
                action: actionStr,
                status: status,
                durationMs: durationMs,
                screenshotPath: screenshotPath,
                errorMessage: nil,
                assertionEvaluation: assertionEvaluation,
                retryCount: 0
            )
        } catch {
            let elapsed = Date().timeIntervalSince(startTime)
            let durationMs = Int64(elapsed * 1000)

            return StepExecutionResult(
                stepIndex: abs(step.id.hashValue) % 1000,
                stepName: step.name,
                action: step.action.rawValue,
                status: .failed,
                durationMs: durationMs,
                screenshotPath: nil,
                errorMessage: error.localizedDescription,
                assertionEvaluation: nil,
                retryCount: 0
            )
        }
    }

    private func executeClick(step: WorkflowStep, pid: pid_t) async throws {
        guard let target = step.target else {
            throw NSError(domain: "StepExecutor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Click requires a target"])
        }

        let located = try await locator.locate(target, in: pid)
        let modifiers = parseModifiers(step.modifiers)
        let clickCount = step.clickCount ?? 1

        input.click(at: located.screenPosition, button: .left, clickCount: clickCount, modifiers: modifiers)

        try? await Task.sleep(for: .milliseconds(200))
    }

    private func executeDrag(step: WorkflowStep, pid: pid_t) async throws {
        guard let from = step.from, let to = step.to else {
            throw NSError(domain: "StepExecutor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Drag requires 'from' and 'to' targets"])
        }

        let fromLocated = try await locator.locate(from, in: pid)
        let toLocated = try await locator.locate(to, in: pid)

        input.drag(from: fromLocated.screenPosition, to: toLocated.screenPosition, duration: 0.5)

        try? await Task.sleep(for: .milliseconds(200))
    }

    private func executeType(step: WorkflowStep, pid: pid_t) async throws {
        guard let text = step.text else {
            throw NSError(domain: "StepExecutor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Type requires text parameter"])
        }

        let delayPerKey = step.delayPerKey ?? 0.05

        for character in text {
            typeCharacter(character)
            try? await Task.sleep(for: .milliseconds(Int(delayPerKey * 1000)))
        }
    }

    private func executeKey(step: WorkflowStep) throws {
        guard let combo = step.combo else {
            throw NSError(domain: "StepExecutor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Key requires combo parameter (e.g., 'cmd+a', 'enter')"])
        }

        try input.pressKeyCombo(combo)
    }

    private func executeScroll(step: WorkflowStep, pid: pid_t) async throws {
        guard let direction = step.direction else {
            throw NSError(domain: "StepExecutor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Scroll requires direction parameter"])
        }

        let target = step.target
        let location = target != nil ? try await locator.locate(target!, in: pid).screenPosition : NSEvent.mouseLocation

        let amount = step.amount ?? 5
        input.scroll(at: location, direction: direction, amount: amount)

        try? await Task.sleep(for: .milliseconds(200))
    }

    private func executeWait(step: WorkflowStep, pid: pid_t) async throws {
        if let duration = step.duration {
            try await Task.sleep(for: .milliseconds(Int(duration * 1000)))
        }

        if let condition = step.condition, let element = condition.element {
            let timeoutInterval = step.timeout ?? 30.0
            let pollInterval = step.interval ?? 0.5

            let deadline = Date().addingTimeInterval(timeoutInterval)

            while Date() < deadline {
                do {
                    let located = try await locator.locate(element, in: pid)
                    if condition.state == "visible" {
                        if accessibility.isElementVisible(located.axElement ?? accessibility.applicationElement(pid: pid)) {
                            return
                        }
                    } else if condition.state == "enabled" {
                        if let axElement = located.axElement, accessibility.isElementEnabled(axElement) {
                            return
                        }
                    } else {
                        return
                    }
                } catch {
                }

                try await Task.sleep(for: .milliseconds(Int(pollInterval * 1000)))
            }

            throw NSError(domain: "StepExecutor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Wait condition timeout"])
        }
    }

    private func executeUpload(step: WorkflowStep, pid: pid_t) async throws {
        guard let filePath = step.filePath else {
            throw NSError(domain: "StepExecutor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Upload requires file_path parameter"])
        }

        guard let target = step.target else {
            throw NSError(domain: "StepExecutor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Upload requires a target file input element"])
        }

        let located = try await locator.locate(target, in: pid)

        if let axElement = located.axElement {
            do {
                try accessibility.setFileURL(axElement, path: filePath)
            } catch {
                throw NSError(domain: "StepExecutor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to upload file: \(error.localizedDescription)"])
            }
        }

        try? await Task.sleep(for: .milliseconds(500))
    }

    private func executeDownload(step: WorkflowStep) async throws {
        try? await Task.sleep(for: .milliseconds(2000))
    }

    private func executeAssert(step: WorkflowStep, pid: pid_t, context: ExecutionContext) async throws -> AssertionEvaluation {
        guard let assertType = step.assertType else {
            throw NSError(domain: "StepExecutor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Assert requires assert_type parameter"])
        }

        let evaluation = try await assertions.evaluate(
            type: assertType,
            target: step.target,
            expected: step.expected,
            appPid: pid,
            stepStartTime: context.stepStartTime,
            runStartTime: context.runStartTime,
            locator: locator
        )

        if !evaluation.passed {
            throw NSError(domain: "StepExecutor", code: -1, userInfo: [NSLocalizedDescriptionKey: evaluation.message])
        }

        return evaluation
    }

    private func executeScreenshot(step: WorkflowStep, pid: pid_t, context: ExecutionContext) throws -> String {
        let screenshot = try vision.captureWindow(pid: pid)

        let filename = String(format: "step_%d_%d.png", context.runId, Int(Date().timeIntervalSince1970 * 1000))
        let screenshotPath = (context.screenshotDir as NSString).appendingPathComponent(filename)

        if let tiffRepresentation = screenshot.tiffRepresentation,
           let bitmapImage = NSBitmapImageRep(data: tiffRepresentation),
           let pngData = bitmapImage.representation(using: .png, properties: [:]) {
            try pngData.write(to: URL(fileURLWithPath: screenshotPath))
        }

        return screenshotPath
    }

    private func executeLaunch(step: WorkflowStep) async throws -> pid_t {
        let bundleId = step.bundleId ?? ""
        let workspace = NSWorkspace.shared

        guard let appURL = workspace.urlForApplication(withBundleIdentifier: bundleId) else {
            throw NSError(domain: "StepExecutor", code: -1, userInfo: [NSLocalizedDescriptionKey: "No application found for bundle ID: \(bundleId)"])
        }

        let config = NSWorkspace.OpenConfiguration()
        if let args = step.args {
            config.arguments = args
        }

        return try await withCheckedThrowingContinuation { continuation in
            workspace.openApplication(at: appURL, configuration: config) { app, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let app = app {
                    continuation.resume(returning: app.processIdentifier)
                } else {
                    continuation.resume(throwing: NSError(domain: "StepExecutor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to launch app: \(bundleId)"]))
                }
            }
        }
    }

    private func executeSetVariable(step: WorkflowStep, context: inout ExecutionContext) {
        if let varName = step.variableName, let varValue = step.variableValue {
            context.variables[varName] = varValue
        }
    }

    private func executeClipboard(step: WorkflowStep) throws {
        guard let action = step.clipboardAction else {
            throw NSError(domain: "StepExecutor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Clipboard requires action parameter"])
        }

        let pasteboard = NSPasteboard.general

        switch action {
        case .copy:
            break

        case .paste:
            if let content = pasteboard.string(forType: .string) {
                typeString(content)
            }

        case .clear:
            pasteboard.clearContents()
        }
    }

    private func executeMenu(step: WorkflowStep, pid: pid_t) throws {
        guard let menuPath = step.menuPath else {
            throw NSError(domain: "StepExecutor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Menu requires menu_path parameter"])
        }

        let appElement = accessibility.applicationElement(pid: pid)
        let menuItems = menuPath.split(separator: ">").map(String.init)

        for menuItem in menuItems {
            let trimmedItem = menuItem.trimmingCharacters(in: .whitespaces)
            do {
                try accessibility.activateMenu(appElement, item: trimmedItem)
            } catch {
                throw NSError(domain: "StepExecutor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to activate menu item: \(trimmedItem)"])
            }
        }
    }

    private func resolveVariablesInStep(_ step: WorkflowStep, resolver: VariableResolver.Type, context: ExecutionContext) throws -> WorkflowStep {
        var resolvedStep = step

        if let text = step.text {
            resolvedStep.text = try resolver.resolve(text, with: context.variables)
        }

        if let expected = step.expected {
            resolvedStep.expected = try resolver.resolve(expected, with: context.variables)
        }

        if let filePath = step.filePath {
            resolvedStep.filePath = try resolver.resolve(filePath, with: context.variables)
        }

        if let expectedPath = step.expectedPath {
            resolvedStep.expectedPath = try resolver.resolve(expectedPath, with: context.variables)
        }

        return resolvedStep
    }

    private func parseModifiers(_ modifierStrings: [String]?) -> CGEventFlags {
        guard let modifiers = modifierStrings else { return [] }

        var flags: CGEventFlags = []

        for modifier in modifiers {
            switch modifier.lowercased() {
            case "cmd", "command":
                flags.insert(.maskCommand)
            case "alt", "option":
                flags.insert(.maskAlternate)
            case "shift":
                flags.insert(.maskShift)
            case "ctrl", "control":
                flags.insert(.maskControl)
            default:
                break
            }
        }

        return flags
    }

    // MARK: - Private keyboard/typing helpers

    private func typeCharacter(_ character: Character) {
        let keyCode = getKeyCodeForCharacter(character)
        if let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) {
            event.post(tap: CGEventTapLocation.cghidEventTap)
        }
        if let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) {
            event.post(tap: CGEventTapLocation.cghidEventTap)
        }
    }

    private func typeString(_ string: String) {
        for character in string {
            typeCharacter(character)
        }
    }

    private func getKeyCodeForCharacter(_ character: Character) -> UInt16 {
        let string = String(character)
        return getKeyCodeForString(string)
    }

    private func getKeyCodeForString(_ string: String) -> UInt16 {
        switch string.lowercased() {
        case "a": return 0
        case "b": return 11
        case "c": return 8
        case "d": return 2
        case "e": return 14
        case "f": return 3
        case "g": return 5
        case "h": return 4
        case "i": return 34
        case "j": return 38
        case "k": return 40
        case "l": return 37
        case "m": return 46
        case "n": return 45
        case "o": return 31
        case "p": return 35
        case "q": return 12
        case "r": return 15
        case "s": return 1
        case "t": return 17
        case "u": return 32
        case "v": return 9
        case "w": return 13
        case "x": return 7
        case "y": return 16
        case "z": return 6
        case "0": return 29
        case "1": return 18
        case "2": return 19
        case "3": return 20
        case "4": return 21
        case "5": return 23
        case "6": return 22
        case "7": return 26
        case "8": return 28
        case "9": return 25
        case "enter", "return": return 36
        case "tab": return 48
        case "space": return 49
        case "backspace", "delete": return 51
        case "escape": return 53
        case "left": return 123
        case "right": return 124
        case "up": return 126
        case "down": return 125
        default: return 0
        }
    }
}
