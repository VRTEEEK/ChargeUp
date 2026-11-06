import SwiftUI
import ChargeUpCore

/// The nurse's whole interface: the treatment journey, the current stage
/// with one big button, and the link, readiness and session controls.
///
/// Keys (a Mac, or an iPad with a keyboard), each also a button for the
/// mouse: Space is the big button on every step but the countdown, where
/// only Return sends CONNECT, so the needle moment never fires on the
/// key that advances everything else. R resets the session, K asks to
/// reset the sky.
///
/// Wide windows get three columns; narrower ones put the journey under the
/// current stage. The big button stays pinned under the stage in both, so it
/// never scrolls away; the narrowest stack everything with the button near the top.
struct NurseView: View {
    @ObservedObject var session: CompanionSession

    @Environment(\.promptLanguage) private var language

    private var mirror: SessionMirror { session.mirror }

    var body: some View {
        GeometryReader { geo in
            if geo.size.width >= 1100 {
                HStack(alignment: .top, spacing: Metrics.gap) {
                    journeyScroll.frame(width: 330)
                    ScrollView { CurrentStagePanel(session: session, includesButton: false) }
                        .safeAreaInset(edge: .bottom, spacing: Metrics.gap) { PrimaryActionButton(session: session) }
                        .frame(maxWidth: .infinity)
                    ScrollView { SessionPanel(session: session) }
                        .frame(width: 320)
                }
                .padding(Metrics.gap)
            } else if geo.size.width >= 720 {
                HStack(alignment: .top, spacing: Metrics.gap) {
                    ScrollView {
                        VStack(spacing: Metrics.gap) {
                            CurrentStagePanel(session: session, includesButton: false)
                            journeyCard
                        }
                    }
                    .safeAreaInset(edge: .bottom, spacing: Metrics.gap) { PrimaryActionButton(session: session) }
                    .frame(maxWidth: .infinity)
                    ScrollView { SessionPanel(session: session) }
                        .frame(width: 300)
                }
                .padding(Metrics.gap)
            } else {
                ScrollView {
                    VStack(spacing: Metrics.gap) {
                        CurrentStagePanel(session: session)
                        SessionPanel(session: session)
                        journeyCard
                    }
                    .padding(16)
                }
            }
        }
        .scrollIndicators(.automatic)
    }

    /// The journey on its own scroll, kept centred on the current step.
    private var journeyScroll: some View {
        ScrollViewReader { proxy in
            ScrollView { journeyCard }
                .onChange(of: mirror.currentStepId) { _, id in
                    guard session.sequence.step(id: id) != nil else { return }
                    withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(id, anchor: .center) }
                }
        }
    }

    private var journeyCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Eyebrow(text: Copy.treatmentJourney.in(language))
            StageTimeline(sequence: session.sequence, currentStepId: mirror.currentStepId, showsCues: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .chargeCard()
    }
}

// MARK: - Current stage and the button

/// What is happening now, what the child feels and sees, the line to say,
/// and, unless the layout pins it elsewhere, the session's single button.
struct CurrentStagePanel: View {
    @ObservedObject var session: CompanionSession
    var includesButton = true

    @Environment(\.promptLanguage) private var language
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var mirror: SessionMirror { session.mirror }
    private var sequence: ChargeSequence { session.sequence }

    var body: some View {
        VStack(spacing: Metrics.gap) {
            stageCard
            if includesButton { PrimaryActionButton(session: session) }
            progressCard
        }
    }

    private var title: String {
        if let step = mirror.currentStep { return step.name }
        return mirror.isComplete ? Copy.sessionComplete.in(language) : Copy.gettingReady.in(language)
    }

