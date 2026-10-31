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
    /// True from the Start tap until the space opens: assets load for a few
    /// seconds, and a second tap must not open the space twice.
    @State private var starting = false

    /// The start screen is the key art at 16:9, with the Start button in the
    /// clear band between the logo and the podium (fractions of the art).
    private static let startSize = CGSize(width: 960, height: 540)
    private static let buttonCentre = CGPoint(x: 0.5, y: 0.725)
    private static let buttonWidth: CGFloat = 0.28

    /// Debug only, default off: `CHARGEUP_AUTOSTART=1` in the environment
    /// presses Start on launch so the simulator can be driven without a click.
    private static let autostart = ProcessInfo.processInfo.environment["CHARGEUP_AUTOSTART"] == "1"

    var body: some View {
        Group {
            if !spaceOpen {
                startScreen
            } else {
                session
            }
        }
        .task {
            if OperatorWindow.autostart, !spaceOpen { await openSpace() }
        }
    }

    private var startScreen: some View {
        let size = Self.startSize
        return ZStack {
            Image("StartBackground")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size.width, height: size.height)
                .clipped()
                .accessibilityHidden(true)
            Button {
                Task { await openSpace() }
            } label: {
                Image("StartButton")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size.width * Self.buttonWidth)
                    .opacity(starting ? 0.6 : 1)
                    .overlay { if starting { ProgressView() } }
            }
            .buttonStyle(.plain)
            .contentShape(.hoverEffect, Capsule())
            .hoverEffect(.lift)
            .disabled(starting)
            .accessibilityLabel("Start")
            .position(x: size.width * Self.buttonCentre.x, y: size.height * Self.buttonCentre.y)
        }
        .frame(width: size.width, height: size.height)
    }

    private var session: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Charge Up")
                    .font(.largeTitle.bold())
                status
                if !controller.host.missingRoles.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Reconnecting: \(controller.host.missingRoles.map(\.rawValue).sorted().joined(separator: ", ")). Session held at \(controller.currentStep?.name ?? controller.currentStepId).")
                            .font(.callout)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                }
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
            .padding(28)
        }
        .frame(width: 560, height: 620)
    }

    private func openSpace() async {
        guard !starting else { return }
        starting = true
        defer { starting = false }
        await controller.loadAssets()
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
            LabeledContent("Assets", value: controller.assetStatus)
                .font(.footnote)
            LabeledContent("Sleeve", value: controller.sleeveStatus)
                .font(.footnote)
            LabeledContent("Cable rebuilds", value: controller.cableStatus)
                .font(.footnote)
            LabeledContent("Companion", value: controller.companionStatus)
                .font(.footnote)
            LabeledContent("Tree", value: controller.treeStatus)
                .font(.footnote)
            LabeledContent("Recording", value: controller.lastRecording)
            LabeledContent("Sky") {
                HStack {
                    Text(controller.skyStatus)
                    Button("Reset Sky", role: .destructive) { controller.resetSky() }
                        .font(.footnote)
                }
            }
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
