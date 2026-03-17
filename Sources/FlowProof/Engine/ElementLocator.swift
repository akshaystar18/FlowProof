import Foundation
import AppKit
import CoreGraphics

// MARK: - Located Element

struct LocatedElement {
    let screenPosition: CGPoint
    let frame: CGRect?
    let axElement: AXUIElement?
    let strategy: String
    let confidence: Double
}

// MARK: - Element Locator

/// Coordinates all targeting strategies to find UI elements
class ElementLocator {
    let accessibility: AccessibilityEngine
    let input: InputEngine
    let vision: VisionEngine

    init(accessibility: AccessibilityEngine = AccessibilityEngine(),
         input: InputEngine = InputEngine(),
         vision: VisionEngine = VisionEngine()) {
        self.accessibility = accessibility
        self.input = input
        self.vision = vision
    }

    // MARK: - Main Locator

    /// Find an element using the target specification, returns screen coordinate + optional AX element
    func locate(_ target: ElementTarget, in appPid: pid_t) async throws -> LocatedElement {
        // Try each targeting strategy in order

        // 1. Try accessibility-based targeting
        if let axTarget = target.accessibility {
            if let located = try tryAccessibility(axTarget, pid: appPid) {
                return located
            }
        }

        // 2. Try text/OCR-based targeting
        if let textTarget = target.textOcr {
            if let located = try tryTextOCR(textTarget, pid: appPid) {
                return located
            }
        }

        // 3. Try image matching
        if let imageTarget = target.imageMatch {
            if let located = try tryImageMatch(imageTarget, pid: appPid) {
                return located
            }
        }

        // 4. Try direct coordinates
        if let coords = target.coordinates {
            return tryCoordinates(coords)
        }

        // 5. Try relative positioning
        if let relativeTarget = target.relative {
            if let located = try await tryRelative(relativeTarget, pid: appPid) {
                return located
            }
        }

        // 6. Try hybrid (multiple strategies)
        if let hybridTargets = target.hybrid {
            return try await tryHybrid(hybridTargets, pid: appPid)
        }

        // If nothing matched, throw error
        throw NSError(domain: "ElementLocator", code: -1, userInfo: [NSLocalizedDescriptionKey: "No targeting strategy available"])
    }

    // MARK: - Strategy: Accessibility

    /// Try each accessibility-based matching strategy
    private func tryAccessibility(_ target: AccessibilityTarget, pid: pid_t) throws -> LocatedElement? {
        let appElement = accessibility.applicationElement(pid: pid)
        let elements = accessibility.findElements(matching: target, in: appElement)

        guard let element = elements.first else {
            return nil
        }

        guard let frame = accessibility.getFrame(element) else {
            return nil
        }

        let centerPoint = CGPoint(x: frame.midX, y: frame.midY)

        return LocatedElement(
            screenPosition: centerPoint,
            frame: frame,
            axElement: element,
            strategy: "accessibility",
            confidence: 1.0
        )
    }

    // MARK: - Strategy: Text/OCR

    /// Try OCR-based text matching on screen
    private func tryTextOCR(_ text: String, pid: pid_t) throws -> LocatedElement? {
        // Capture the window
        let screenshot = try vision.captureWindow(pid: pid)

        // Find text matches
        let matches = try vision.findText(text, in: screenshot, matchMode: .contains)

        guard let firstMatch = matches.first else {
            return nil
        }

        let centerPoint = CGPoint(x: firstMatch.boundingBox.midX, y: firstMatch.boundingBox.midY)

        return LocatedElement(
            screenPosition: centerPoint,
            frame: firstMatch.boundingBox,
            axElement: nil,
            strategy: "text_ocr",
            confidence: Double(firstMatch.confidence)
        )
    }

    // MARK: - Strategy: Image Matching

    /// Try template matching with provided image
    private func tryImageMatch(_ target: ImageMatchTarget, pid: pid_t) throws -> LocatedElement? {
        // Capture the window
        let screenshot = try vision.captureWindow(pid: pid)

        // Load the template image from the provided path
        guard let templateImage = NSImage(contentsOfFile: target.template) else {
            return nil
        }

        // Find template matches
        let matches = try vision.findTemplate(templateImage, in: screenshot, threshold: target.threshold ?? 0.85)

        guard let firstMatch = matches.first else {
            return nil
        }

        let centerPoint = CGPoint(x: firstMatch.midX, y: firstMatch.midY)

        return LocatedElement(
            screenPosition: centerPoint,
            frame: firstMatch,
            axElement: nil,
            strategy: "image_match",
            confidence: target.threshold ?? 0.85
        )
    }

    // MARK: - Strategy: Direct Coordinates

    /// Direct coordinate specification
    private func tryCoordinates(_ coords: Coordinates) -> LocatedElement {
        let point = CGPoint(x: coords.x, y: coords.y)
        return LocatedElement(
            screenPosition: point,
            frame: nil,
            axElement: nil,
            strategy: "coordinates",
            confidence: 1.0
        )
    }

    // MARK: - Strategy: Relative

    /// Locate element relative to another element
    private func tryRelative(_ target: RelativeTarget, pid: pid_t) async throws -> LocatedElement? {
        // First, locate the reference element
        let referenceElement = try await locate(target.relativeTo, in: pid)

        guard let referenceFrame = referenceElement.frame else {
            return nil
        }

        let offset = target.offset
        let relativePoint = CGPoint(
            x: referenceElement.screenPosition.x + offset.x,
            y: referenceElement.screenPosition.y + offset.y
        )

        return LocatedElement(
            screenPosition: relativePoint,
            frame: nil,
            axElement: nil,
            strategy: "relative",
            confidence: referenceElement.confidence
        )
    }

    // MARK: - Strategy: Hybrid

    /// Try multiple strategies in sequence, returning first successful match
    private func tryHybrid(_ targets: [ElementTarget], pid: pid_t) async throws -> LocatedElement {
        var lastError: Error?

        for target in targets {
            do {
                return try await locate(target, in: pid)
            } catch {
                lastError = error
                continue
            }
        }

        if let error = lastError {
            throw error
        }

        throw NSError(domain: "ElementLocator", code: -1, userInfo: [NSLocalizedDescriptionKey: "All hybrid strategies failed"])
    }
}
