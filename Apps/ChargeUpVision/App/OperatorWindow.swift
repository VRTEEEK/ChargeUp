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

    var body: some View {
        VStack(spacing: 20) {
            Text("Charge Up")
                .font(.largeTitle.bold())

            if !spaceOpen {
                Button {
                    Task {
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
                    Text(controller.forearm.status.rawValue)
                    if !controller.forearm.lastError.isEmpty {
                        Text(controller.forearm.lastError).foregroundStyle(.secondary)
                    }
                }
            }
            LabeledContent("Link", value: controller.host.channel.lastDiagnostic)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var forearmColor: Color {
        switch controller.forearm.status {
        case .tracked: return .green
        case .holding: return .yellow
        case .faded, .searching: return .orange
        case .idle: return .gray
        case .unsupported, .unauthorized, .failed: return .red
        }
    }
}
