import AppKit
import Foundation

struct AssertionEvaluation {
    let passed: Bool
    let assertionType: String
    let expected: String?
    let actual: String?
    let message: String
    let confidence: Double
}

class AssertionEngine {
    let accessibilityEngine: AccessibilityEngine
    let visionEngine: VisionEngine

    init(accessibilityEngine: AccessibilityEngine, visionEngine: VisionEngine) {
        self.accessibilityEngine = accessibilityEngine
        self.visionEngine = visionEngine
    }

    func evaluate(
        type: AssertionType,
        target: ElementTarget?,
        expected: String?,
        appPid: pid_t,
        stepStartTime: Date,
        runStartTime: Date,
        locator: ElementLocator
    ) async throws -> AssertionEvaluation {
        switch type {
        case .screenshotMatch:
            return try evaluateScreenshotMatch(target: target, expected: expected, pid: appPid)
        case .pixelDiff:
            return try evaluatePixelDiff(target: target, expected: expected, pid: appPid)
        case .regionCompare:
            return try evaluateRegionCompare(target: target, expected: expected, pid: appPid)
        case .textEquals:
            return try await evaluateTextEquals(target: target, expected: expected, pid: appPid, locator: locator)
        case .textContains:
            return try await evaluateTextContains(target: target, expected: expected, pid: appPid, locator: locator)
        case .textRegex:
            return try await evaluateTextRegex(target: target, expected: expected, pid: appPid, locator: locator)
        case .textNotContains:
            return try await evaluateTextNotContains(target: target, expected: expected, pid: appPid, locator: locator)
        case .elementVisible:
            return try await evaluateElementVisible(target: target, pid: appPid, locator: locator)
        case .elementEnabled:
            return try await evaluateElementEnabled(target: target, pid: appPid, locator: locator)
        case .elementFocused:
            return try await evaluateElementFocused(target: target, pid: appPid, locator: locator)
        case .elementValue:
            return try await evaluateElementValue(target: target, expected: expected, pid: appPid, locator: locator)
        case .fileExists:
            return try evaluateFileExists(expected: expected)
        case .fileSize:
            return try evaluateFileSize(expected: expected)
        case .fileContent:
            return try evaluateFileContent(expected: expected)
        case .fileCount:
            return try evaluateFileCount(expected: expected)
        case .clipboardContains:
            return evaluateClipboardContains(expected: expected)
        case .notificationAppeared:
            return evaluateNotificationAppeared(expected: expected)
        case .processRunning:
            return evaluateProcessRunning(expected: expected)
        case .stepDurationUnder:
            return evaluateStepDuration(expected: expected, stepStartTime: stepStartTime)
        case .totalDurationUnder:
            return evaluateTotalDuration(expected: expected, runStartTime: runStartTime)
        }
    }

    private func evaluateScreenshotMatch(target: ElementTarget?, expected: String?, pid: pid_t) throws -> AssertionEvaluation {
        guard let expected = expected else {
            return AssertionEvaluation(
                passed: false,
                assertionType: "screenshot_match",
                expected: expected,
                actual: nil,
                message: "Expected parameter required for screenshot_match",
                confidence: 0.0
            )
        }

        let screenshot = try visionEngine.captureWindow(pid: pid)
        guard let expectedImage = NSImage(contentsOfFile: expected) else {
            return AssertionEvaluation(
                passed: false,
                assertionType: "screenshot_match",
                expected: expected,
                actual: nil,
                message: "Cannot load expected image from path",
                confidence: 0.0
            )
        }

        let comparison = try visionEngine.compareImages(screenshot, expectedImage)

        return AssertionEvaluation(
            passed: comparison.passed,
            assertionType: "screenshot_match",
            expected: expected,
            actual: nil,
            message: comparison.passed ? "Screenshot matches baseline" : "Screenshot differs from baseline",
            confidence: comparison.similarityScore
        )
    }

