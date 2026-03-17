import Foundation
import Yams

enum ParserError: Error, CustomStringConvertible {
    case invalidFile
    case invalidYAML(String)
    case missingRequiredField(String)
    case invalidActionType(String)
    case variableResolutionFailed(String)
    case fileNotFound(String)

    var description: String {
        switch self {
        case .invalidFile:
            return "Invalid file format"
        case .invalidYAML(let details):
            return "Invalid YAML: \(details)"
        case .missingRequiredField(let field):
            return "Missing required field: \(field)"
        case .invalidActionType(let type):
            return "Invalid action type: \(type)"
        case .variableResolutionFailed(let details):
            return "Variable resolution failed: \(details)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        }
    }
}

class WorkflowParser {
    static func parse(from url: URL) throws -> Workflow {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ParserError.fileNotFound(url.path)
        }

        let data = try Data(contentsOf: url)
        let content = String(data: data, encoding: .utf8) ?? ""

        if url.pathExtension.lowercased() == "json" {
            return try parseJSON(content)
        } else {
            return try parseYAML(content)
        }
    }

    static func parseYAML(_ string: String) throws -> Workflow {
        do {
            let decoder = YAMLDecoder()
            var workflow = try decoder.decode(Workflow.self, from: string)

            // Apply variable resolution
            workflow = try resolveWorkflowVariables(workflow)

            // Validate required fields
            try validateWorkflow(workflow)

            return workflow
        } catch {
            if let decodingError = error as? DecodingError {
                throw ParserError.invalidYAML(decodingError.localizedDescription)
            }
            throw error
        }
    }

    private static func parseJSON(_ string: String) throws -> Workflow {
        guard let data = string.data(using: .utf8) else {
            throw ParserError.invalidFile
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var workflow = try decoder.decode(Workflow.self, from: data)

            // Apply variable resolution
            workflow = try resolveWorkflowVariables(workflow)

            // Validate required fields
            try validateWorkflow(workflow)

            return workflow
        } catch {
            if let decodingError = error as? DecodingError {
                throw ParserError.invalidYAML(decodingError.localizedDescription)
            }
            throw error
        }
    }

    private static func validateWorkflow(_ workflow: Workflow) throws {
        if workflow.name.trimmingCharacters(in: .whitespaces).isEmpty {
            throw ParserError.missingRequiredField("name")
        }

        if workflow.version.trimmingCharacters(in: .whitespaces).isEmpty {
            throw ParserError.missingRequiredField("version")
        }

        if workflow.targetApp.name.trimmingCharacters(in: .whitespaces).isEmpty {
            throw ParserError.missingRequiredField("target_app.name")
        }

        if workflow.steps.isEmpty {
            throw ParserError.missingRequiredField("steps (at least one step required)")
        }

        for step in workflow.steps {
            try validateStep(step)
        }

        if let setupSteps = workflow.setup {
            for step in setupSteps {
                try validateStep(step)
            }
        }

        if let teardownSteps = workflow.teardown {
            for step in teardownSteps {
                try validateStep(step)
            }
        }
    }

