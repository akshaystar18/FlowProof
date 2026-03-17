import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - UTType Extensions

extension UTType {
    static var yaml: UTType {
        UTType(filenameExtension: "yaml") ?? .plainText
    }

    static var yml: UTType {
        UTType(filenameExtension: "yml") ?? .plainText
    }
}

// MARK: - Date Extensions

extension Date {
    /// ISO 8601 formatted string
    var iso8601: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: self)
    }

    /// Short display format: "Mar 16, 2:30 PM"
    var shortDisplay: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }

    /// Relative display format: "2 hours ago"
    var relativeDisplay: String {
        let calendar = Calendar.current
        let now = Date()

        let components = calendar.dateComponents([.second, .minute, .hour, .day], from: self, to: now)

        if let day = components.day, day > 0 {
            return day == 1 ? "1 day ago" : "\(day) days ago"
        }

        if let hour = components.hour, hour > 0 {
            return hour == 1 ? "1 hour ago" : "\(hour) hours ago"
        }

        if let minute = components.minute, minute > 0 {
            return minute == 1 ? "1 minute ago" : "\(minute) minutes ago"
        }

        if let second = components.second, second > 0 {
            return second == 1 ? "1 second ago" : "\(second) seconds ago"
        }

        return "Just now"
    }
}

// MARK: - Duration Extensions

extension Int64 {
    /// Format duration in milliseconds to human-readable string
    /// Examples: "2m 30s", "450ms", "1h 5m"
    var durationDisplay: String {
        let totalSeconds = Double(self) / 1000.0

        if totalSeconds < 1 {
            return "\(self)ms"
        }

        let hours = Int(totalSeconds) / 3600
        let minutes = (Int(totalSeconds) % 3600) / 60
        let seconds = Int(totalSeconds) % 60
        let milliseconds = self % 1000

        if hours > 0 {
            return String(format: "%dh %dm %ds", hours, minutes, seconds)
        }

        if minutes > 0 {
            if seconds > 0 {
                return String(format: "%dm %ds", minutes, seconds)
            } else {
                return String(format: "%dm", minutes)
            }
        }

        if seconds > 0 {
            if milliseconds > 0 {
                return String(format: "%d.%03ds", seconds, milliseconds)
            } else {
                return String(format: "%ds", seconds)
            }
        }

        return "\(self)ms"
    }
}

extension TimeInterval {
    /// Format TimeInterval (in seconds) to human-readable string
    var durationDisplay: String {
        let milliseconds = Int64(self * 1000)
        return milliseconds.durationDisplay
    }
}

// MARK: - String Extensions

extension String {
    /// Expand tilde in file paths to home directory
    func expandingTildeInPath() -> String {
        if hasPrefix("~") {
            let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
            return replacingOccurrences(of: "~", with: homeDirectory, options: [], range: startIndex..<index(startIndex, offsetBy: 1))
        }
        return self
    }

    /// Escape special characters for YAML string representation
    var yamlEscaped: String {
        let needsQuotes = contains { char in
            char.isWhitespace || char == ":" || char == "#" || char == "[" || char == "]"
                || char == "{" || char == "}" || char == "," || char == "\"" || char == "'"
        }

        if needsQuotes {
            let escaped = replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }

        return self
    }

    /// Check if string matches a regular expression pattern
    func matches(regex pattern: String) -> Bool {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let range = NSRange(location: 0, length: utf16.count)
            return regex.firstMatch(in: self, options: [], range: range) != nil
        } catch {
            return false
        }
    }

    /// Extract all matches for a regular expression pattern
    func extractMatches(regex pattern: String) -> [String] {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let range = NSRange(location: 0, length: utf16.count)
            let matches = regex.matches(in: self, options: [], range: range)

            return matches.compactMap { match in
                if let range = Range(match.range, in: self) {
                    return String(self[range])
                }
                return nil
            }
        } catch {
            return []
        }
    }
}

// MARK: - NSImage Extensions

extension NSImage {
    /// Load an image from file path, returns nil if not found or invalid
    static func fromPath(_ path: String) -> NSImage? {
        let expandedPath = path.expandingTildeInPath()
        return NSImage(contentsOfFile: expandedPath)
    }

    /// Resize image to fit within max dimensions while maintaining aspect ratio
    func resized(maxWidth: CGFloat = CGFloat.greatestFiniteMagnitude, maxHeight: CGFloat = CGFloat.greatestFiniteMagnitude) -> NSImage {
        let currentSize = self.size

        let widthRatio = maxWidth / currentSize.width
        let heightRatio = maxHeight / currentSize.height

        let scale = min(1.0, widthRatio, heightRatio)

        if scale >= 1.0 {
            return self
        }

        let newSize = CGSize(width: currentSize.width * scale, height: currentSize.height * scale)
        let newImage = NSImage(size: newSize)

        newImage.lockFocus()
        self.draw(
            in: NSRect(origin: .zero, size: newSize),
            from: NSRect(origin: .zero, size: currentSize),
            operation: .copy,
            fraction: 1.0
        )
        newImage.unlockFocus()

        return newImage
    }