    private func evaluatePixelDiff(target: ElementTarget?, expected: String?, pid: pid_t) throws -> AssertionEvaluation {
        guard let expected = expected else {
            return AssertionEvaluation(
                passed: false,
                assertionType: "pixel_diff",
                expected: expected,
                actual: nil,
                message: "Expected parameter required for pixel_diff",
                confidence: 0.0
            )
        }

        let screenshot = try visionEngine.captureWindow(pid: pid)
        guard let baselineImage = NSImage(contentsOfFile: expected) else {
            return AssertionEvaluation(
                passed: false,
                assertionType: "pixel_diff",
                expected: expected,
                actual: nil,
                message: "Cannot load baseline image",
                confidence: 0.0
            )
        }

        let comparison = try visionEngine.compareImages(screenshot, baselineImage)
        let passed = comparison.passed && comparison.similarityScore > 0.95

        return AssertionEvaluation(
            passed: passed,
            assertionType: "pixel_diff",
            expected: expected,
            actual: nil,
            message: "Pixel similarity: \(String(format: "%.2f", comparison.similarityScore * 100))%",
            confidence: comparison.similarityScore
        )
    }

    private func evaluateRegionCompare(target: ElementTarget?, expected: String?, pid: pid_t) throws -> AssertionEvaluation {
        guard let expected = expected, let target = target else {
            return AssertionEvaluation(
                passed: false,
                assertionType: "region_compare",
                expected: expected,
                actual: nil,
                message: "Target and expected parameters required for region_compare",
                confidence: 0.0
            )
        }

        let screenshot = try visionEngine.captureWindow(pid: pid)
        guard let baselineImage = NSImage(contentsOfFile: expected) else {
            return AssertionEvaluation(
                passed: false,
                assertionType: "region_compare",
                expected: expected,
                actual: nil,
                message: "Cannot load baseline region image",
                confidence: 0.0
            )
        }

        let comparison = try visionEngine.compareImages(screenshot, baselineImage)

        return AssertionEvaluation(
            passed: comparison.passed,
            assertionType: "region_compare",
            expected: expected,
            actual: nil,
            message: "Region similarity: \(String(format: "%.2f", comparison.similarityScore * 100))%",
            confidence: comparison.similarityScore
        )
    }

    private func evaluateTextEquals(target: ElementTarget?, expected: String?, pid: pid_t, locator: ElementLocator) async throws -> AssertionEvaluation {
        guard let expected = expected, let target = target else {
            return AssertionEvaluation(
                passed: false,
                assertionType: "text_equals",
                expected: expected,
                actual: nil,
                message: "Target and expected parameters required",
                confidence: 0.0
            )
        }

        let located = try await locator.locate(target, in: pid)
        let appElement = accessibilityEngine.applicationElement(pid: pid)

        guard let axElement = located.axElement else {
            let screenshot = try visionEngine.captureWindow(pid: pid)
            let allText = try visionEngine.extractAllText(from: screenshot)
            let texts = allText.map { $0.text }
            let actual = texts.joined(separator: " ")

            let passed = actual == expected
            return AssertionEvaluation(
                passed: passed,
                assertionType: "text_equals",
                expected: expected,
                actual: actual,
                message: passed ? "Text matches expected" : "Text does not match expected",
                confidence: 0.8
            )
        }

        let actual = (accessibilityEngine.getValue(axElement) ?? accessibilityEngine.getElementText(axElement)) ?? ""
        let passed = actual == expected

        return AssertionEvaluation(
            passed: passed,
            assertionType: "text_equals",
            expected: expected,
            actual: actual,
            message: passed ? "Text equals expected" : "Text: '\(actual)' != '\(expected)'",
            confidence: 1.0
        )
    }

