import SwiftUI

struct SettingsView: View {
    @State private var screenshotQuality: Double = 0.8
    @State private var defaultTimeout: Double = 300
    @State private var retryCount: Int = 3
    @State private var captureScreenshots = true

    var body: some View {
        Form {
            Section("Automation") {
                HStack {
                    Text("Default Timeout")
                    Spacer()
                    TextField("", value: $defaultTimeout, format: .number)
                        .frame(width: 80)
                    Text("seconds")
                        .foregroundColor(.secondary)
                }
                Stepper("Retry Count: \(retryCount)", value: $retryCount, in: 0...10)
            }

            Section("Screenshots") {
                Toggle("Capture Screenshots Per Step", isOn: $captureScreenshots)
                HStack {
                    Text("Quality")
                    Slider(value: $screenshotQuality, in: 0.1...1.0, step: 0.1)
                    Text("\(Int(screenshotQuality * 100))%")
                        .foregroundColor(.secondary)
                        .frame(width: 40)
                }
            }

            Section("Accessibility") {
                HStack {
                    Text("Permission Status")
                    Spacer()
                    if AccessibilityEngine.isAccessibilityEnabled() {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Label("Not Granted", systemImage: "xmark.circle.fill")
                            .foregroundColor(.red)
                    }
                }
                Button("Open Accessibility Settings") {
                    AccessibilityEngine.requestAccess()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 400)
    }
}
