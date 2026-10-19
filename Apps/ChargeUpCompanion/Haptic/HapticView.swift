import SwiftUI
import ChargeUpCore

/// The phone in the child's free hand. Shows only a connection dot and
/// reacts to each step's `haptic` field: `pulse` taps once, `ramp` runs the
/// rising buzz for rampDurationMs and ends by itself, `none` does nothing
/// so a ramp started at the needle moment is not cut off by the next step.
/// Reset and the end of the session stop everything.
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
        session.mirror.onStepChanged = { [weak player] id, step in
            guard let player else { return }
            guard let step else {
                player.stop()   // idle or complete
                return
            }
            switch step.haptic {
            case .pulse: player.pulse()
            case .ramp: player.startRamp(values)
            case .none: break
            }
        }
        // Catch up if we joined mid-ramp.
        if session.mirror.currentStep?.haptic == .ramp { player.startRamp(values) }
    }
}
