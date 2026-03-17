import Foundation

enum VariableResolverError: Error, CustomStringConvertible {
    case undefinedVariable(String)
    case invalidSyntax(String)
    case circularReference(String)

    var description: String {
        switch self {
        case .undefinedVariable(let name):
            return "Undefined variable: \(name)"
        case .invalidSyntax(let details):
            return "Invalid syntax: \(details)"
        case .circularReference(let name):
            return "Circular reference detected for: \(name)"
        }
    }
}

class VariableResolver {
    private static let variablePattern = try! NSRegularExpression(
        pattern: "\\$\\{([^}]+)\\}",
        options: []
    )

    static func resolve(_ input: String, with variables: [String: String]) throws -> String {
        var result = input
        var iterations = 0
        let maxIterations = 100

        while iterations < maxIterations {
            let before = result
            result = try resolveOnce(result, with: variables)

            // If no changes, we're done
            if result == before {
                break
            }

            iterations += 1
        }

        if iterations >= maxIterations {
            throw VariableResolverError.circularReference(input)
        }

        return result
    }

    private static func resolveOnce(_ input: String, with variables: [String: String]) throws -> String {
        let nsInput = input as NSString
        let range = NSRange(location: 0, length: nsInput.length)

        var result = input
        var offset = 0

        let matches = variablePattern.matches(in: input, options: [], range: range)

        for match in matches {
            let variableRange = match.range(at: 1)
            let variableNameNS = nsInput.substring(with: variableRange)
            let fullMatchRange = match.range

            let adjustedRange = NSRange(
                location: fullMatchRange.location + offset,
                length: fullMatchRange.length
            )

            do {
                let replacement = try resolveVariable(variableNameNS, with: variables)
                let resultNS = result as NSString
                result = resultNS.replacingCharacters(in: adjustedRange, with: replacement)
                offset += replacement.count - fullMatchRange.length
            } catch {
                throw error
            }
        }

        return result
    }

    private static func resolveVariable(_ name: String, with variables: [String: String]) throws -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)

        // Handle built-in variables
        if trimmedName == "timestamp" {
            return String(Int(Date().timeIntervalSince1970 * 1000))
        }

        if trimmedName == "date" {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: Date())
        }

        if trimmedName == "random" {
            return String(Int.random(in: 0..<100000))
        }

        if trimmedName == "home_dir" {
            return NSHomeDirectory()
        }

        if trimmedName == "desktop" {
            let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            return desktopURL?.path ?? ""
        }

        // Handle environment variables: env.NAME
        if trimmedName.hasPrefix("env.") {
            let envVarName = String(trimmedName.dropFirst(4))
            if let envValue = ProcessInfo.processInfo.environment[envVarName] {
                return envValue
            } else {
                throw VariableResolverError.undefinedVariable("environment variable: \(envVarName)")
            }
        }

        // Handle custom variables from the workflow
        if let value = variables[trimmedName] {
            return value
        }

        // Variable not found
        throw VariableResolverError.undefinedVariable(trimmedName)
    }

    static func extractVariableNames(from input: String) -> [String] {
        let nsInput = input as NSString
        let range = NSRange(location: 0, length: nsInput.length)

        let matches = variablePattern.matches(in: input, options: [], range: range)
        var names: [String] = []

        for match in matches {
            let variableRange = match.range(at: 1)
            let variableName = nsInput.substring(with: variableRange).trimmingCharacters(in: .whitespaces)
            if !names.contains(variableName) {
                names.append(variableName)
            }
        }

        return names
    }

    static func validate(_ input: String, with variables: [String: String]) -> [VariableResolverError] {
        let variableNames = extractVariableNames(from: input)
        var errors: [VariableResolverError] = []

        for name in variableNames {
            // Check if it's a built-in variable
            if ["timestamp", "date", "random", "home_dir", "desktop"].contains(name) {
                continue
            }

            // Check if it's an environment variable reference
            if name.hasPrefix("env.") {
                let envVarName = String(name.dropFirst(4))
                if ProcessInfo.processInfo.environment[envVarName] == nil {
                    errors.append(.undefinedVariable("environment variable: \(envVarName)"))
                }
                continue
            }

            // Check if it's a custom variable
            if variables[name] == nil {
                errors.append(.undefinedVariable(name))
            }
        }

        return errors
    }
}
