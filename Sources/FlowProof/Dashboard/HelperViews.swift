import SwiftUI

// MARK: - Summary Card

struct SummaryCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Spacer()
            }
            Text(value)
                .font(.system(size: 32, weight: .bold, design: .rounded))
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

// MARK: - Quick Action Button

struct QuickActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundColor(color)
            .frame(width: 120, height: 80)
            .background(color.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Accessibility Warning Banner

struct AccessibilityWarningBanner: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Accessibility Permission Required")
                    .fontWeight(.semibold)
                Text("FlowProof needs accessibility access to automate workflows. Open System Settings to grant permission.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Open Settings") {
                AccessibilityEngine.requestAccess()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(16)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Empty State View

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}

// MARK: - Run Row View

struct RunRowView: View {
    let run: WorkflowRun

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: statusIcon)
                .font(.title2)
                .foregroundColor(statusColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(run.workflowName)
                    .fontWeight(.medium)
                Text(run.startedAt, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Step counts
            HStack(spacing: 8) {
                StepBadge(count: run.passedSteps, color: .green, icon: "checkmark")
                StepBadge(count: run.failedSteps, color: .red, icon: "xmark")
                if run.skippedSteps > 0 {
                    StepBadge(count: run.skippedSteps, color: .orange, icon: "forward")
                }
            }

            // Duration
            if let duration = run.durationMs {
                Text(formatDuration(duration))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private var statusIcon: String {
        switch run.status {
        case .passed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .running: return "arrow.triangle.2.circlepath.circle.fill"
        case .aborted: return "stop.circle.fill"
        default: return "circle.dashed"
        }
    }

    private var statusColor: Color {
        switch run.status {
        case .passed: return .green
        case .failed: return .red
        case .running: return .blue
        case .aborted: return .orange
        default: return .secondary
        }
    }

    private func formatDuration(_ ms: Int64) -> String {
        if ms < 1000 { return "\(ms)ms" }
        let seconds = Double(ms) / 1000.0
        if seconds < 60 { return String(format: "%.1fs", seconds) }
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(minutes)m \(secs)s"
    }
}

// MARK: - Step Badge

struct StepBadge: View {
    let count: Int
    let color: Color
    let icon: String

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.caption2)
            Text("\(count)")
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundColor(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.1))
        .cornerRadius(4)
    }
}

// MARK: - Pass Rate Badge

struct PassRateBadge: View {
    let rate: Double

    var body: some View {
        VStack(spacing: 2) {
            Text("\(Int(rate * 100))%")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(rateColor)
            Text("pass rate")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(rateColor.opacity(0.1))
        .cornerRadius(10)
    }

    private var rateColor: Color {
        if rate >= 0.9 { return .green }
        if rate >= 0.7 { return .yellow }
        return .red
    }
}
