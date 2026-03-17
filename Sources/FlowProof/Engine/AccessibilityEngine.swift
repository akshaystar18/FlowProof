import AppKit
import ApplicationServices

// MARK: - Error Types

enum AccessibilityError: Error, CustomStringConvertible {
    case accessibilityNotEnabled
    case invalidElement
    case attributeNotFound
    case actionFailed(String)
    case elementNotFound
    case timeout
    case invalidPID

    var description: String {
        switch self {
        case .accessibilityNotEnabled:
            return "Accessibility permissions not enabled"
        case .invalidElement:
            return "Invalid AXUIElement"
        case .attributeNotFound:
            return "Attribute not found on element"
        case .actionFailed(let action):
            return "Failed to perform action: \(action)"
        case .elementNotFound:
            return "Element not found"
        case .timeout:
            return "Operation timed out"
        case .invalidPID:
            return "Invalid process ID"
        }
    }
}

// MARK: - Accessibility Engine

/// Wraps macOS Accessibility API for UI element discovery and manipulation
class AccessibilityEngine {

    // MARK: - Static Permissions

    /// Check if accessibility permissions are granted
    static func isAccessibilityEnabled() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Request accessibility access (shows system dialog)
    static func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Element Retrieval

    /// Get the AXUIElement for a running application by PID
    func applicationElement(pid: pid_t) -> AXUIElement {
        return AXUIElementCreateApplication(pid)
    }