    private static func validateStep(_ step: WorkflowStep) throws {
        // Check if action is known
        let _ = step.action

        // Validate action-specific requirements
        switch step.action {
        case .click, .type, .scroll, .drag:
            // These typically require a target
            break
        case .key:
            if step.combo == nil && step.modifiers == nil {
                throw ParserError.missingRequiredField("step requires 'combo' or 'modifiers'")
            }
        case .wait:
            if step.condition == nil && step.duration == nil {
                throw ParserError.missingRequiredField("wait step requires 'condition' or 'duration'")
            }
        case .launch:
            if step.bundleId == nil {
                throw ParserError.missingRequiredField("launch step requires 'bundle_id'")
            }
        case .assert:
            if step.assertType == nil {
                throw ParserError.missingRequiredField("assert step requires 'assert_type'")
            }
        case .conditional:
            if step.ifCondition == nil || step.thenSteps == nil {
                throw ParserError.missingRequiredField("conditional step requires 'if_condition' and 'then_steps'")
            }
        case .loop:
            if step.count == nil || step.loopSteps == nil {
                throw ParserError.missingRequiredField("loop step requires 'count' and 'loop_steps'")
            }
        case .subWorkflow:
            if step.subWorkflowPath == nil {
                throw ParserError.missingRequiredField("sub_workflow step requires 'sub_workflow_path'")
            }
        case .setVariable:
            if step.variableName == nil {
                throw ParserError.missingRequiredField("set_variable step requires 'variable_name'")
            }
        case .menu:
            if step.menuPath == nil {
                throw ParserError.missingRequiredField("menu step requires 'menu_path'")
            }
        case .clipboard:
            if step.clipboardAction == nil {
                throw ParserError.missingRequiredField("clipboard step requires 'clipboard_action'")
            }
        case .upload, .download:
            if step.filePath == nil {
                throw ParserError.missingRequiredField("file operation requires 'file_path'")
            }
        default:
            break
        }

        // Recursively validate nested steps
        if let thenSteps = step.thenSteps {
            for nestedStep in thenSteps {
                try validateStep(nestedStep)
            }
        }

        if let elseSteps = step.elseSteps {
            for nestedStep in elseSteps {
                try validateStep(nestedStep)
            }
        }

        if let loopSteps = step.loopSteps {
            for nestedStep in loopSteps {
                try validateStep(nestedStep)
            }
        }
    }

    private static func resolveWorkflowVariables(_ workflow: Workflow) throws -> Workflow {
        var result = workflow

        // Resolve variables in workflow-level fields
        result.name = try VariableResolver.resolve(result.name, with: workflow.variables ?? [:])
        result.version = try VariableResolver.resolve(result.version, with: workflow.variables ?? [:])

        // Resolve variables in all steps
        result.steps = try result.steps.map { step in
            try resolveStepVariables(step, with: workflow.variables ?? [:])
        }

        if var setupSteps = result.setup {
            setupSteps = try setupSteps.map { step in
                try resolveStepVariables(step, with: workflow.variables ?? [:])
            }
            result.setup = setupSteps
        }

        if var teardownSteps = result.teardown {
            teardownSteps = try teardownSteps.map { step in
                try resolveStepVariables(step, with: workflow.variables ?? [:])
            }
            result.teardown = teardownSteps
        }

        return result
    }

    private static func resolveStepVariables(_ step: WorkflowStep, with variables: [String: String]) throws -> WorkflowStep {
        var result = step

        // Resolve text fields
        if let name = result.name {
            result.name = try VariableResolver.resolve(name, with: variables)
        }
        if let text = result.text {
            result.text = try VariableResolver.resolve(text, with: variables)
        }
        if let filePath = result.filePath {
            result.filePath = try VariableResolver.resolve(filePath, with: variables)
        }
        if let variableValue = result.variableValue {
            result.variableValue = try VariableResolver.resolve(variableValue, with: variables)
        }
        if let clipboardValue = result.clipboardValue {
            result.clipboardValue = try VariableResolver.resolve(clipboardValue, with: variables)
        }
        if let menuPath = result.menuPath {
            result.menuPath = try VariableResolver.resolve(menuPath, with: variables)
        }
        if let subWorkflowPath = result.subWorkflowPath {
            result.subWorkflowPath = try VariableResolver.resolve(subWorkflowPath, with: variables)
        }
        if let expected = result.expected {
            result.expected = try VariableResolver.resolve(expected, with: variables)
        }

        // Recursively resolve nested steps
        if var thenSteps = result.thenSteps {
            thenSteps = try thenSteps.map { step in
                try resolveStepVariables(step, with: variables)
            }
            result.thenSteps = thenSteps
        }

        if var elseSteps = result.elseSteps {
            elseSteps = try elseSteps.map { step in
                try resolveStepVariables(step, with: variables)
            }
            result.elseSteps = elseSteps
        }

        if var loopSteps = result.loopSteps {
            loopSteps = try loopSteps.map { step in
                try resolveStepVariables(step, with: variables)
            }
            result.loopSteps = loopSteps
        }

        return result
    }
}