    private func evaluateTextContains(target: ElementTarget?, expected: String?, pid: pid_t, locator: ElementLocator) async throws -> AssertionEvaluation {
        guard let expected = expected, let target = target else {
            return AssertionEvaluation(
                passed: false,
                assertionType: "text_contains",
                expected: expected,
                actual: nil,
                message: "Target and expected parameters required",
                confidence: 0.0
            )
        }

        let located = try await locator.locate(target, in: pid)

        guard let axElement = located.axElement else {
            let screenshot = try visionEngine.captureWindow(pid: pid)
            let allText = try visionEngine.extractAllText(from: screenshot)
            let actual = allText.map { $0.text }.joined(separator: " ")
            let passed = actual.localizedCaseInsensitiveContains(expected)

            return AssertionEvaluation(
                passed: passed,
                assertionType: "text_contains",
                expected: expected,
                actual: actual,
                message: passed ? "Text contains expected substring" : "Text does not contain '\(expected)'",
                confidence: 0.8
            )
        }

        let actual = (accessibilityEngine.getValue(axElement) ?? accessibilityEngine.getElementText(axElement)) ?? ""
        let passed = actual.localizedCaseInsensitiveContains(expected)

        return AssertionEvaluation(
            passed: passed,
            assertionType: "text_contains",
            expected: expected,
            actual: actual,
            message: passed ? "Text contains expected" : "'\(actual)' does not contain '\(expected)'",
            confidence: 1.0
        )
    }

    private func evaluateTextRegex(target: ElementTarget?, expected: String?, pid: pid_t, locator: ElementLocator) async throws -> AssertionEvaluation {
        guard let expected = expected, let target = target else {
            return AssertionEvaluation(
                passed: false,
                assertionType: "text_regex",
                expected: expected,
                actual: nil,
                message: "Target and expected regex pattern required",
                confidence: 0.0
            )
        }

        let located = try await locator.locate(target, in: pid)
        guard let axElement = located.axElement else {
            let screenshot = try visionEngine.captureWindow(pid: pid)
            let allText = try visionEngine.extractAllText(from: screenshot)
            let actual = allText.map { $0.text }.joined(separator: " ")

            do {
                let regex = try NSRegularExpression(pattern: expected, options: .caseInsensitive)
                let range = NSRange(actual.startIndex..., in: actual)
                let matches = regex.firstMatch(in: actual, options: [], range: range)
                let passed = matches != nil

                return AssertionEvaluation(
                    passed: passed,
                    assertionType: "text_regex",
                    expected: expected,
                    actual: actual,
                    message: passed ? "Text matches regex" : "Text does not match regex pattern",
                    confidence: 0.8
                )
            } catch {
                return AssertionEvaluation(
                    passed: false,
                    assertionType: "text_regex",
                    expected: expected,
                    actual: nil,
                    message: "Invalid regex pattern: \(error.localizedDescription)",
                    confidence: 0.0
                )
            }
        }

        let actual = (accessibilityEngine.getValue(axElement) ?? accessibilityEngine.getElementText(axElement)) ?? ""

        do {
            let regex = try NSRegularExpression(pattern: expected, options: .caseInsensitive)
            let range = NSRange(actual.startIndex..., in: actual)
            let matches = regex.firstMatch(in: actual, options: [], range: range)
            let passed = matches != nil

            return AssertionEvaluation(
                passed: passed,
                assertionType: "text_regex",
                expected: expected,
                actual: actual,
                message: passed ? "Text matches regex pattern" : "Text does not match regex",
                confidence: 1.0
            )
        } catch {
            return AssertionEvaluation(
                passed: false,
                assertionType: "text_regex",
                expected: expected,
                actual: nil,
                message: "Invalid regex pattern: \(error.localizedDescription)",
                confidence: 0.0
            )
        }
    }

