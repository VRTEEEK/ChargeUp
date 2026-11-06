import SwiftUI
import ChargeUpCore

/// The parent's screen: a lantern that glows with the child's, one large
/// prompt line for the current step in the chosen language, the lanterns
/// collected so far, and the journey without its clinical cues. It has no
/// control over the session. Readable at arm's length; right to left in Arabic.
struct ParentView: View {
    @ObservedObject var session: CompanionSession

    @Environment(\.promptLanguage) private var language
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var mirror: SessionMirror { session.mirror }

    /// Lanterns listed by date; the count above covers them all.
    private static let recentLanterns = 5

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: Metrics.gap) {
                    header
                    if geo.size.width >= 900 {
                        HStack(alignment: .top, spacing: Metrics.gap) {
                            lanternCard.frame(maxWidth: .infinity)
                            VStack(spacing: Metrics.gap) {
                                collectionCard
                                journeyCard
                            }
                            .frame(width: 360)
                        }
                    } else {
                        lanternCard
                        collectionCard
                        journeyCard
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .frame(maxWidth: 1240)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text(Copy.parentTitle.in(language))
                .font(TypeScale.appTitle)
                .foregroundStyle(LinearGradient(colors: [Palette.brightGold, Palette.gold],
                                                startPoint: .top, endPoint: .bottom))
                .multilineTextAlignment(.center)
            Text(Copy.parentSubtitle.in(language))
                .font(TypeScale.body)
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 4)
    }

    private var statusTitle: String {
        if let step = mirror.currentStep { return step.name }
        return mirror.isComplete ? Copy.allDone.in(language) : Copy.gettingReady.in(language)
    }

    /// The lantern and the line to read out.
    private var lanternCard: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 32) {
                lantern.frame(width: 190)
                status
            }
            .frame(minWidth: 560)
            VStack(spacing: 24) {
                lantern.frame(height: 240)
                status
            }
        }
        .frame(maxWidth: .infinity)
        .chargeCard(elevated: true, accent: Palette.gold)
    }

    private var lantern: some View {
        LanternProgressView(level: mirror.charge)
            .padding(.vertical, 12)
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow(text: statusTitle, color: Palette.brightGold)
            Text(session.sequence.prompt(for: mirror.currentStepId, in: language))
                .font(.companion(size: 40, weight: .semibold))
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentTransition(.opacity)
                .animation(Motion.gentle(reduceMotion), value: mirror.currentStepId)
            StageProgressBar(sequence: session.sequence, currentStepId: mirror.currentStepId)
                .frame(maxWidth: 360)
                .padding(.top, 4)
            Text(Copy.lanternMirror.in(language))
                .font(TypeScale.status)
                .foregroundStyle(Palette.muted)
        }
        .accessibilityElement(children: .combine)
    }

    /// Past sessions from the headset's skyState: the count, then the newest few.
    /// Without the link the count is the last one received, and says so.
    private var collectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow(text: Copy.lanternsCollected.in(language))
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(session.wasConnected || !mirror.sessions.isEmpty ? "\(mirror.sessions.count)" : "–")
                    .font(.companion(size: 48, weight: .bold).monospacedDigit())
                    .foregroundStyle(Palette.brightGold)
                Image(systemName: "sparkles")
                    .foregroundStyle(Palette.gold)
            }
            if !session.isConnected {
                StatusBadge(kind: .waiting, text: Copy.awaitingConnection.in(language))
            } else if mirror.sessions.isEmpty {
                Text(Copy.noLanternsYet.in(language))
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.muted)
            }
            if !mirror.sessions.isEmpty {
                let newest = Array(mirror.sessions.reversed().prefix(Self.recentLanterns))
                VStack(spacing: 6) {
                    ForEach(Array(newest.enumerated()), id: \.element.id) { index, record in
                        LanternRecordRow(record: record, isNewest: index == 0)
                    }
                }
                if mirror.sessions.count > newest.count {
                    Text(Copy.earlierLanterns.in(language, mirror.sessions.count - newest.count))
                        .font(TypeScale.status)
                        .foregroundStyle(Palette.muted)
                        .padding(.horizontal, 10)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .chargeCard()
    }

    private var journeyCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Eyebrow(text: Copy.journey.in(language))
            StageTimeline(sequence: session.sequence, currentStepId: mirror.currentStepId, showsCues: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .chargeCard()
    }
}

/// One lantern in the sky: its date and how full it was when the needle came out.
private struct LanternRecordRow: View {
    let record: SessionRecord
    let isNewest: Bool

    var body: some View {
        HStack(spacing: 12) {
            LanternProgressView(level: record.fill, showsStars: false)
                .frame(height: 30)
            Text(record.date, style: .date)
                .font(TypeScale.body)
            Spacer()
            Text(String(format: "%.0f%%", record.fill * 100))
                .font(TypeScale.status.monospacedDigit())
                .foregroundStyle(Palette.muted)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isNewest ? Palette.gold.opacity(0.12) : Color.clear))
        .accessibilityElement(children: .combine)
    }
}
