import SwiftUI
import ChargeUpCore

/// Mirrors the nurse's step list without the button. The per-step prompt
/// line for the parent is Milestone 3 task 1 and is not here yet.
struct ParentView: View {
    @ObservedObject var session: CompanionSession

    var body: some View {
        StepListView(sequence: session.sequence, currentStepId: session.mirror.currentStepId, showCues: false)
            .padding()
    }
}
