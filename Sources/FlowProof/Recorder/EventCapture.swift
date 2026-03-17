import Cocoa
import CoreGraphics

/// Captures global mouse and keyboard events using CGEventTap
class EventCapture {
    /// Whether recording is active
    private(set) var isRecording = false

    /// Captured raw events
    private(set) var capturedEvents: [CapturedEvent] = []

    /// Callback for real-time event streaming
    var onEventCaptured: ((CapturedEvent) -> Void)?

    /// The PID of the target app being recorded
    private var targetPid: pid_t?

    /// The event tap
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Static reference to self for the C callback
    private static var shared: EventCapture?

    deinit {
        stopRecording()
    }

    /// Start recording events for a target application
    func startRecording(targetPid: pid_t) throws {
        guard !isRecording else { return }

        self.targetPid = targetPid
        EventCapture.shared = self

        let eventMask1: CGEventMask = (1 << CGEventType.leftMouseDown.rawValue) |
                                       (1 << CGEventType.leftMouseUp.rawValue) |
                                       (1 << CGEventType.rightMouseDown.rawValue) |
                                       (1 << CGEventType.rightMouseUp.rawValue) |
                                       (1 << CGEventType.mouseMoved.rawValue)
        let eventMask2: CGEventMask = (1 << CGEventType.leftMouseDragged.rawValue) |
                                       (1 << CGEventType.rightMouseDragged.rawValue) |
                                       (1 << CGEventType.keyDown.rawValue) |
                                       (1 << CGEventType.keyUp.rawValue) |
                                       (1 << CGEventType.scrollWheel.rawValue) |
                                       (1 << CGEventType.flagsChanged.rawValue)
        let eventMask: CGEventMask = eventMask1 | eventMask2

        guard let eventTap = CGEvent.tapCreate(
            tap: CGEventTapLocation.cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: EventCapture.tapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw RecorderError.eventTapFailed
        }

        self.eventTap = eventTap
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        self.runLoopSource = runLoopSource

        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        isRecording = true
    }