    /// Get the focused/frontmost application element
    func frontmostApplicationElement() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        return AXUIElementCreateApplication(app.processIdentifier)
    }

    // MARK: - Element Finding

    /// Find elements matching an AccessibilityTarget in the given app
    func findElements(matching target: AccessibilityTarget, in app: AXUIElement) -> [AXUIElement] {
        var results: [AXUIElement] = []
        searchTree(app, matching: target, results: &results, depth: 0, maxDepth: 20)
        return results
    }

    /// Recursive search through AX tree
    private func searchTree(_ element: AXUIElement, matching target: AccessibilityTarget, results: inout [AXUIElement], depth: Int, maxDepth: Int) {
        guard depth < maxDepth else { return }

        // Check if this element matches the target
        if elementMatches(element, target: target) {
            results.append(element)
        }

        // Get children and recursively search
        if let children = getChildren(element) {
            for child in children {
                searchTree(child, matching: target, results: &results, depth: depth + 1, maxDepth: maxDepth)
            }
        }
    }

    /// Check if an element matches the given accessibility target
    /// AccessibilityTarget has optional properties: role, label, value, identifier
    /// All non-nil properties must match for the element to be considered a match.
    private func elementMatches(_ element: AXUIElement, target: AccessibilityTarget) -> Bool {
        // If role is specified, it must match
        if let targetRole = target.role {
            guard let elementRole = getRole(element), elementRole == targetRole else {
                return false
            }
        }

        // If label is specified, it must match
        if let targetLabel = target.label {
            guard let elementLabel = getLabel(element),
                  elementLabel.localizedCaseInsensitiveContains(targetLabel) else {
                return false
            }
        }

        // If value is specified, it must match
        if let targetValue = target.value {
            guard let elementValue = getAttribute(kAXValueAttribute as String, from: element) as? String,
                  elementValue == targetValue else {
                return false
            }
        }

        // If identifier is specified, it must match
        if let targetIdentifier = target.identifier {
            guard let elementIdentifier = getAttribute("AXIdentifier", from: element) as? String,
                  elementIdentifier == targetIdentifier else {
                return false
            }
        }

        // At least one property must have been specified
        return target.role != nil || target.label != nil || target.value != nil || target.identifier != nil
    }

    private func getRole(_ element: AXUIElement) -> String? {
        return getAttribute("AXRole", from: element) as? String
    }

    private func getLabel(_ element: AXUIElement) -> String? {
        if let label = getAttribute("AXLabel", from: element) as? String {
            return label
        }
        if let title = getAttribute("AXTitle", from: element) as? String {
            return title
        }
        return nil
    }

    /// Get value attribute from element
    func getValue(_ element: AXUIElement) -> String? {
        return getAttribute(kAXValueAttribute as String, from: element) as? String
    }

    /// Check if element is focused
    func isFocused(_ element: AXUIElement) -> Bool {
        if let focused = getAttribute(kAXFocusedAttribute as String, from: element) as? Bool {
            return focused
        }
        return false
    }

    // MARK: - Actions

    /// Perform a click action on an element
    func clickElement(_ element: AXUIElement) throws {
        let error = AXUIElementPerformAction(element, kAXPressAction as CFString)
        guard error == .success else {
            throw AccessibilityError.actionFailed("click")
        }
    }

    /// Set value of an element (for text fields)
    func setValue(_ value: String, on element: AXUIElement) throws {
        let cfValue = value as CFTypeRef
        let error = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, cfValue)
        guard error == .success else {
            throw AccessibilityError.actionFailed("setValue")
        }
    }

    /// Perform AXAction (like AXPress, AXConfirm, etc.)
    func performAction(_ action: String, on element: AXUIElement) throws {
        let error = AXUIElementPerformAction(element, action as CFString)
        guard error == .success else {
            throw AccessibilityError.actionFailed(action)
        }
    }

    // MARK: - Attribute Retrieval

    /// Get attribute value from element
    func getAttribute(_ attribute: String, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success else {
            return nil
        }
        return value
    }

    /// Get element's text/title/value as string
    func getElementText(_ element: AXUIElement) -> String? {
        // Try value first (for text fields, etc.)
        if let value = getAttribute(kAXValueAttribute as String, from: element) as? String {
            return value
        }
        // Try title
        if let title = getAttribute(kAXTitleAttribute as String, from: element) as? String {
            return title
        }
        // Try label
        if let label = getAttribute("AXLabel", from: element) as? String {
            return label
        }
        return nil
    }

    /// Get element position (CGPoint)
    func getPosition(_ element: AXUIElement) -> CGPoint? {
        guard let value = getAttribute(kAXPositionAttribute as String, from: element) else {
            return nil
        }
        var point = CGPoint.zero
        if AXValueGetValue(value as! AXValue, .cgPoint, &point) {
            return point
        }
        return nil
    }

    /// Get element size
    func getSize(_ element: AXUIElement) -> CGSize? {
        guard let value = getAttribute(kAXSizeAttribute as String, from: element) else {
            return nil
        }
        var size = CGSize.zero
        if AXValueGetValue(value as! AXValue, .cgSize, &size) {
            return size
        }
        return nil
    }

    /// Get element frame (position + size)
    func getFrame(_ element: AXUIElement) -> CGRect? {
        guard let position = getPosition(element),
              let size = getSize(element) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    /// Check if element is visible/on screen
    func isElementVisible(_ element: AXUIElement) -> Bool {
        // An element is visible if it has a valid frame and is not hidden
        if let frame = getFrame(element), frame.width > 0, frame.height > 0 {
            // Check AXHidden attribute
            if let hidden = getAttribute(kAXHiddenAttribute as String, from: element) as? Bool {
                return !hidden
            }
            return true
        }
        return false
    }

    /// Check if element is enabled
    func isElementEnabled(_ element: AXUIElement) -> Bool {
        if let enabled = getAttribute(kAXEnabledAttribute as String, from: element) as? Bool {
            return enabled
        }
        return true
    }

    /// Get all children of an element
    func getChildren(_ element: AXUIElement) -> [AXUIElement]? {
        guard let childrenRef = getAttribute(kAXChildrenAttribute as String, from: element) else {
            return nil
        }

        guard let children = childrenRef as? [AXUIElement] else {
            return nil
        }

        return children
    }

    // MARK: - File Upload

    /// Set a file URL on a file-chooser element (for upload actions)
    func setFileURL(_ element: AXUIElement, path: String) throws {
        let url = URL(fileURLWithPath: path)
        let cfValue = url.absoluteString as CFTypeRef
        let error = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, cfValue)
        guard error == .success else {
            throw AccessibilityError.actionFailed("setFileURL")
        }
    }

    // MARK: - Menu Navigation

    /// Activate a menu bar item by title in the given application element
    func activateMenu(_ appElement: AXUIElement, item: String) throws {
        guard let menuBar = getAttribute(kAXMenuBarAttribute as String, from: appElement) else {
            throw AccessibilityError.elementNotFound
        }
        let menuBarElement = menuBar as! AXUIElement
        guard let children = getChildren(menuBarElement) else {
            throw AccessibilityError.elementNotFound
        }
        for child in children {
            if let title = getLabel(child), title.localizedCaseInsensitiveContains(item) {
                let err = AXUIElementPerformAction(child, kAXPressAction as CFString)
                guard err == .success else {
                    throw AccessibilityError.actionFailed("activateMenu:\(item)")
                }
                return
            }
        }
        throw AccessibilityError.elementNotFound
    }

    // MARK: - Waiting

    /// Wait for an element matching target to appear, with timeout
    func waitForElement(matching target: AccessibilityTarget, in app: AXUIElement, timeout: TimeInterval, pollInterval: TimeInterval) async throws -> AXUIElement {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let elements = findElements(matching: target, in: app)
            if !elements.isEmpty {
                return elements[0]
            }

            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }

        throw AccessibilityError.timeout
    }
}
