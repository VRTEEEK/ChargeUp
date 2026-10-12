import SwiftUI
import ChargeUpCore

/// The phone in the child's free hand. Shows only a connection dot and
/// reacts to each step's `haptic` field: pulse, ramp, or stop.
struct HapticView: View {
    @ObservedObject var session: CompanionSession
    @StateObject private var player = HapticPlayer()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Circle()
                .fill(session.isConnected ? Color.green : Color.red)
                .frame(width: 220, height: 220)
                .shadow(color: (session.isConnected ? Color.green : Color.red).opacity(0.6), radius: 40)
            if !player.isAvailable {
                VStack {
                    Spacer()
                    Text("No haptic hardware on this device")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.bottom, 24)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { bind() }
        .onDisappear {
            player.stop()
            session.mirror.onStepChanged = nil
        }
    }

    private func bind() {
        let config = session.sequence.config
        let values = SequenceConfigValues(startIntensity: config.rampStartIntensity,
                                          endIntensity: config.rampEndIntensity,
                                          sharpness: config.rampSharpness,
                                          durationSeconds: Double(config.rampDurationMs) / 1000)
        session.mirror.onStepChanged = { [weak player] _, step in
            guard let player else { return }
            switch step?.haptic ?? .none {
            case .pulse: player.pulse()
            case .ramp: player.startRamp(values)
            case .none: player.stop()
            }
        }
        // Catch up if we joined mid-ramp.
        if session.mirror.currentStep?.haptic == .ramp { player.startRamp(values) }
    }
}
