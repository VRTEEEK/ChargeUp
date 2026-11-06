import SwiftUI
import ChargeUpCore

/// Where a step stands relative to the session.
enum StageStatus {
    case done, current, upcoming

    static func of(index: Int, in sequence: ChargeSequence, currentStepId: String) -> StageStatus {
        if currentStepId == SessionMarker.complete { return .done }
        guard let current = sequence.index(of: currentStepId) else { return .upcoming }
        return index < current ? .done : (index == current ? .current : .upcoming)
    }
}

/// The seven steps as a vertical timeline, drawn from sequence.json. Shared
/// by the Nurse (with clinical cues) and the Parent (names only). It only
/// shows the session; nothing here can change it.
struct StageTimeline: View {
    let sequence: ChargeSequence
    let currentStepId: String
    /// Show each step's clinical cue under its name.
    var showsCues: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(sequence.steps.enumerated()), id: \.element.id) { index, step in
                let status = StageStatus.of(index: index, in: sequence, currentStepId: currentStepId)
                StageRow(number: index + 1,
                         step: step,
                         status: status,
                         isNext: isNext(index),
                         isLast: index == sequence.steps.count - 1,
                         showsCue: showsCues)
                    .id(step.id)
            }
        }
        .animation(Motion.gentle(reduceMotion), value: currentStepId)
    }

    private func isNext(_ index: Int) -> Bool {
        if currentStepId == SessionMarker.idle { return index == 0 }
        guard let current = sequence.index(of: currentStepId) else { return false }
        return index == current + 1
    }
}

struct StageRow: View {
    let number: Int
    let step: Step
    let status: StageStatus
    let isNext: Bool
    let isLast: Bool
    let showsCue: Bool

    @Environment(\.promptLanguage) private var language

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                indicator
                    .padding(.top, 12)
                // The line to the next step: gold where the journey has passed.
                Rectangle()
                    .fill(status == .done ? Palette.gold.opacity(0.7) : Palette.hairline)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                    .opacity(isLast ? 0 : 1)
            }
            .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(step.name)
                        .font(status == .current ? TypeScale.cardTitle : TypeScale.body.weight(.medium))
                        .foregroundStyle(status == .upcoming ? Palette.muted : Palette.text)
                        .opacity(status == .done ? 0.7 : 1)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    statusLabel
                }
                if showsCue {
                    Text(step.clinicalCue)
                        .font(TypeScale.secondary)
                        .foregroundStyle(Palette.muted)
                        .opacity(status == .done ? 0.7 : 1)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                    .fill(status == .current ? Palette.elevated : Color.clear))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                    .strokeBorder(status == .current ? Palette.gold : Color.clear, lineWidth: 1.5))
            .padding(.bottom, isLast ? 0 : 6)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(number). \(step.name)")
        .accessibilityValue(accessibilityStatus)
    }

    @ViewBuilder
    private var indicator: some View {
        ZStack {
            switch status {
            case .done:
                Circle().fill(Palette.success.opacity(0.18))
                Circle().strokeBorder(Palette.success, lineWidth: 1.5)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.success)
            case .current:
                Circle().fill(Palette.gold.opacity(0.22))
                Circle().strokeBorder(Palette.brightGold, lineWidth: 2)
                Circle().fill(Palette.brightGold).padding(8)
                    .shadow(color: Palette.brightGold.opacity(0.8), radius: 5)
            case .upcoming:
                Circle().strokeBorder(Palette.muted.opacity(0.45), lineWidth: 1.5)
                Text("\(number)")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Palette.muted)
            }
        }
        .frame(width: 26, height: 26)
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch status {
        case .current:
            Text(Copy.now.in(language))
                .font(TypeScale.eyebrow)
                .foregroundStyle(Palette.background)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Palette.brightGold))
        case .done:
            Text(Copy.done.in(language))
                .font(TypeScale.eyebrow)
                .foregroundStyle(Palette.success)
        case .upcoming where isNext:
            Text(Copy.next.in(language))
                .font(TypeScale.eyebrow)
                .foregroundStyle(Palette.muted)
        case .upcoming:
            EmptyView()
        }
    }

    private var accessibilityStatus: String {
        switch status {
        case .done: Copy.done.in(language)
        case .current: Copy.now.in(language)
        case .upcoming: isNext ? Copy.next.in(language) : ""
        }
    }
}

/// Seven short bars, one per step: the journey at a glance.
struct StageProgressBar: View {
    let sequence: ChargeSequence
    let currentStepId: String

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(sequence.steps.enumerated()), id: \.element.id) { index, _ in
                let status = StageStatus.of(index: index, in: sequence, currentStepId: currentStepId)
                Capsule()
                    .fill(color(status))
                    .frame(height: 6)
                    .shadow(color: status == .current ? Palette.brightGold.opacity(0.6) : .clear, radius: 4)
            }
        }
        .accessibilityHidden(true)
    }

    private func color(_ status: StageStatus) -> Color {
        switch status {
        case .done: Palette.gold
        case .current: Palette.brightGold
        case .upcoming: Palette.elevated
        }
    }
}
