import Vision
import AppKit
import CoreImage
import CoreGraphics
import ScreenCaptureKit

// MARK: - Enums and Structs

enum TextMatchMode {
    case exact
    case contains
    case regex
}

struct TextMatch {
    let text: String
    let boundingBox: CGRect
    let confidence: Float
}

struct ImageComparison {
    let similarityScore: Double
    let diffRegions: [CGRect]
    let passed: Bool
}

// MARK: - Vision Engine

/// On-device OCR and visual element detection using Apple Vision framework
class VisionEngine {

    private let ciContext = CIContext()

    // MARK: - OCR and Text Detection

    /// Find text on screen matching a query, returns bounding rects in screen coordinates
    func findText(_ query: String, in image: NSImage, matchMode: TextMatchMode = .contains) throws -> [TextMatch] {
        let allMatches = try extractAllText(from: image)

        return allMatches.filter { match in
            switch matchMode {
            case .exact:
                return match.text == query
            case .contains:
                return match.text.localizedCaseInsensitiveContains(query)
            case .regex:
                do {
                    let regex = try NSRegularExpression(pattern: query, options: .caseInsensitive)
                    let range = NSRange(match.text.startIndex..., in: match.text)
                    return regex.firstMatch(in: match.text, options: [], range: range) != nil
                } catch {
                    return false
                }
            }
        }
    }