    private func evaluateTextNotContains(target: ElementTarget?, expected: String?, pid: pid_t, locator: ElementLocator) async throws -> AssertionEvaluation {
        guard let expected = expected, let target = target else {
            return AssertionEvaluation(
                passed: false,
                assertionType: "text_not_contains",
                expected: expected,
                actual: nil,
                message: "Target and expected parameters required",
                confidence: 0.0
            )
        }

        let located = try await locator.locate(target, in: pid)
        guard let axElement = located.axElement else {
            let screenshot = try visionEngine.captureWindow(pid: pid)
            let allText = try visionEngine.extractAllText(from: screenshot)
            let actual = allText.map { $0.text }.joined(separator: " ")
            let passed = !actual.localizedCaseInsensitiveContains(expected)

            return AssertionEvaluation(
                passed: passed,
                assertionType: "text_not_contains",
                expected: expected,
                actual: actual,
                message: passed ? "Text does not contain substring" : "Text should not contain '\(expected)'",
                confidence: 0.8
            )
        }

        let actual = (accessibilityEngine.getValue(axElement) ?? accessibilityEngine.getElementText(axElement)) ?? ""
        let passed = !actual.localizedCaseInsensitiveContains(expected)

        return AssertionEvaluation(
            passed: passed,
            assertionType: "text_not_contains",
            expected: expected,
            actual: actual,
            message: passed ? "Text does not contain expected" : "'\(actual)' should not contain '\(expected)'",
            confidence: 1.0
        )
    }

    private func evaluateElementVisible(target: ElementTarget?, pid: pid_t, locator: ElementLocator) async throws -> AssertionEvaluation {
        guard let target = target else {
            return AssertionEvaluation(
                passed: false,
                assertionType: "element_visible",
                expected: nil,
                actual: nil,
                message: "Target parameter required",
                confidence: 0.0
            )
        }

        do {
            let located = try await locator.locate(target, in: pid)
            guard let axElement = located.axElement else {
                return AssertionEvaluation(
                    passed: false,
                    assertionType: "element_visible",
                    expected: nil,
                    actual: "not found",
                    message: "Element not found",
                    confidence: 0.0
                )
            }

            let visible = accessibilityEngine.isElementVisible(axElement)
            return AssertionEvaluation(
                passed: visible,
                assertionType: "element_visible",
                expected: "true",
                actual: String(visible),
                message: visible ? "Element is visible" : "Element is not visible",
                confidence: 1.0
            )
        } catch {
            return AssertionEvaluation(
                passed: false,
                assertionType: "element_visible",
                expected: nil,
                actual: nil,
                message: "Error locating element: \(error.localizedDescription)",
                confidence: 0.0
            )
        }
    }

    private func evaluateElementEnabled(target: ElementTarget?, pid: pid_t, locator: ElementLocator) async throws -> AssertionEvaluation {
        guard let target = target else {
            return AssertionEvaluation(
                passed: false,
                assertionType: "element_enabled",
                expected: nil,
                actual: nil,
                message: "Target parameter required",
                confidence: 0.0
            )
        }

        do {
            let located = try await locator.locate(target, in: pid)
            guard let axElement = located.axElement else {
                return AssertionEvaluation(
                    passed: false,
                    assertionType: "element_enabled",
                    expected: nil,
                    actual: "not found",
                    message: "Element not found",
                    confidence: 0.0
                )
            }

            let enabled = accessibilityEngine.isElementEnabled(axElement)
            return AssertionEvaluation(
                passed: enabled,
                assertionType: "element_enabled",
                expected: "true",
                actual: String(enabled),
                message: enabled ? "Element is enabled" : "Element is disabled",
                confidence: 1.0
            )
        } catch {
            return AssertionEvaluation(
                passed: false,
                assertionType: "element_enabled",
                expected: nil,
                actual: nil,
                message: "Error locating element: \(error.localizedDescription)",
                confidence: 0.0
            )
        }
    }

