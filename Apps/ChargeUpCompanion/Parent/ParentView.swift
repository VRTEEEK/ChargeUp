import SwiftUI
import ChargeUpCore

/// The parent's screen: the nurse's step list without the button, and one
/// large prompt line for the current step from sequence.json's `prompts`.
/// Readable at arm's length.
struct ParentView: View {
    @ObservedObject var session: CompanionSession

    private var mirror: SessionMirror { session.mirror }

    var body: some View {
        VStack(spacing: 24) {
            promptCard
            StepListView(sequence: session.sequence, currentStepId: mirror.currentStepId, showCues: false)
        }
        .padding()
    }

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(mirror.currentStep?.name ?? (mirror.isComplete ? "Done" : "Getting ready"))
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(session.sequence.prompt(for: mirror.currentStepId))
                .font(.system(size: 40, weight: .semibold))
                .minimumScaleFactor(0.6)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeInOut(duration: 0.25), value: mirror.currentStepId)
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .leading)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
    }
}
