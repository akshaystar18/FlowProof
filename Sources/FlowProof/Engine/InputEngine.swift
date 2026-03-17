import CoreGraphics
import AppKit

// MARK: - Mouse Button Enum

enum MouseButton: UInt32 {
    case left = 0
    case right = 1
    case center = 2
}

// MARK: - Input Engine

/// Simulates mouse and keyboard input via CGEvent API
class InputEngine {

    // MARK: - Mouse Input

    /// Click at a screen coordinate
    func click(at point: CGPoint, button: MouseButton = .left, clickCount: Int = 1, modifiers: CGEventFlags = []) {
        let eventType: CGEventType = button == .left ? .leftMouseDown : (button == .right ? .rightMouseDown : .otherMouseDown)
        let eventTypeUp: CGEventType = button == .left ? .leftMouseUp : (button == .right ? .rightMouseUp : .otherMouseUp)
        let cgButton = CGMouseButton(rawValue: button.rawValue) ?? .left

        // Move to position
        moveMouse(to: point)

        // Perform click(s)
        for _ in 0..<clickCount {
            if let downEvent = CGEvent(mouseEventSource: nil, mouseType: eventType, mouseCursorPosition: point, mouseButton: cgButton) {
                downEvent.flags = modifiers
                downEvent.post(tap: CGEventTapLocation.cghidEventTap)
            }

            if let upEvent = CGEvent(mouseEventSource: nil, mouseType: eventTypeUp, mouseCursorPosition: point, mouseButton: cgButton) {
                upEvent.flags = modifiers
                upEvent.post(tap: CGEventTapLocation.cghidEventTap)
            }
        }
    }

    /// Double click
    func doubleClick(at point: CGPoint) {
        click(at: point, button: .left, clickCount: 2)
    }

    /// Right click
    func rightClick(at point: CGPoint) {
        click(at: point, button: .right, clickCount: 1)
    }

    /// Drag from one point to another
    func drag(from start: CGPoint, to end: CGPoint, duration: TimeInterval = 0.5) {
        // Move to start
        moveMouse(to: start)

        // Mouse down
        if let downEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: start, mouseButton: .left) {
            downEvent.post(tap: CGEventTapLocation.cghidEventTap)
        }

        // Calculate number of steps for smooth dragging
        let steps = max(10, Int(duration * 60)) // Assume 60 FPS
        let stepDuration = duration / Double(steps)

        for i in 1...steps {
            let progress = Double(i) / Double(steps)
            let currentPoint = CGPoint(
                x: start.x + (end.x - start.x) * progress,
                y: start.y + (end.y - start.y) * progress
            )

            if let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: currentPoint, mouseButton: .left) {
                moveEvent.post(tap: CGEventTapLocation.cghidEventTap)
            }

