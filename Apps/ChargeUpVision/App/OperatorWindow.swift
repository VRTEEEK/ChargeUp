import SwiftUI
import ChargeUpCore

/// The only UI on the headset. The child never sees this window; the
/// operator uses it to open the space and watch the link.
struct OperatorWindow: View {
    static let id = "operator"

    @ObservedObject var controller: SessionController
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @State private var spaceOpen = false

    /// Debug only, default off: `CHARGEUP_AUTOSTART=1` in the environment
    /// presses Start on launch so the simulator can be driven without a click.
    private static let autostart = ProcessInfo.processInfo.environment["CHARGEUP_AUTOSTART"] == "1"

    var body: some View {
        VStack(spacing: 20) {
            Text("Charge Up")
                .font(.largeTitle.bold())

            if !spaceOpen {
                Button {
                    Task { await openSpace() }
                } label: {
                    Text("Start")
                        .font(.title.bold())
                        .frame(maxWidth: .infinity, minHeight: 72)
                }
                .buttonStyle(.borderedProminent)
            } else {
                status
                HStack {
                    Button("Reset session", role: .destructive) { controller.reset() }
                    Spacer()
                    Button("Stop") {
                        Task {
                            await dismissImmersiveSpace()
                            controller.stop()
                            spaceOpen = false
                        }
                    }
                }
            }
        }
        .padding(28)
        .task {
            if OperatorWindow.autostart, !spaceOpen { await openSpace() }
        }
    }

    private func openSpace() async {
        switch await openImmersiveSpace(id: ImmersiveView.id) {
        case .opened:
            spaceOpen = true
            controller.start()
        case .userCancelled, .error:
            break
        @unknown default:
            break
        }
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent("Step", value: controller.currentStep?.name ?? controller.currentStepId)
            LabeledContent("Peers") {
                if controller.peers.isEmpty {
                    Text("waiting for companions").foregroundStyle(.secondary)
                } else {
                    Text(controller.peers.map { $0.role?.rawValue ?? "?" }.joined(separator: ", "))
                }
            }
            LabeledContent("Forearm") {
                HStack(spacing: 6) {
                    Circle()
                        .fill(forearmColor)
                        .frame(width: 10, height: 10)
                    Text(controller.forearmStatus)
                }
            }
            LabeledContent("Lantern", value: controller.lanternPlacement)
            LabeledContent("Audio", value: controller.audioStatus)
            LabeledContent("Recording", value: controller.lastRecording)
            LabeledContent("Link", value: controller.host.channel.lastDiagnostic)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var forearmColor: Color {
        let s = controller.forearmStatus
        if s.hasPrefix("tracked") || s == "simulated" { return .green }
        if s.hasPrefix("holding") { return .yellow }
        if s.hasPrefix("faded") || s.hasPrefix("searching") { return .orange }
        if s.hasPrefix("idle") || s.hasPrefix("simulated") { return .gray }
        return .red
    }
}