    private func evaluateElementFocused(target: ElementTarget?, pid: pid_t, locator: ElementLocator) async throws -> AssertionEvaluation {
        guard let target = target else {
            return AssertionEvaluation(
                passed: false,
                assertionType: "element_focused",
                expected: nil,
                actual: nil,
                message: "Target parameter required",
                confidence: 0.0
            )
        }

        do {
            let located = try await locator.locate(target, in: pid)
            guard let axElement = located.axElement else {
                return AssertionEvaluation(
                    passed: false,
                    assertionType: "element_focused",
                    expected: nil,
                    actual: "not found",
                    message: "Element not found",
                    confidence: 0.0
                )
            }

            let focused = accessibilityEngine.isFocused(axElement)
            return AssertionEvaluation(
                passed: focused,
                assertionType: "element_focused",
                expected: "true",
                actual: String(focused),
                message: focused ? "Element is focused" : "Element is not focused",
                confidence: 1.0
            )
        } catch {
            return AssertionEvaluation(
                passed: false,
                assertionType: "element_focused",
                expected: nil,
                actual: nil,
                message: "Error locating element: \(error.localizedDescription)",
                confidence: 0.0
            )
        }
    }

    private func evaluateElementValue(target: ElementTarget?, expected: String?, pid: pid_t, locator: ElementLocator) async throws -> AssertionEvaluation {
        guard let target = target, let expected = expected else {
            return AssertionEvaluation(
                passed: false,
                assertionType: "element_value",
                expected: expected,
                actual: nil,
                message: "Target and expected parameters required",
                confidence: 0.0
            )
        }

        do {
            let located = try await locator.locate(target, in: pid)
            guard let axElement = located.axElement else {
                return AssertionEvaluation(
                    passed: false,
                    assertionType: "element_value",
                    expected: expected,
                    actual: nil,
                    message: "Element not found",
                    confidence: 0.0
                )
            }

            let actual = accessibilityEngine.getValue(axElement) ?? ""
            let passed = actual == expected

            return AssertionEvaluation(
                passed: passed,
                assertionType: "element_value",
                expected: expected,
                actual: actual,
                message: passed ? "Element value matches" : "Value '\(actual)' != '\(expected)'",
                confidence: 1.0
            )
        } catch {
            return AssertionEvaluation(
                passed: false,
                assertionType: "element_value",
                expected: expected,
                actual: nil,
                message: "Error locating element: \(error.localizedDescription)",
                confidence: 0.0
            )
        }
    }

    private func evaluateFileExists(expected: String?) throws -> AssertionEvaluation {
        guard let expected = expected else {
            return AssertionEvaluation(
                passed: false,
                assertionType: "file_exists",
                expected: expected,
                actual: nil,
                message: "Expected file path required",
                confidence: 0.0
            )
        }

        let fileManager = FileManager.default
        let exists = fileManager.fileExists(atPath: expected)

        return AssertionEvaluation(
            passed: exists,
            assertionType: "file_exists",
            expected: expected,
            actual: exists ? "exists" : "not found",
            message: exists ? "File exists" : "File not found at \(expected)",
            confidence: 1.0
        )
    }

    private func evaluateFileSize(expected: String?) throws -> AssertionEvaluation {
        guard let expected = expected else {
            return AssertionEvaluation(
                passed: false,
                assertionType: "file_size",
                expected: expected,
                actual: nil,
                message: "Expected JSON with path and size constraints required",
                confidence: 0.0
            )
        }

        do {
            if let jsonData = expected.data(using: .utf8),
               let jsonDict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let filePath = jsonDict["path"] as? String {

                let fileManager = FileManager.default
                guard let attrs = try? fileManager.attributesOfItem(atPath: filePath) as NSDictionary,
                      let fileSize = attrs.fileSize() as NSNumber? else {
                    return AssertionEvaluation(
                        passed: false,
                        assertionType: "file_size",
                        expected: expected,
                        actual: nil,
                        message: "Cannot read file size",
                        confidence: 0.0
                    )
                }

                let size = fileSize.int64Value
                let minBytes = (jsonDict["min_bytes"] as? NSNumber)?.int64Value ?? 0
                let maxBytes = (jsonDict["max_bytes"] as? NSNumber)?.int64Value ?? Int64.max

                let passed = size >= minBytes && size <= maxBytes
                return AssertionEvaluation(
                    passed: passed,
                    assertionType: "file_size",
                    expected: expected,
                    actual: String(size),
                    message: passed ? "File size in expected range" : "File size \(size) not in range [\(minBytes), \(maxBytes)]",
                    confidence: 1.0
                )
            }

            return AssertionEvaluation(
                passed: false,
                assertionType: "file_size",
                expected: expected,
                actual: nil,
                message: "Invalid JSON format for file_size",
                confidence: 0.0
            )
        } catch {
            return AssertionEvaluation(
                passed: false,
                assertionType: "file_size",
                expected: expected,
                actual: nil,
                message: "Error parsing file_size JSON: \(error.localizedDescription)",
                confidence: 0.0
            )
        }
    }

