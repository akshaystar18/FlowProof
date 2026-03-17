import SwiftUI
import Combine
import AppKit

/// Coordinates the recording workflow
@MainActor
class RecorderCoordinator: ObservableObject {
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var capturedEventCount = 0
    @Published var inferredActions: [InferredAction] = []
    @Published var generatedYAML: String = ""
    @Published var targetApp: RunningApp?
    @Published var availableApps: [RunningApp] = []
    @Published var selectedAppName: String = ""
    @Published var eventCount: Int = 0
    @Published var recordedActions: [RecordedAction] = []

    private let capture = EventCapture()
    private let inference = ActionInference()
    private let generator = WorkflowGenerator()

    private var cancellables = Set<AnyCancellable>()

    init() {
        Task {
            await self.refreshApps()
        }
    }

    /// Start the coordinator (refresh apps)
    func start() {
        Task {
            await self.refreshApps()
        }
    }

    /// Stop the coordinator
    func stop() {
        if isRecording {
            capture.stopRecording()
            isRecording = false
        }
    }

    /// Clear all recorded actions
    func clearRecording() {
        discardRecording()
    }

    /// Refresh list of running applications
    @MainActor
    func refreshApps() async {
        let apps = await getRunningApplications()
        self.availableApps = apps
    }

    /// Start recording for the selected app
    func startRecording() throws {
        // Find the app matching selectedAppName
        guard let app = availableApps.first(where: { $0.name == selectedAppName }) else {
            throw RecorderCoordinatorError.noTargetApp
        }
        self.targetApp = app

        do {
            try capture.startRecording(targetPid: app.id)
            self.isRecording = true
            self.isPaused = false
            self.capturedEventCount = 0
            self.inferredActions = []
            self.generatedYAML = ""

            // Set up real-time event callback
            capture.onEventCaptured = { [weak self] event in
                Task { @MainActor in
                    self?.capturedEventCount += 1
                    self?.eventCount += 1
                }
            }
        } catch {
            throw RecorderCoordinatorError.captureFailed(error)
        }
    }

    /// Pause recording (stop capturing but keep events)
    func pauseRecording() {
        guard isRecording else { return }
        capture.stopRecording()
        isRecording = false
        isPaused = true
    }

    /// Resume recording
    func resumeRecording() throws {
        guard isPaused else { return }
        guard let targetApp = targetApp else {
            throw RecorderCoordinatorError.noTargetApp
        }

        do {
            try capture.startRecording(targetPid: targetApp.id)
            isRecording = true
            isPaused = false

            capture.onEventCaptured = { [weak self] event in
                Task { @MainActor in
                    self?.capturedEventCount += 1
                }
            }
        } catch {
            throw RecorderCoordinatorError.captureFailed(error)
        }
    }

    /// Stop recording and generate workflow
    func stopRecording() -> String {
        capture.stopRecording()
        isRecording = false
        isPaused = false

        let events = capture.capturedEvents
        let actions = inference.inferActions(from: events)
        self.inferredActions = actions

        // Convert inferred actions to recorded actions for display
        self.recordedActions = actions.map { action in
            var details: [String: String] = [:]

            if let text = action.text {
                details["text"] = text
            }
            if let combo = action.combo {
                details["combo"] = combo
            }
            if let amount = action.amount {
                details["amount"] = String(amount)
            }
            if let duration = action.duration {
                details["duration"] = String(format: "%.1f", duration)
            }
            if let direction = action.direction {
                details["direction"] = direction.rawValue
            }

            return RecordedAction(
                type: actionTypeString(action.action),
                name: action.suggestedName,
                details: details,
                assertions: []
            )
        }

        guard let targetApp = targetApp else {
            return ""
        }

        let yaml = generator.generateYAML(
            name: "Recorded Workflow",
            targetAppName: targetApp.name,
            targetBundleId: targetApp.bundleId ?? "",
            actions: actions
        )

        self.generatedYAML = yaml
        return yaml
    }

    private func actionTypeString(_ action: InferredActionType) -> String {
        switch action {
        case .click: return "click"
        case .type: return "type"
        case .shortcut: return "shortcut"
        case .drag: return "drag"
        case .scroll: return "scroll"
        case .wait: return "wait"
        }
    }

    /// Save the generated YAML to a file
    func saveWorkflow(name: String, to url: URL) throws {
        let yaml = generatedYAML
        try yaml.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Discard recording
    func discardRecording() {
        if isRecording {
            capture.stopRecording()
            isRecording = false
        }
        isPaused = false
        capture.clearEvents()
        capturedEventCount = 0
        eventCount = 0
        inferredActions = []
        recordedActions = []
        generatedYAML = ""
    }

    // MARK: - Private Helpers

    private func getRunningApplications() async -> [RunningApp] {
        let workspace = NSWorkspace.shared
        let runningApps = workspace.runningApplications

        return runningApps.compactMap { nsApp in
            guard let bundleId = nsApp.bundleIdentifier else {
                return nil
            }

            let name = nsApp.localizedName ?? "Unknown"
            let pid = nsApp.processIdentifier

            // Get app icon
            var icon: NSImage?
            if let appURL = nsApp.bundleURL {
                icon = workspace.icon(forFile: appURL.path)
            }

            return RunningApp(
                id: pid,
                name: name,
                bundleId: bundleId,
                icon: icon
            )
        }.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
}

struct RunningApp: Identifiable, Hashable {
    let id: pid_t
    let name: String
    let bundleId: String?
    let icon: NSImage?

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(bundleId)
    }

    static func == (lhs: RunningApp, rhs: RunningApp) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.bundleId == rhs.bundleId
    }
}

enum RecorderCoordinatorError: LocalizedError {
    case noTargetApp
    case captureFailed(Error)

    var errorDescription: String? {
        switch self {
        case .noTargetApp:
            return "No target application selected."
        case .captureFailed(let error):
            return "Failed to start recording: \(error.localizedDescription)"
        }
    }
}