            Thread.sleep(forTimeInterval: stepDuration)
        }

        // Mouse up
        if let upEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: end, mouseButton: .left) {
            upEvent.post(tap: CGEventTapLocation.cghidEventTap)
        }
    }

    /// Move mouse to position
    func moveMouse(to point: CGPoint) {
        if let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) {
            moveEvent.post(tap: CGEventTapLocation.cghidEventTap)
        }
    }

    /// Scroll at a position
    func scroll(at point: CGPoint, direction: ScrollDirection, amount: Int = 3) {
        // Move to position first
        moveMouse(to: point)

        let wheelDelta: Int32 = direction == .up ? Int32(amount) : Int32(-amount)

        if let scrollEvent = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: wheelDelta, wheel2: 0, wheel3: 0) {
            scrollEvent.location = point
            scrollEvent.post(tap: CGEventTapLocation.cghidEventTap)
        }
    }

    // MARK: - Keyboard Input

    /// Type a string of text character by character
    func typeText(_ text: String, delayPerKey: TimeInterval = 0.02) {
        for character in text {
            let keyCode = characterToKeyCode(character)

            // Determine if shift is needed
            let needsShift = character.isUppercase || "!@#$%^&*()_+{}|:\"<>?".contains(character)

            // Key down
            if let downEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) {
                if needsShift {
                    downEvent.flags.insert(.maskShift)
                }
                downEvent.post(tap: CGEventTapLocation.cghidEventTap)
            }

            // Key up
            if let upEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) {
                if needsShift {
                    upEvent.flags.insert(.maskShift)
                }
                upEvent.post(tap: CGEventTapLocation.cghidEventTap)
            }

            Thread.sleep(forTimeInterval: delayPerKey)
        }
    }

    /// Press a keyboard shortcut (e.g., "cmd+s", "cmd+shift+e")
    func pressKeyCombo(_ combo: String) throws {
        let (keyCode, modifiers) = try parseKeyCombo(combo)
        pressKey(keyCode, modifiers: modifiers)
    }

    /// Press a single key with optional modifiers
    func pressKey(_ keyCode: CGKeyCode, modifiers: CGEventFlags = []) {
        if let downEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) {
            downEvent.flags = modifiers
            downEvent.post(tap: CGEventTapLocation.cghidEventTap)
        }

        if let upEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) {
            upEvent.flags = modifiers
            upEvent.post(tap: CGEventTapLocation.cghidEventTap)
        }
    }

    // MARK: - Helpers

    /// Parse key combo string to keyCode + modifiers (e.g., "cmd+shift+s")
    private func parseKeyCombo(_ combo: String) throws -> (keyCode: CGKeyCode, modifiers: CGEventFlags) {
        let components = combo.lowercased().split(separator: "+").map(String.init)

        var modifiers: CGEventFlags = []

        for component in components.dropLast() {
            switch component {
            case "cmd", "command":
                modifiers.insert(.maskCommand)
            case "shift":
                modifiers.insert(.maskShift)
            case "alt", "option":
                modifiers.insert(.maskAlternate)
            case "ctrl", "control":
                modifiers.insert(.maskControl)
            default:
                break
            }
        }

        guard let lastComponent = components.last else {
            throw NSError(domain: "InputEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Empty key combo"])
        }

        guard let keyCode = Self.keyCodeMap[lastComponent] else {
            throw NSError(domain: "InputEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown key: \(lastComponent)"])
        }

        return (keyCode, modifiers)
    }

    /// Map character to key code
    private func characterToKeyCode(_ char: Character) -> CGKeyCode {
        let lowerChar = char.lowercased().first ?? char
        return Self.keyCodeMap[String(lowerChar)] ?? 0
    }

    // MARK: - Key Code Map

    /// Comprehensive key code mapping
    static let keyCodeMap: [String: CGKeyCode] = [
        // Letters
        "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5, "h": 4, "i": 34, "j": 38,
        "k": 40, "l": 37, "m": 46, "n": 45, "o": 31, "p": 35, "q": 12, "r": 15, "s": 1, "t": 17,
        "u": 32, "v": 9, "w": 13, "x": 7, "y": 16, "z": 6,

        // Numbers
        "0": 29, "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26, "8": 28, "9": 25,

        // Function Keys
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98,
        "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "f13": 105, "f14": 107, "f15": 113, "f16": 106, "f17": 64, "f18": 79, "f19": 80, "f20": 90,

        // Arrows
        "up": 126, "down": 125, "left": 123, "right": 124,

        // Control Keys
        "return": 36, "enter": 36, "tab": 48, "space": 49,
        "delete": 51, "backspace": 51, "escape": 53,
        "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
        "insert": 114, "help": 114,

        // Special Characters (with shift on US keyboard)
        "!": 18, "@": 19, "#": 20, "$": 21, "%": 23, "^": 22, "&": 26, "*": 28,
        "(": 25, ")": 29, "-": 27, "_": 27, "=": 24, "+": 24,
        "[": 33, "]": 30, "{": 33, "}": 30, "\\": 42, "|": 42,
        ";": 41, ":": 41, "'": 39, "\"": 39,
        ",": 43, "<": 43, ".": 47, ">": 47, "/": 44, "?": 44,
        "`": 50, "~": 50,

        // Key names
        "left shift": 56, "right shift": 60, "left command": 55, "right command": 54,
        "left option": 58, "right option": 61, "left control": 59, "right control": 62,
    ]
}