    private func evaluateFileContent(expected: String?) throws -> AssertionEvaluation {
        guard let expected = expected else {
            return AssertionEvaluation(
                passed: false,
                assertionType: "file_content",
                expected: expected,
                actual: nil,
                message: "Expected JSON with path and content pattern required",
                confidence: 0.0
            )
        }

        do {
            if let jsonData = expected.data(using: .utf8),
               let jsonDict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let filePath = jsonDict["path"] as? String,
               let searchPattern = jsonDict["contains"] as? String {

                let fileManager = FileManager.default
                guard fileManager.fileExists(atPath: filePath),
                      let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
                    return AssertionEvaluation(
                        passed: false,
                        assertionType: "file_content",
                        expected: expected,
                        actual: nil,
                        message: "Cannot read file content",
                        confidence: 0.0
                    )
                }

                let passed = content.contains(searchPattern)
                return AssertionEvaluation(
                    passed: passed,
                    assertionType: "file_content",
                    expected: searchPattern,
                    actual: passed ? "found" : "not found",
                    message: passed ? "File contains expected pattern" : "Pattern not found in file",
                    confidence: 1.0
                )
            }

            return AssertionEvaluation(
                passed: false,
                assertionType: "file_content",
                expected: expected,
                actual: nil,
                message: "Invalid JSON format for file_content",
                confidence: 0.0
            )
        } catch {
            return AssertionEvaluation(
                passed: false,
                assertionType: "file_content",
                expected: expected,
                actual: nil,
                message: "Error parsing file_content JSON: \(error.localizedDescription)",
                confidence: 0.0
            )
        }
    }

    private func evaluateFileCount(expected: String?) throws -> AssertionEvaluation {
        guard let expected = expected else {
            return AssertionEvaluation(
                passed: false,
                assertionType: "file_count",
                expected: expected,
                actual: nil,
                message: "Expected JSON with path and file count required",
                confidence: 0.0
            )
        }

        do {
            if let jsonData = expected.data(using: .utf8),
               let jsonDict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let directoryPath = jsonDict["path"] as? String {

                let fileManager = FileManager.default
                guard fileManager.fileExists(atPath: directoryPath) else {
                    return AssertionEvaluation(
                        passed: false,
                        assertionType: "file_count",
                        expected: expected,
                        actual: nil,
                        message: "Directory not found",
                        confidence: 0.0
                    )
                }

                let files = try fileManager.contentsOfDirectory(atPath: directoryPath)
                let count = files.count
                let expectedCount = (jsonDict["count"] as? NSNumber)?.intValue ?? 0

                let passed = count == expectedCount
                return AssertionEvaluation(
                    passed: passed,
                    assertionType: "file_count",
                    expected: String(expectedCount),
                    actual: String(count),
                    message: passed ? "File count matches" : "Expected \(expectedCount) files, found \(count)",
                    confidence: 1.0
                )
            }

            return AssertionEvaluation(
                passed: false,
                assertionType: "file_count",
                expected: expected,
                actual: nil,
                message: "Invalid JSON format for file_count",
                confidence: 0.0
            )
        } catch {
            return AssertionEvaluation(
                passed: false,
                assertionType: "file_count",
                expected: expected,
                actual: nil,
                message: "Error reading directory: \(error.localizedDescription)",
                confidence: 0.0
            )
        }
    }

    private func evaluateClipboardContains(expected: String?) -> AssertionEvaluation {
        guard let expected = expected else {
            return AssertionEvaluation(
                passed: false,
                assertionType: "clipboard_contains",
                expected: expected,
                actual: nil,
                message: "Expected text pattern required",
                confidence: 0.0
            )
        }

        let pasteboard = NSPasteboard.general
        guard let clipboardContent = pasteboard.string(forType: .string) else {
            return AssertionEvaluation(
                passed: false,
                assertionType: "clipboard_contains",
                expected: expected,
                actual: nil,
                message: "Clipboard is empty",
                confidence: 0.0
            )
        }

        let passed = clipboardContent.contains(expected)
        return AssertionEvaluation(
            passed: passed,
            assertionType: "clipboard_contains",
            expected: expected,
            actual: clipboardContent,
            message: passed ? "Clipboard contains expected text" : "Clipboard does not contain expected text",
            confidence: 1.0
        )
    }

    private func evaluateNotificationAppeared(expected: String?) -> AssertionEvaluation {
        guard let expected = expected else {
            return AssertionEvaluation(
                passed: false,
                assertionType: "notification_appeared",
                expected: expected,
                actual: nil,
                message: "Expected notification identifier required",
                confidence: 0.0
            )
        }

        return AssertionEvaluation(
            passed: false,
            assertionType: "notification_appeared",
            expected: expected,
            actual: nil,
            message: "Notification monitoring not implemented",
            confidence: 0.0
        )
    }

    private func evaluateProcessRunning(expected: String?) -> AssertionEvaluation {
        guard let expected = expected else {
            return AssertionEvaluation(
                passed: false,
                assertionType: "process_running",
                expected: expected,
                actual: nil,
                message: "Expected process name required",
                confidence: 0.0
            )
        }

        let workspace = NSWorkspace.shared
        let running = workspace.runningApplications.contains { app in
            app.bundleIdentifier == expected || app.executableURL?.lastPathComponent == expected
        }

        return AssertionEvaluation(
            passed: running,
            assertionType: "process_running",
            expected: expected,
            actual: running ? "running" : "not running",
            message: running ? "Process is running" : "Process '\(expected)' is not running",
            confidence: 1.0
        )
    }

    private func evaluateStepDuration(expected: String?, stepStartTime: Date) -> AssertionEvaluation {
        guard let expected = expected, let maxDuration = TimeInterval(expected) else {
            return AssertionEvaluation(
                passed: false,
                assertionType: "step_duration_under",
                expected: expected,
                actual: nil,
                message: "Expected max duration in seconds required",
                confidence: 0.0
            )
        }

        let elapsed = Date().timeIntervalSince(stepStartTime)
        let passed = elapsed <= maxDuration

        return AssertionEvaluation(
            passed: passed,
            assertionType: "step_duration_under",
            expected: expected,
            actual: String(format: "%.2f", elapsed),
            message: passed ? "Step completed in \(String(format: "%.2f", elapsed))s" : "Step took \(String(format: "%.2f", elapsed))s, exceeded \(maxDuration)s",
            confidence: 1.0
        )
    }

    private func evaluateTotalDuration(expected: String?, runStartTime: Date) -> AssertionEvaluation {
        guard let expected = expected, let maxDuration = TimeInterval(expected) else {
            return AssertionEvaluation(
                passed: false,
                assertionType: "total_duration_under",
                expected: expected,
                actual: nil,
                message: "Expected max total duration in seconds required",
                confidence: 0.0
            )
        }

        let elapsed = Date().timeIntervalSince(runStartTime)
        let passed = elapsed <= maxDuration

        return AssertionEvaluation(
            passed: passed,
            assertionType: "total_duration_under",
            expected: expected,
            actual: String(format: "%.2f", elapsed),
            message: passed ? "Total duration \(String(format: "%.2f", elapsed))s" : "Total duration \(String(format: "%.2f", elapsed))s exceeded \(maxDuration)s",
            confidence: 1.0
        )
    }
}