    /// Extract ALL text from an image with positions
    func extractAllText(from image: NSImage) throws -> [TextMatch] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw NSError(domain: "VisionEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not convert NSImage to CGImage"])
        }

        let recognizeTextRequest = VNRecognizeTextRequest()
        recognizeTextRequest.recognitionLevel = .accurate
        recognizeTextRequest.usesLanguageCorrection = true

        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        try requestHandler.perform([recognizeTextRequest])

        guard let observations = recognizeTextRequest.results as? [VNRecognizedTextObservation] else {
            return []
        }

        let imageHeight = CGFloat(cgImage.height)
        let imageWidth = CGFloat(cgImage.width)

        var matches: [TextMatch] = []

        for observation in observations {
            let topCandidate = observation.topCandidates(1).first

            guard let candidate = topCandidate else { continue }

            let text = candidate.string
            let confidence = Float(candidate.confidence)

            // Convert bounding box from Vision coordinates to screen coordinates
            // Vision uses bottom-left origin, but screen uses top-left
            let bbox = observation.boundingBox
            let screenRect = CGRect(
                x: bbox.minX * imageWidth,
                y: (1 - bbox.maxY) * imageHeight,
                width: bbox.width * imageWidth,
                height: bbox.height * imageHeight
            )

            matches.append(TextMatch(text: text, boundingBox: screenRect, confidence: confidence))
        }

        return matches
    }

    // MARK: - Template Matching

    /// Template matching - find a template image within a larger image
    func findTemplate(_ template: NSImage, in image: NSImage, threshold: Double = 0.85) throws -> [CGRect] {
        guard let templateCG = template.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let imageCG = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw NSError(domain: "VisionEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not convert images to CGImage"])
        }

        // Convert to CIImage for processing
        let templateCI = CIImage(cgImage: templateCG)
        let imageCI = CIImage(cgImage: imageCG)

        let templateHeight = templateCI.extent.height
        let templateWidth = templateCI.extent.width
        let imageHeight = imageCI.extent.height
        let imageWidth = imageCI.extent.width

        var matches: [CGRect] = []

        // Template matching using correlation
        let templatePixels = getPixels(from: templateCG)
        let imagePixels = getPixels(from: imageCG)

        let templateSize = Int(templateWidth) * Int(templateHeight)
        let imageRowSize = Int(imageWidth)

        // Slide template across image
        for y in 0...(Int(imageHeight) - Int(templateHeight)) {
            for x in 0...(Int(imageWidth) - Int(templateWidth)) {
                let correlation = correlationAtPoint(CGPoint(x: x, y: y),
                                                    templatePixels: templatePixels,
                                                    imagePixels: imagePixels,
                                                    templateWidth: Int(templateWidth),
                                                    templateHeight: Int(templateHeight),
                                                    imageWidth: imageRowSize)

                if correlation >= threshold {
                    let matchRect = CGRect(x: x, y: y, width: Int(templateWidth), height: Int(templateHeight))
                    matches.append(matchRect)
                }
            }
        }

        return removeOverlappingMatches(matches)
    }

    private func getPixels(from cgImage: CGImage) -> [UInt32] {
        let width = cgImage.width
        let height = cgImage.height
        var pixelData = [UInt8](repeating: 0, count: width * height * 4)

        guard let dataProvider = cgImage.dataProvider else { return [] }
        let data = dataProvider.data
        let pixelBuffer = CFDataGetBytePtr(data)

        memcpy(&pixelData, pixelBuffer, pixelData.count)

        var result: [UInt32] = []
        for i in stride(from: 0, to: pixelData.count, by: 4) {
            let gray = UInt32(pixelData[i]) + UInt32(pixelData[i + 1]) + UInt32(pixelData[i + 2])
            result.append(gray / 3)
        }

        return result
    }

    private func correlationAtPoint(_ point: CGPoint, templatePixels: [UInt32], imagePixels: [UInt32],
                                  templateWidth: Int, templateHeight: Int, imageWidth: Int) -> Double {
        let startX = Int(point.x)
        let startY = Int(point.y)

        var sum: Double = 0
        var templateSum: Double = 0
        var imageSum: Double = 0

        for ty in 0..<templateHeight {
            for tx in 0..<templateWidth {
                let templateIdx = ty * templateWidth + tx
                let imageIdx = (startY + ty) * imageWidth + (startX + tx)

                guard templateIdx < templatePixels.count && imageIdx < imagePixels.count else { continue }

                let tVal = Double(templatePixels[templateIdx])
                let iVal = Double(imagePixels[imageIdx])

                sum += tVal * iVal
                templateSum += tVal * tVal
                imageSum += iVal * iVal
            }
        }

        let denominator = sqrt(templateSum * imageSum)
        guard denominator > 0 else { return 0 }

        return sum / denominator
    }

    private func removeOverlappingMatches(_ matches: [CGRect]) -> [CGRect] {
        var filtered: [CGRect] = []

        for match in matches.sorted(by: { $0.origin.y < $1.origin.y }) {
            let overlaps = filtered.contains { existing in
                match.intersects(existing)
            }

            if !overlaps {
                filtered.append(match)
            }
        }

        return filtered
    }

    // MARK: - Image Comparison

    /// Compare two images and return similarity score
    func compareImages(_ image1: NSImage, _ image2: NSImage, excludeRegions: [CGRect] = []) throws -> ImageComparison {
        guard let cg1 = image1.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let cg2 = image2.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw NSError(domain: "VisionEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not convert images"])
        }

        // Resize to same dimensions if needed
        let size1 = CGSize(width: cg1.width, height: cg1.height)
        let size2 = CGSize(width: cg2.width, height: cg2.height)

        let targetSize = size1.width > size2.width ? size2 : size1

        let pixels1 = getPixels(from: cg1)
        let pixels2 = getPixels(from: cg2)

        guard pixels1.count == pixels2.count else {
            throw NSError(domain: "VisionEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Image dimensions do not match"])
        }

        var similaritySum: Double = 0
        var pixelCount = 0
        var diffRegions: [CGRect] = []

        for i in 0..<pixels1.count {
            let diff = abs(Int(pixels1[i]) - Int(pixels2[i]))

            if diff > 30 { // Threshold for difference
                let x = i % Int(targetSize.width)
                let y = i / Int(targetSize.width)
                diffRegions.append(CGRect(x: x, y: y, width: 1, height: 1))
            }

            similaritySum += 1.0 - (Double(diff) / 255.0)
            pixelCount += 1
        }

        let similarityScore = pixelCount > 0 ? similaritySum / Double(pixelCount) : 0

        return ImageComparison(
            similarityScore: similarityScore,
            diffRegions: mergeDiffRegions(diffRegions),
            passed: similarityScore > 0.95
        )
    }

    private func mergeDiffRegions(_ regions: [CGRect]) -> [CGRect] {
        guard !regions.isEmpty else { return [] }

        var merged: [CGRect] = []
        var current = regions[0]

        for region in regions.dropFirst() {
            if current.intersects(region.insetBy(dx: -5, dy: -5)) {
                current = current.union(region)
            } else {
                merged.append(current)
                current = region
            }
        }

        merged.append(current)
        return merged
    }

    /// Generate a visual diff image highlighting differences
    func generateDiffImage(_ baseline: NSImage, _ current: NSImage) throws -> NSImage {
        guard let baseCG = baseline.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let currCG = current.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw NSError(domain: "VisionEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not convert images"])
        }

        let comparison = try compareImages(baseline, current)

        // Create a copy of current image
        let width = currCG.width
        let height = currCG.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel

        var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        guard let dataProvider = currCG.dataProvider else {
            throw NSError(domain: "VisionEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data provider"])
        }

        let data = dataProvider.data
        let pixelBuffer = CFDataGetBytePtr(data)
        memcpy(&pixelData, pixelBuffer, pixelData.count)

        // Highlight diff regions with red overlay
        for rect in comparison.diffRegions {
            let x = Int(rect.minX)
            let y = Int(rect.minY)

            guard x >= 0 && x < width && y >= 0 && y < height else { continue }

            let pixelIndex = (y * width + x) * bytesPerPixel
            pixelData[pixelIndex] = 255 // Red
            pixelData[pixelIndex + 1] = 0
            pixelData[pixelIndex + 2] = 0
            pixelData[pixelIndex + 3] = 255
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let dataProvider = CGDataProvider(data: NSData(bytes: pixelData, length: pixelData.count)) else {
            throw NSError(domain: "VisionEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not create data provider"])
        }

        guard let resultCG = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                     bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                     provider: dataProvider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            throw NSError(domain: "VisionEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not create result image"])
        }

        return NSImage(cgImage: resultCG, size: NSZeroSize)
    }

    // MARK: - Screen Capture

    /// Capture screenshot of entire screen
    func captureScreen() throws -> NSImage {
        let screens = NSScreen.screens
        guard let mainScreen = screens.first else {
            throw NSError(domain: "VisionEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "No screens found"])
        }

        let frame = mainScreen.frame
        return try captureRegion(frame)
    }

    /// Capture screenshot of a specific window
    func captureWindow(pid: pid_t) throws -> NSImage {
        let options: CGWindowListOption = [.excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            throw NSError(domain: "VisionEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not get window list"])
        }

        for windowInfo in windowList {
            if let windowPID = windowInfo[kCGWindowOwnerPID as String] as? pid_t, windowPID == pid {
                if let windowNumber = windowInfo[kCGWindowNumber as String] as? Int32 {
                    guard let cgImage = CGWindowListCreateImage(.null, .optionIncludingWindow, UInt32(windowNumber), [.boundsIgnoreFraming, .nominalResolution]) else {
                        throw NSError(domain: "VisionEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not capture window"])
                    }

                    return NSImage(cgImage: cgImage, size: NSZeroSize)
                }
            }
        }

        throw NSError(domain: "VisionEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Window not found for PID"])
    }

    /// Capture a specific region of the screen
    func captureRegion(_ rect: CGRect) throws -> NSImage {
        guard let cgImage = CGWindowListCreateImage(rect, .optionOnScreenBelowWindow, kCGNullWindowID, [.nominalResolution]) else {
            throw NSError(domain: "VisionEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not capture region"])
        }

        return NSImage(cgImage: cgImage, size: NSZeroSize)
    }
}
