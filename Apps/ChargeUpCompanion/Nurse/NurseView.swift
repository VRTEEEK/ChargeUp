import SwiftUI
import ChargeUpCore

/// The nurse's whole interface: the step list, one big button, two presence
/// indicators, and a log export for the acceptance run.
struct NurseView: View {
    @ObservedObject var session: CompanionSession

    private var mirror: SessionMirror { session.mirror }

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > 700
            if wide {
                HStack(spacing: 24) {
                    stepList.frame(maxWidth: .infinity)
                    controls.frame(width: 360)
                }
                .padding()
            } else {
                VStack(spacing: 16) {
                    stepList
                    controls
                }
                .padding()
            }
        }
    }

    private var stepList: some View {
        StepListView(sequence: session.sequence, currentStepId: mirror.currentStepId, showCues: true)
    }

    private var controls: some View {
        VStack(spacing: 20) {
            PresenceIndicators(headOnPort: mirror.headOnPort, armStill: mirror.armStill, charge: mirror.charge)

            Button {
                mirror.tapButton()
            } label: {
                Text(mirror.buttonLabel)
                    .font(.system(size: 40, weight: .heavy))
                    .frame(maxWidth: .infinity, minHeight: 140)
            }
            .buttonStyle(.borderedProminent)
            .tint(mirror.currentStepId == StepID.countdown ? .orange : .accentColor)
            .disabled(!mirror.isButtonEnabled)

            if let ms = mirror.lastConnectRoundTripMs {
                Text(String(format: "Connect round trip %.0f ms", ms))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Toggle(isOn: Binding(get: { session.rehearsal.isOn }, set: { session.rehearsal.set($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rehearsal").font(.headline)
                    Text(String(format: "Taps every %.0f s so one person can test the headset alone.",
                                session.sequence.config.rehearsalInterval))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.orange)
            .padding(.horizontal, 4)

            HStack {
                ShareLink(item: LogExport(csv: session.channel.log.csv()),
                          preview: SharePreview("Charge Up log")) {
                    Label("Export log", systemImage: "square.and.arrow.up")
                }
                Spacer()
                Button("Reset", role: .destructive) { mirror.sendReset() }
                    .disabled(!session.isConnected)
            }
            .font(.footnote)
        }
    }
}

/// Seven rows, the current one highlighted. Shared with the Parent role.
struct StepListView: View {
    let sequence: ChargeSequence
    let currentStepId: String
    var showCues: Bool

    var body: some View {
        VStack(spacing: 8) {
            ForEach(sequence.steps) { step in
                let current = step.id == currentStepId
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(sequence.index(of: step.id).map { $0 + 1 } ?? 0)")
                        .font(.title3.monospacedDigit().bold())
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.name)
                            .font(current ? .title2.bold() : .title3)
                        if showCues {
                            Text(step.clinicalCue)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(current ? Color.accentColor.opacity(0.22) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(current ? Color.accentColor : Color.clear, lineWidth: 2))
            }
            Spacer(minLength: 0)
        }
    }
}

struct PresenceIndicators: View {
    let headOnPort: Bool
    let armStill: Bool
    let charge: Double

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 24) {
                Indicator(label: "Head on port", on: headOnPort)
                Indicator(label: "Arm still", on: armStill)
            }
            ProgressView(value: charge)
                .tint(.yellow)
                .accessibilityLabel("Charge")
        }
    }

    private struct Indicator: View {
        let label: String
        let on: Bool
        var body: some View {
            HStack(spacing: 8) {
                Circle()
                    .fill(on ? Color.green : Color.gray.opacity(0.4))
                    .frame(width: 22, height: 22)
                Text(label).font(.headline)
            }
            .frame(maxWidth: .infinity)
        }
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
