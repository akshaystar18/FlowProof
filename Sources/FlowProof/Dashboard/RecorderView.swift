import SwiftUI
import UniformTypeIdentifiers

struct RecorderView: View {
    @StateObject private var coordinator = RecorderCoordinator()
    @State private var workflowName = ""
    @State private var showSaveDialog = false
    @State private var saveError: String?

    var body: some View {
        VStack(spacing: 0) {
            // Top: App selector
            appSelectorPanel
                .background(Color(.controlBackgroundColor))
                .border(Color.gray.opacity(0.2), width: 1)

            // Middle: Recording controls and event list
            VStack(spacing: 16) {
                recordingControlsPanel
                eventListPanel
            }
            .padding(16)

            // Bottom: YAML preview and save controls
            yamlPreviewPanel
                .background(Color(.controlBackgroundColor))
                .border(Color.gray.opacity(0.2), width: 1)

            workflowNameAndSavePanel
                .background(Color(.controlBackgroundColor))
                .border(Color.gray.opacity(0.2), width: 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            coordinator.start()
        }
        .onDisappear {
            coordinator.stop()
        }
        .alert("Save Workflow", isPresented: $showSaveDialog, actions: {
            Button("Cancel", role: .cancel) { }
            Button("Save", action: saveWorkflow)
        }, message: {
            Text("Workflow will be saved as '\(workflowName).yaml'")
        })
        .alert("Save Error", isPresented: .constant(saveError != nil), actions: {
            Button("OK") { saveError = nil }
        }, message: {
            if let error = saveError {
                Text(error)
            }
        })
    }

    // MARK: - Components

    private var appSelectorPanel: some View {
        HStack(spacing: 12) {
            Text("Target App:")
                .fontWeight(.semibold)

            Picker("Target App", selection: $coordinator.selectedAppName) {
                Text("None").tag("")
                Divider()
                ForEach(coordinator.availableApps.sorted { $0.name < $1.name }) { app in
                    HStack {
                        if let icon = app.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 16, height: 16)
                        }
                        Text(app.name)
                    }
                    .tag(app.name)
                }
            }
            .pickerStyle(.menu)

            if !coordinator.selectedAppName.isEmpty {
                Text("●")
                    .foregroundColor(.green)
                    .font(.system(size: 8))
                Text("Active")
                    .font(.caption)
                    .foregroundColor(.green)
            }

            Spacer()

            if !coordinator.selectedAppName.isEmpty {
                Button(action: { coordinator.selectedAppName = "" }) {
                    Text("Clear")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
    }

    private var recordingControlsPanel: some View {
        VStack(spacing: 12) {
            // Recording buttons
            HStack(spacing: 16) {
                Button(action: { try? coordinator.startRecording() }) {
                    HStack(spacing: 8) {
                        Image(systemName: "record.circle.fill")
                            .font(.system(size: 20))
                        Text("Record")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(coordinator.isRecording ? Color.red : Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(6)
                }
                .disabled(!coordinator.selectedAppName.isEmpty && coordinator.isRecording)

                if coordinator.isRecording {
                    Button(action: coordinator.pauseRecording) {
                        HStack(spacing: 8) {
                            Image(systemName: "pause.circle.fill")
                                .font(.system(size: 20))
                            Text("Pause")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                    }

                    Button(action: { _ = coordinator.stopRecording() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 20))
                            Text("Stop")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                    }
                } else if !coordinator.recordedActions.isEmpty {
                    Button(action: coordinator.clearRecording) {
                        HStack(spacing: 8) {
                            Image(systemName: "trash.circle.fill")
                                .font(.system(size: 20))
                            Text("Clear")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                    }
                }
            }

            // Status indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(coordinator.isRecording ? Color.red : Color.gray)
                    .frame(width: 8, height: 8)

                Text(coordinator.isRecording ? "Recording..." : "Idle")
                    .fontWeight(.semibold)

                Spacer()

                // Event counter
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(coordinator.eventCount) events")
                        .font(.body)
                        .fontWeight(.semibold)

                    Text("\(coordinator.recordedActions.count) actions inferred")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(6)
        }
    }

    private var eventListPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Captured Actions")
                .font(.headline)

            if coordinator.recordedActions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)

                    Text("No actions recorded yet")
                        .font(.body)
                        .foregroundColor(.secondary)

                    Text("Start recording to capture app interactions")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.controlBackgroundColor))
                .cornerRadius(6)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(Array(coordinator.recordedActions.enumerated()), id: \.element.id) { index, action in
                            RecordedActionRow(
                                action: action,
                                index: index + 1
                            )
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
    }

    private var yamlPreviewPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Generated YAML")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 12)

            ScrollView(.horizontal) {
                ScrollView(.vertical) {
                    Text(generateYAMLPreview())
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(12)
                        .background(Color(.black))
                        .textSelection(.enabled)
                }
            }
            .frame(maxHeight: 200)
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    private var workflowNameAndSavePanel: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Workflow Name")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("e.g., Login Flow", text: $workflowName)
                    .textFieldStyle(.roundedBorder)
            }

            Button(action: {
                if !workflowName.trimmingCharacters(in: .whitespaces).isEmpty {
                    showSaveDialog = true
                } else {
                    saveError = "Please enter a workflow name"
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down.fill")
                    Text("Save Workflow")
                        .fontWeight(.semibold)
                }
                .padding(10)
                .background(coordinator.recordedActions.isEmpty ? Color.gray : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(6)
            }
            .disabled(coordinator.recordedActions.isEmpty)

            Spacer()
        }
        .padding(12)
    }

    // MARK: - Helper Methods

    private func generateYAMLPreview() -> String {
        var yaml = """
        name: \(workflowName.isEmpty ? "Untitled Workflow" : workflowName)
        description: Automated workflow recorded on \(Date().shortDisplay)
        actions:
        """

        for (index, action) in coordinator.recordedActions.enumerated() {
            yaml += "\n  - step: \(index + 1)"
            yaml += "\n    action: \(action.type)"
            yaml += "\n    name: \(action.name.yamlEscaped)"

            if !action.details.isEmpty {
                yaml += "\n    details:"
                for (key, value) in action.details {
                    yaml += "\n      \(key): \(value.yamlEscaped)"
                }
            }

            if !action.assertions.isEmpty {
                yaml += "\n    assertions:"
                for assertion in action.assertions {
                    yaml += "\n      - type: \(assertion.type)"
                    yaml += "\n        target: \(assertion.target.yamlEscaped)"
                    if !assertion.value.isEmpty {
                        yaml += "\n        value: \(assertion.value.yamlEscaped)"
                    }
                }
            }
        }

        return yaml
    }

    private func saveWorkflow() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.yaml, .yml]
        panel.nameFieldStringValue = "\(workflowName.replacingOccurrences(of: " ", with: "-")).yaml"

        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }

            do {
                let yaml = generateYAMLPreview()
                try yaml.write(to: url, atomically: true, encoding: .utf8)

                let alert = NSAlert()
                alert.messageText = "Workflow Saved"
                alert.informativeText = "Your workflow has been saved to \(url.lastPathComponent)"
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
                alert.runModal()

                workflowName = ""
                coordinator.clearRecording()
            } catch {
                saveError = "Failed to save workflow: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Supporting Views

struct RecordedActionRow: View {
    let action: RecordedAction
    let index: Int

    var body: some View {
        HStack(spacing: 12) {
            // Index badge
            Text("\(index)")
                .font(.caption)
                .fontWeight(.semibold)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.blue))
                .foregroundColor(.white)

            // Action type badge
            Text(action.type.uppercased())
                .font(.caption2)
                .fontWeight(.semibold)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.green.opacity(0.15))
                .foregroundColor(.green)
                .cornerRadius(3)

            // Action name
            VStack(alignment: .leading, spacing: 2) {
                Text(action.name)
                    .font(.body)
                    .lineLimit(1)

                if !action.details.isEmpty {
                    Text(action.details.map { "\($0.key): \($0.value)" }.joined(separator: " • "))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if !action.assertions.isEmpty {
                Label("\(action.assertions.count)", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
        .padding(10)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(4)
    }
}

#Preview {
    RecorderView()
        .frame(width: 800, height: 900)
}
