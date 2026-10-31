import SwiftUI
import ChargeUpCore

/// The parent's screen: the nurse's step list without the button, one
/// large prompt line for the current step in the chosen language, and the
/// child's lanterns so far. Readable at arm's length; right to left in Arabic.
struct ParentView: View {
    @ObservedObject var session: CompanionSession
    let language: PromptLanguage

    private var mirror: SessionMirror { session.mirror }

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > 700
            if wide {
                HStack(alignment: .top, spacing: 24) {
                    VStack(spacing: 24) {
                        promptCard
                        StepListView(sequence: session.sequence, currentStepId: mirror.currentStepId, showCues: false)
                    }
                    lanterns.frame(width: 300)
                }
                .padding()
            } else {
                ScrollView {
                    VStack(spacing: 24) {
                        promptCard
                        StepListView(sequence: session.sequence, currentStepId: mirror.currentStepId, showCues: false)
                        lanterns
                    }
                    .padding()
                }
            }
        }
    }

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(mirror.currentStep?.name ?? (mirror.isComplete ? "Done" : "Getting ready"))
                .font(.companion(.title3))
                .foregroundStyle(.secondary)
            Text(session.sequence.prompt(for: mirror.currentStepId, in: language))
                .font(.companion(size: 40, weight: .semibold))
                .minimumScaleFactor(0.6)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeInOut(duration: 0.25), value: mirror.currentStepId)
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .leading)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
    }

    /// Past sessions from the headset's skyState, newest first, with a count.
    private var lanterns: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Lanterns").font(.companion(.title2).bold())
                Spacer()
                Text("\(mirror.sessions.count)")
                    .font(.companion(.title2).monospacedDigit().bold())
                    .foregroundStyle(.secondary)
            }
            if mirror.sessions.isEmpty {
                Text(session.isConnected ? "No lanterns yet." : "Lanterns appear once the headset is linked.")
                    .font(.companion(.body))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(mirror.sessions.reversed().enumerated()), id: \.element.id) { index, record in
                    HStack(spacing: 12) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(Color.yellow.opacity(0.4 + 0.6 * record.fill))
                        Text(record.date, style: .date)
                            .font(.companion(.title3))
                        Spacer()
                        Text(String(format: "%.0f%%", record.fill * 100))
                            .font(.companion(.title3).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(index == 0 ? Color.yellow.opacity(0.12) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(.top, 4)
    }
}