    /// Scale image by a given factor
    func scaled(by factor: CGFloat) -> NSImage {
        let newSize = CGSize(width: size.width * factor, height: size.height * factor)
        return resized(maxWidth: newSize.width, maxHeight: newSize.height)
    }

    /// Save image as PNG to specified path
    func savePNG(to path: String) throws {
        let expandedPath = path.expandingTildeInPath()

        guard let tiffRepresentation = self.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffRepresentation),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "NSImage", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to convert image to PNG"
            ])
        }

        try pngData.write(to: URL(fileURLWithPath: expandedPath))
    }

    /// Crop image to a specific rectangle
    func cropped(to rect: NSRect) -> NSImage? {
        let newImage = NSImage(size: rect.size)

        newImage.lockFocus()
        self.draw(
            in: NSRect(origin: .zero, size: rect.size),
            from: rect,
            operation: .copy,
            fraction: 1.0
        )
        newImage.unlockFocus()

        return newImage
    }
}

// MARK: - Color Extensions

extension Color {
    /// Get color based on run status
    static func forRunStatus(_ status: RunStatus) -> Color {
        switch status {
        case .passed:
            return .green
        case .failed:
            return .red
        case .running:
            return .yellow
        case .pending:
            return .gray
        case .aborted:
            return .orange
        case .skipped:
            return .blue
        }
    }
}

// MARK: - FileManager Extensions

extension FileManager {
    /// Find first file matching a glob pattern in a directory
    func firstFile(matching glob: String, in directory: String) -> String? {
        let pattern = glob.replacingOccurrences(of: "*", with: "[^/]*")
        let expandedDir = directory.expandingTildeInPath()

        guard let contents = try? contentsOfDirectory(atPath: expandedDir) else {
            return nil
        }

        for file in contents {
            let fullPath = (expandedDir as NSString).appendingPathComponent(file)
            if file.matches(regex: "^\(pattern)$") {
                return fullPath
            }
        }

        return nil
    }

    /// Find all files matching a glob pattern in a directory
    func filesMatching(glob: String, in directory: String) -> [String] {
        let pattern = glob.replacingOccurrences(of: "*", with: "[^/]*")
        let expandedDir = directory.expandingTildeInPath()

        guard let contents = try? contentsOfDirectory(atPath: expandedDir) else {
            return []
        }

        return contents
            .filter { $0.matches(regex: "^\(pattern)$") }
            .map { (expandedDir as NSString).appendingPathComponent($0) }
            .sorted()
    }

    /// Check if a path is a directory
    func isDirectory(path: String) -> Bool {
        var isDir: ObjCBool = false
        let exists = fileExists(atPath: path, isDirectory: &isDir)
        return exists && isDir.boolValue
    }

    /// Get file size in bytes
    func fileSize(atPath path: String) -> Int64 {
        do {
            let attributes = try attributesOfItem(atPath: path)
            return attributes[.size] as? Int64 ?? 0
        } catch {
            return 0
        }
    }

    /// Create directory if it doesn't exist
    @discardableResult
    func createDirectoryIfNeeded(at path: String) -> Bool {
        let expandedPath = path.expandingTildeInPath()

        guard !fileExists(atPath: expandedPath) else {
            return true
        }

        do {
            try createDirectory(atPath: expandedPath, withIntermediateDirectories: true, attributes: nil)
            return true
        } catch {
            return false
        }
    }

    /// Recursively find all files in a directory matching a predicate
    func findFiles(in directory: String, where predicate: (String) -> Bool) -> [String] {
        let expandedDir = directory.expandingTildeInPath()
        var results: [String] = []

        if let enumerator = enumerator(atPath: expandedDir) {
            for case let file as String in enumerator {
                let fullPath = (expandedDir as NSString).appendingPathComponent(file)
                if predicate(fullPath) {
                    results.append(fullPath)
                }
            }
        }

        return results
    }

    /// Get all files modified after a given date
    func filesModifiedAfter(_ date: Date, in directory: String) -> [String] {
        return findFiles(in: directory) { path in
            guard let attributes = try? attributesOfItem(atPath: path),
                  let modifiedDate = attributes[.modificationDate] as? Date else {
                return false
            }
            return modifiedDate > date
        }
    }
}

// MARK: - UserDefaults Extensions

extension UserDefaults {
    /// Type-safe access to UserDefaults with optional return
    func value<T>(forKey key: String, type: T.Type) -> T? {
        return object(forKey: key) as? T
    }

    /// Store an Codable object
    func setCodable<T: Encodable>(_ value: T, forKey key: String) throws {
        let encoded = try JSONEncoder().encode(value)
        set(encoded, forKey: key)
    }

    /// Retrieve a Codable object
    func codable<T: Decodable>(forKey key: String, type: T.Type) throws -> T? {
        guard let data = data(forKey: key) else { return nil }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Array Extensions

extension Array {
    /// Safely access an element by index
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }

    /// Split array into chunks of a given size
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Dictionary Extensions

extension Dictionary {
    /// Merge another dictionary into this one
    mutating func merge(_ other: [Key: Value]) {
        for (key, value) in other {
            self[key] = value
        }
    }

    /// Create a new dictionary with merged contents
    func merging(_ other: [Key: Value]) -> [Key: Value] {
        var result = self
        result.merge(other)
        return result
    }
}