    /// Stop recording
    func stopRecording() {
        guard isRecording else { return }

        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }

        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }

        eventTap = nil
        targetPid = nil
        isRecording = false
    }

    /// Clear captured events
    func clearEvents() {
        capturedEvents.removeAll()
    }

    /// The CGEventTap callback (must be a C function)
    private static let tapCallback: CGEventTapCallBack = { proxy, type, event, refcon in
        guard let refcon = refcon else { return Unmanaged.passUnretained(event) }

        let capture = Unmanaged<EventCapture>.fromOpaque(refcon).takeUnretainedValue()

        if let processedEvent = capture.processEvent(event, type: type) {
            capture.capturedEvents.append(processedEvent)
            capture.onEventCaptured?(processedEvent)
        }

        return Unmanaged.passUnretained(event)
    }

    /// Process a single captured event
    private func processEvent(_ event: CGEvent, type: CGEventType) -> CapturedEvent? {
        guard let targetPid = targetPid else { return nil }

        let timestamp = Date()
        let position = event.location

        let elementInfo = elementAtPosition(position, pid: targetPid)

        var eventType: CapturedEventType?
        var keyCode: CGKeyCode?
        var characters: String?

        switch type {
        case .leftMouseDown:
            let clickCount = event.getIntegerValueField(.mouseEventClickState)
            eventType = .mouseDown(button: 0, clickCount: Int(clickCount))

        case .leftMouseUp:
            eventType = .mouseUp(button: 0)

        case .rightMouseDown:
            let clickCount = event.getIntegerValueField(.mouseEventClickState)
            eventType = .mouseDown(button: 1, clickCount: Int(clickCount))

        case .rightMouseUp:
            eventType = .mouseUp(button: 1)

        case .mouseMoved:
            eventType = .mouseMoved

        case .leftMouseDragged, .rightMouseDragged:
            eventType = .mouseDragged

        case .keyDown:
            keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            var charLength: Int = 0
            var charBuffer = [UniChar](repeating: 0, count: 4)
            event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &charLength, unicodeString: &charBuffer)
            characters = charLength > 0 ? String(charBuffer.prefix(charLength).compactMap { Unicode.Scalar($0).map { Character($0) } }) : nil
            eventType = .keyDown

        case .keyUp:
            keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            var charLength: Int = 0
            var charBuffer = [UniChar](repeating: 0, count: 4)
            event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &charLength, unicodeString: &charBuffer)
            characters = charLength > 0 ? String(charBuffer.prefix(charLength).compactMap { Unicode.Scalar($0).map { Character($0) } }) : nil
            eventType = .keyUp

        case .scrollWheel:
            let deltaX = event.getDoubleValueField(.scrollWheelEventDeltaAxis2)
            let deltaY = event.getDoubleValueField(.scrollWheelEventDeltaAxis1)
            eventType = .scrollWheel(deltaX: deltaX, deltaY: deltaY)

        case .flagsChanged:
            eventType = .flagsChanged

        default:
            return nil
        }

        guard let eventType = eventType else { return nil }

        let modifiers = event.flags

        return CapturedEvent(
            timestamp: timestamp,
            eventType: eventType,
            position: position,
            keyCode: keyCode,
            characters: characters,
            modifiers: modifiers,
            elementInfo: elementInfo,
            targetPid: targetPid
        )
    }

    /// Get the accessibility element at a screen position
    private func elementAtPosition(_ point: CGPoint, pid: pid_t) -> ElementInfo? {
        let appElement = AXUIElementCreateApplication(pid)

        var foundElement: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(appElement, Float(point.x), Float(point.y), &foundElement)

        guard result == .success, let element = foundElement else {
            return nil
        }

        var role: String?
        var label: String?
        var value: String?
        var identifier: String?
        var frame: CGRect?
        var title: String?

        func axAttr(_ attr: String, from el: AXUIElement) -> CFTypeRef? {
            var val: CFTypeRef?
            let err = AXUIElementCopyAttributeValue(el, attr as CFString, &val)
            return err == .success ? val : nil
        }

        role = axAttr(kAXRoleAttribute as String, from: element) as? String
        label = axAttr(kAXTitleAttribute as String, from: element) as? String
        value = axAttr(kAXValueAttribute as String, from: element) as? String
        identifier = axAttr("AXIdentifier", from: element) as? String
        title = axAttr(kAXTitleAttribute as String, from: element) as? String

        if let posValue = axAttr(kAXPositionAttribute as String, from: element),
           let sizeValue = axAttr(kAXSizeAttribute as String, from: element) {
            var point = CGPoint.zero
            var size = CGSize.zero
            if AXValueGetValue(posValue as! AXValue, .cgPoint, &point),
               AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) {
                frame = CGRect(origin: point, size: size)
            }
        }

        return ElementInfo(
            role: role,
            label: label ?? title,
            value: value,
            identifier: identifier,
            frame: frame,
            title: title
        )
    }
}

/// Raw captured event with timestamp
struct CapturedEvent {
    let timestamp: Date
    let eventType: CapturedEventType
    let position: CGPoint?
    let keyCode: CGKeyCode?
    let characters: String?
    let modifiers: CGEventFlags
    let elementInfo: ElementInfo?
    let targetPid: pid_t
}

enum CapturedEventType: Equatable {
    case mouseDown(button: Int, clickCount: Int)
    case mouseUp(button: Int)
    case mouseDragged
    case mouseMoved
    case keyDown
    case keyUp
    case scrollWheel(deltaX: Double, deltaY: Double)
    case flagsChanged
}

/// Info about the AX element at the event position
struct ElementInfo {
    let role: String?
    let label: String?
    let value: String?
    let identifier: String?
    let frame: CGRect?
    let title: String?
}

enum RecorderError: LocalizedError {
    case eventTapFailed
    case invalidTarget

    var errorDescription: String? {
        switch self {
        case .eventTapFailed:
            return "Failed to create event tap. Ensure accessibility permissions are granted."
        case .invalidTarget:
            return "Invalid target application."
        }
    }
}