    private var stageCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Eyebrow(text: Copy.currentStage.in(language), color: Palette.brightGold)
                        if let index = mirror.currentIndex {
                            Text(Copy.stageOf.in(language, index + 1, sequence.steps.count))
                                .font(TypeScale.status)
                                .foregroundStyle(Palette.muted)
                        }
                    }
                    Text(title)
                        .font(TypeScale.appTitle)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.opacity)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Copy.sayToChild.in(language))
                            .font(TypeScale.status)
                            .foregroundStyle(Palette.muted)
                        Text(sequence.prompt(for: mirror.currentStepId, in: language))
                            .font(TypeScale.cardTitle.weight(.regular))
                            .foregroundStyle(Palette.text.opacity(0.92))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                VStack(spacing: 8) {
                    LanternProgressView(level: mirror.charge)
                        .frame(height: 130)
                    Text("\(Copy.lanternCharge.in(language)) \(Int((mirror.charge * 100).rounded()))%")
                        .font(TypeScale.status.monospacedDigit())
                        .foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.center)
                }
                .frame(width: 110)
            }

            if let step = mirror.currentStep {
                Rectangle().fill(Palette.hairline).frame(height: 1)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 24) { details(step) }
                    VStack(alignment: .leading, spacing: 14) { details(step) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .chargeCard(elevated: true, accent: Palette.gold)
        .animation(Motion.gentle(reduceMotion), value: mirror.currentStepId)
    }

    @ViewBuilder
    private func details(_ step: Step) -> some View {
        DetailBlock(label: Copy.childFeels.in(language), text: step.clinicalCue, icon: "hand.raised")
        DetailBlock(label: Copy.childSees.in(language), text: step.perceived, icon: "sparkles")
    }

    private var progressCard: some View {
        let done: Int = {
            if mirror.isComplete { return sequence.steps.count }
            return mirror.currentIndex.map { $0 + 1 } ?? 0
        }()
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Eyebrow(text: Copy.stageProgress.in(language))
                Spacer()
                Text("\(done) / \(sequence.steps.count)")
                    .font(TypeScale.status.monospacedDigit())
                    .foregroundStyle(Palette.muted)
            }
            StageProgressBar(sequence: sequence, currentStepId: mirror.currentStepId)
        }
        .chargeCard()
        .accessibilityElement(children: .combine)
    }
}

/// The session's single button. Its label comes from sequence.json via the
/// mirror; the caption under it says why it is waiting or what it sends.
struct PrimaryActionButton: View {
    @ObservedObject var session: CompanionSession

    @Environment(\.promptLanguage) private var language

    private var mirror: SessionMirror { session.mirror }
    private var isCountdown: Bool { mirror.currentStepId == StepID.countdown }

    var body: some View {
        Button {
            mirror.tapButton()
        } label: {
            VStack(spacing: 8) {
                Text(mirror.buttonLabel)
                    .font(.companion(size: 40, weight: .heavy))
                    .tracking(1)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if let caption = buttonCaption {
                        Text(caption)
                    }
                    #if os(macOS)
                    if mirror.isButtonEnabled {
                        KeyCap(isCountdown ? "Return" : "Space", onGold: true)
                    }
                    #endif
                }
                .font(TypeScale.status)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 140)
        }
        .buttonStyle(GoldButtonStyle(ringed: isCountdown))
        .disabled(!mirror.isButtonEnabled)
        .keyboardShortcut(isCountdown ? .return : .space, modifiers: [])
        .accessibilityHint(buttonCaption ?? "")
    }

    /// The line under the label: why the button is waiting, or what it does
    /// that the label alone does not say.
    private var buttonCaption: String? {
        if !session.isConnected { return Copy.waitingForHeadset.in(language) }
        if isCountdown { return Copy.needleMoment.in(language) }
        if mirror.isComplete { return Copy.sessionComplete.in(language) }
        if !mirror.isButtonEnabled { return Copy.advancesOnItsOwn.in(language) }
        return nil
    }
}

