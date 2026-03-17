import Foundation

/// Generates YAML workflow definitions from inferred actions
class WorkflowGenerator {

    /// Generate YAML string from inferred actions
    func generateYAML(
        name: String,
        targetAppName: String,
        targetBundleId: String,
        actions: [InferredAction]
    ) -> String {
        var yaml = ""

        yaml += "version: '1.0'\n"
        yaml += "name: \(yamlEscape(name))\n"
        yaml += "description: Auto-generated workflow from recording\n"
        yaml += "target_app:\n"
        yaml += "  name: \(yamlEscape(targetAppName))\n"
        yaml += "  bundle_id: \(yamlEscape(targetBundleId))\n"
        yaml += "steps:\n"

        for (_, action) in actions.enumerated() {
            yaml += "  - name: \(yamlEscape(generateStepName(action)))\n"
            yaml += "    action: \(actionTypeToString(action.action))\n"

            let actionYaml = actionToYAML(action, indent: "    ")
            yaml += actionYaml
        }

        return yaml
    }

    /// Convert InferredActionType to the canonical ActionType raw string
    private func actionTypeToString(_ action: InferredActionType) -> String {
        switch action {
        case .click: return "click"
        case .type: return "type"
        case .shortcut: return "key"
        case .drag: return "drag"
        case .scroll: return "scroll"
        case .wait: return "wait"
        }
    }

    /// Convert a single inferred action to YAML properties
    private func actionToYAML(_ action: InferredAction, indent: String) -> String {
        var yaml = ""

        switch action.action {
        case .click(let button):
            if button != 0 {
                yaml += "\(indent)click_count: 1\n"
            }
            if let target = action.target {
                yaml += targetToYAML(target, indent: indent)
            }

        case .type(let text):
            yaml += "\(indent)text: \(yamlEscape(text))\n"
            if let target = action.target {
                yaml += targetToYAML(target, indent: indent)
            }

        case .shortcut(let combo):
            yaml += "\(indent)combo: \(yamlEscape(combo))\n"

        case .drag:
            if let from = action.from {
                yaml += "\(indent)from:\n"
                let parts = from.value.split(separator: ",")
                yaml += "\(indent)  coordinates:\n"
                yaml += "\(indent)    x: \(parts.first ?? "0")\n"
                yaml += "\(indent)    y: \(parts.last ?? "0")\n"
            }
            if let to = action.to {
                yaml += "\(indent)to:\n"
                let parts = to.value.split(separator: ",")
                yaml += "\(indent)  coordinates:\n"
                yaml += "\(indent)    x: \(parts.first ?? "0")\n"
                yaml += "\(indent)    y: \(parts.last ?? "0")\n"
            }

        case .scroll(let direction, let amount):
            yaml += "\(indent)direction: \(direction.rawValue)\n"
            yaml += "\(indent)amount: \(amount)\n"

        case .wait(let seconds):
            yaml += "\(indent)duration: \(seconds)\n"
        }

        if let amount = action.amount, amount > 1 {
            if case .click = action.action {
                yaml += "\(indent)repeat: \(amount)\n"
            }
        }

        return yaml
    }

    /// Convert InferredElementTarget to YAML text
    private func targetToYAML(_ target: InferredElementTarget, indent: String) -> String {
        switch target.strategy {
        case .identifier:
            return "\(indent)target:\n\(indent)  accessibility:\n\(indent)    identifier: \(yamlEscape(target.value))\n"
        case .label:
            return "\(indent)target:\n\(indent)  accessibility:\n\(indent)    label: \(yamlEscape(target.value))\n"
        case .role:
            return "\(indent)target:\n\(indent)  accessibility:\n\(indent)    role: \(yamlEscape(target.value))\n"
        case .coordinates:
            let parts = target.value.split(separator: ",")
            return "\(indent)target:\n\(indent)  coordinates:\n\(indent)    x: \(parts.first ?? "0")\n\(indent)    y: \(parts.last ?? "0")\n"
        case .xpath:
            return "\(indent)target:\n\(indent)  text_ocr: \(yamlEscape(target.value))\n"
        }
    }

    /// Generate a human-readable step name from an action
    private func generateStepName(_ action: InferredAction) -> String {
        switch action.action {
        case .click(let button):
            let buttonName = button == 0 ? "Left" : "Right"
            if let target = action.target, target.strategy == .label {
                return "Click \(target.value)"
            }
            return "Click \(buttonName) Button"

        case .type(let text):
            let preview = String(text.prefix(20))
            return "Type '\(preview)\(text.count > 20 ? "..." : "")'"

        case .shortcut(let combo):
            return "Press \(combo)"

        case .drag:
            if let distance = action.amount {
                return "Drag \(distance)px"
            }
            return "Drag"

        case .scroll(let direction, let amount):
            return "Scroll \(direction.rawValue.capitalized) \(amount)"

        case .wait(let seconds):
            return "Wait \(seconds)s"
        }
    }

    /// Escape YAML special characters
    private func yamlEscape(_ string: String) -> String {
        let needsQuoting = string.contains(":") ||
                          string.contains("#") ||
                          string.contains("[") ||
                          string.contains("]") ||
                          string.contains("{") ||
                          string.contains("}") ||
                          string.contains(",") ||
                          string.contains("&") ||
                          string.contains("*") ||
                          string.contains("!") ||
                          string.contains("|") ||
                          string.contains(">") ||
                          string.contains("'") ||
                          string.contains("\"") ||
                          string.contains("\n") ||
                          string.isEmpty

        if needsQuoting {
            let escaped = string
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
                .replacingOccurrences(of: "\t", with: "\\t")
            return "\"\(escaped)\""
        }

        return string
    }
}