private struct DetailBlock: View {
    let label: String
    let text: String
    let icon: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.brightGold)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Palette.gold.opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(TypeScale.status)
                    .foregroundStyle(Palette.muted)
                Text(text)
                    .font(TypeScale.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Link, readiness and controls

/// The right-hand column: the headset link, the two readiness signals, the
/// session tools, and the resets set apart at the bottom.
struct SessionPanel: View {
    @ObservedObject var session: CompanionSession

    @Environment(\.promptLanguage) private var language
    @State private var confirmingResetSky = false

    private var mirror: SessionMirror { session.mirror }

    var body: some View {
        VStack(spacing: Metrics.gap) {
            HeadsetCard(session: session)
            readinessCard
            sessionCard
            resetsCard
        }
    }

    // Presence comes only from the headset; without the link the last
    // values are stale, so they show as no signal rather than as ready.
    private var readinessCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: Copy.readiness.in(language))
            ReadinessRow(label: Copy.headOnPort.in(language), icon: "eye",
                         state: readiness(mirror.headOnPort))
            ReadinessRow(label: Copy.armStill.in(language), icon: "hand.raised",
                         state: readiness(mirror.armStill))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .chargeCard()
    }

    private func readiness(_ on: Bool) -> ReadinessRow.State {
        guard session.isConnected else { return .noSignal }
        return on ? .yes : .notYet
    }

    private var sessionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow(text: Copy.session.in(language))
            Toggle(isOn: Binding(get: { session.rehearsal.isOn }, set: { session.rehearsal.set($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Copy.rehearsal.in(language)).font(TypeScale.body.weight(.semibold))
                    Text(Copy.rehearsalDetail.in(language, session.sequence.config.rehearsalInterval))
                        .font(TypeScale.status)
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            .tint(Palette.gold)
            ShareLink(item: LogExport(csv: session.channel.log.csv()),
                      preview: SharePreview("Charge Up log")) {
                Label(Copy.exportLog.in(language), systemImage: "square.and.arrow.up")
            }
            .buttonStyle(QuietButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .chargeCard()
    }

    /// Kept apart and in the error tint. Reset Sky wipes the child's saved
    /// lanterns on the headset, so it asks first; the session reset does not,
    /// because the operator may need it at once.
    private var resetsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: Copy.resets.in(language), color: Palette.error)
            VStack(spacing: 10) {
                Button(role: .destructive) {
                    mirror.sendReset()
                } label: {
                    HStack(spacing: 6) {
                        Text(Copy.resetSession.in(language))
                        #if os(macOS)
                        KeyCap("R")
                        #endif
                    }
                }
                .keyboardShortcut("r", modifiers: [])
                Button(role: .destructive) {
                    confirmingResetSky = true
                } label: {
                    HStack(spacing: 6) {
                        Text(Copy.resetSky.in(language))
                        #if os(macOS)
                        KeyCap("K")
                        #endif
                    }
                }
                .keyboardShortcut("k", modifiers: [])
            }
            .buttonStyle(QuietButtonStyle(tint: Palette.error))
            .disabled(!session.isConnected)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Metrics.cardPadding)
        .background(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
            .fill(Palette.error.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
            .strokeBorder(Palette.error.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
        .alert(Copy.resetSkyTitle.in(language), isPresented: $confirmingResetSky) {
            Button(Copy.resetSky.in(language), role: .destructive) { mirror.sendResetSky() }
            Button(Copy.cancel.in(language), role: .cancel) {}
                .keyboardShortcut(.defaultAction)
        } message: {
            Text(Copy.resetSkyMessage.in(language))
        }
    }
}

/// The link to the headset: state, device, how recent the last message
/// was, and the connect round trip from the acceptance log.
private struct HeadsetCard: View {
    @ObservedObject var session: CompanionSession

    @Environment(\.promptLanguage) private var language
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var kind: StatusBadge.Kind {
        session.isConnected ? .good : (session.wasConnected ? .waiting : .bad)
    }

    private var stateText: String {
        session.isConnected ? Copy.linked.in(language)
            : (session.wasConnected ? Copy.reconnecting.in(language) : Copy.lookingForHeadset.in(language))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: Copy.headset.in(language))
            HStack(spacing: 10) {
                if kind == .waiting {
                    ProgressView().controlSize(.small).tint(Palette.warning)
                } else {
                    Circle()
                        .fill(color)
                        .frame(width: 14, height: 14)
                        .shadow(color: color.opacity(0.8), radius: 6)
                }
                Text(stateText)
                    .font(TypeScale.cardTitle)
                    .foregroundStyle(kind == .good ? Palette.text : color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !session.isConnected && !session.wasConnected {
                Text(Copy.tapStartOnHeadset.in(language))
                    .font(TypeScale.status)
                    .foregroundStyle(Palette.muted)
            }
            VStack(spacing: 8) {
                if let host = session.channel.hostPeer {
                    InfoRow(label: Copy.device.in(language), value: host.id)
                }
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    InfoRow(label: Copy.lastMessage.in(language), value: lastMessage(at: context.date))
                }
                if let ms = mirror.lastConnectRoundTripMs {
                    InfoRow(label: Copy.connectRoundTrip.in(language), value: String(format: "%.0f ms", ms))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .chargeCard(accent: kind == .good ? nil : color)
        .animation(Motion.gentle(reduceMotion), value: kind)
    }

    private var mirror: SessionMirror { session.mirror }

    private var color: Color {
        switch kind {
        case .good: Palette.success
        case .waiting: Palette.warning
        case .bad, .inactive: Palette.error
        }
    }

    private func lastMessage(at now: Date) -> String {
        guard let last = session.channel.log.entries.last(where: { $0.direction == .received }) else {
            return Copy.noneYet.in(language)
        }
        let seconds = max(0, Int(now.timeIntervalSince1970 - last.localTimestamp))
        return Copy.secondsAgo.in(language, seconds)
    }
}

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(Palette.muted)
            Spacer(minLength: 12)
            Text(value)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(TypeScale.status)
        .accessibilityElement(children: .combine)
    }
}

private struct ReadinessRow: View {
    enum State { case yes, notYet, noSignal }

    let label: String
    let icon: String
    let state: State

    @Environment(\.promptLanguage) private var language

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(state == .yes ? Palette.success : Palette.muted)
                .frame(width: 34, height: 34)
                .background(Circle().fill((state == .yes ? Palette.success : Palette.muted).opacity(0.14)))
            Text(label)
                .font(TypeScale.body.weight(.medium))
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                Image(systemName: symbol)
                Text(text)
            }
            .font(TypeScale.status)
            .foregroundStyle(state == .yes ? Palette.success : Palette.muted)
        }
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch state {
        case .yes: "checkmark.circle.fill"
        case .notYet: "circle.dotted"
        case .noSignal: "antenna.radiowaves.left.and.right.slash"
        }
    }

    private var text: String {
        switch state {
        case .yes: Copy.yes.in(language)
        case .notYet: Copy.notYet.in(language)
        case .noSignal: Copy.noSignal.in(language)
        }
    }
}

/// A key name drawn as a keycap, beside the control it triggers.
struct KeyCap: View {
    let key: String
    var onGold = false

    init(_ key: String, onGold: Bool = false) {
        self.key = key
        self.onGold = onGold
    }

    var body: some View {
        Text(key)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5)
                .fill(onGold ? Palette.background.opacity(0.12) : Palette.background.opacity(0.5)))
            .overlay(RoundedRectangle(cornerRadius: 5)
                .strokeBorder(onGold ? Palette.background.opacity(0.35) : Palette.hairline, lineWidth: 1))
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityHidden(true)
    }
}

/// The ring buffer as a CSV file for ShareLink.
struct LogExport: Transferable {
    let csv: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { export in
            Data(export.csv.utf8)
        }
        .suggestedFileName("chargeup-log.csv")
    }
}
