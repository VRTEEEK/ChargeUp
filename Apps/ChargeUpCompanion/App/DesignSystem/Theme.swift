import SwiftUI
import ChargeUpCore

/// The companion's look: the midnight navy and lantern gold of the child's
/// world, kept calm enough for a clinic. Every colour on screen comes from here.
enum Palette {
    static let background = Color(hex: 0x141A2E)
    static let surface = Color(hex: 0x202942)
    static let elevated = Color(hex: 0x2A3552)
    static let gold = Color(hex: 0xD9A441)
    static let brightGold = Color(hex: 0xF5C76B)
    static let text = Color(hex: 0xF7F2E8)
    static let muted = Color(hex: 0xAAB5C8)
    static let success = Color(hex: 0x58C6A2)
    static let warning = Color(hex: 0xE9B85B)
    static let error = Color(hex: 0xE89A85)
    static let coolBlue = Color(hex: 0x6FA8DC)
    /// Card edges and dividers.
    static let hairline = Color.white.opacity(0.09)
    /// Brass shading for the lantern frame.
    static let brass = Color(hex: 0x9A6E2A)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// The type ramp. Built on `Font.companion`, so a Mac gets its larger
/// metre-away sizes and iPhone and iPad keep Dynamic Type.
enum TypeScale {
    static let appTitle = Font.companion(.largeTitle).weight(.bold)
    static let heading = Font.companion(.title).weight(.semibold)
    static let cardTitle = Font.companion(.title3).weight(.semibold)
    static let body = Font.companion(.callout)
    static let secondary = Font.companion(.subheadline)
    static let status = Font.companion(.footnote).weight(.medium)
    /// Small capitals over a card: CURRENT STAGE.
    static let eyebrow = Font.companion(.caption).weight(.bold)
}

enum Metrics {
    static let cardRadius: CGFloat = 20
    static let controlRadius: CGFloat = 14
    static let cardPadding: CGFloat = 20
    static let gap: CGFloat = 20
}

// MARK: - Language

private struct PromptLanguageKey: EnvironmentKey {
    static let defaultValue = PromptLanguage.en
}

extension EnvironmentValues {
    /// The language picked on the role screen, for chrome text and prompts.
    var promptLanguage: PromptLanguage {
        get { self[PromptLanguageKey.self] }
        set { self[PromptLanguageKey.self] = newValue }
    }
}

// MARK: - Motion

/// Animations that turn into instant changes under Reduce Motion.
enum Motion {
    static func gentle(_ reduceMotion: Bool, duration: Double = 0.35) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: duration)
    }
}

// MARK: - Background

/// The window behind everything: navy with a low amber horizon and a few
/// fixed stars. Drawn once; nothing here moves.
struct ChargeBackground: View {
    var body: some View {
        ZStack {
            Palette.background
            RadialGradient(colors: [Palette.gold.opacity(0.10), .clear],
                           center: .bottom, startRadius: 0, endRadius: 700)
            RadialGradient(colors: [Palette.coolBlue.opacity(0.08), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 600)
            Canvas { context, size in
                // A fixed pseudo-random field, the same on every launch.
                var seed: UInt64 = 0x5EED
                func next() -> Double {
                    seed = seed &* 6364136223846793005 &+ 1442695040888963407
                    return Double(seed >> 33) / Double(1 << 31)
                }
                for _ in 0..<70 {
                    let point = CGPoint(x: next() * size.width, y: next() * size.height * 0.75)
                    let radius = 0.4 + next() * 1.1
                    let alpha = 0.10 + next() * 0.25
                    context.fill(Path(ellipseIn: CGRect(x: point.x, y: point.y, width: radius * 2, height: radius * 2)),
                                 with: .color(Palette.text.opacity(alpha)))
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

// MARK: - Cards

/// A panel on the navy background. `accent` draws a coloured edge, used for
/// the card that matters most on the screen.
struct CardBackground: ViewModifier {
    var elevated = false
    var accent: Color?

    func body(content: Content) -> some View {
        content
            .padding(Metrics.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .fill(elevated ? Palette.elevated : Palette.surface)
                    .shadow(color: .black.opacity(0.25), radius: elevated ? 18 : 8, y: elevated ? 8 : 3))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .strokeBorder(accent?.opacity(0.75) ?? Palette.hairline, lineWidth: accent == nil ? 1 : 1.5))
    }
}

extension View {
    func chargeCard(elevated: Bool = false, accent: Color? = nil) -> some View {
        modifier(CardBackground(elevated: elevated, accent: accent))
    }
}

/// The small capitals label that heads a card.
struct Eyebrow: View {
    let text: String
    var color: Color = Palette.muted

    @Environment(\.promptLanguage) private var language

    var body: some View {
        Text(text.uppercased(with: Locale.current))
            .font(TypeScale.eyebrow)
            // Letter spacing would break Arabic's joined letters apart.
            .tracking(language.isRightToLeft ? 0 : 1.2)
            .foregroundStyle(color)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Buttons

/// The one gold action on a screen. Navy type on gold; disabled it drops to
/// a flat navy slab so it never looks pressable when it is not.
struct GoldButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 18
    /// A warm white ring around the button, for the needle moment.
    var ringed = false

    func makeBody(configuration: Configuration) -> some View {
        GoldButton(configuration: configuration, cornerRadius: cornerRadius, ringed: ringed)
    }

    private struct GoldButton: View {
        let configuration: ButtonStyleConfiguration
        let cornerRadius: CGFloat
        let ringed: Bool
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovering = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            configuration.label
                .foregroundStyle(isEnabled ? Palette.background : Palette.muted)
                .background {
                    if isEnabled {
                        shape.fill(LinearGradient(colors: [Palette.brightGold, Palette.gold],
                                                  startPoint: .top, endPoint: .bottom))
                            .brightness(hovering ? 0.05 : 0)
                            .shadow(color: Palette.gold.opacity(hovering ? 0.45 : 0.28), radius: hovering ? 22 : 14, y: 6)
                    } else {
                        shape.fill(Palette.elevated)
                    }
                }
                .overlay(shape.strokeBorder(isEnabled ? Color.white.opacity(0.25) : Palette.hairline, lineWidth: 1))
                .overlay {
                    if ringed && isEnabled {
                        shape.inset(by: -6).stroke(Palette.text.opacity(0.85), lineWidth: 2)
                    }
                }
                .contentShape(shape)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
                .animation(Motion.gentle(reduceMotion, duration: 0.18), value: hovering)
                .animation(Motion.gentle(reduceMotion, duration: 0.12), value: configuration.isPressed)
                .onHover { hovering = $0 }
        }
    }
}

/// Secondary actions: a quiet navy chip, tinted for its role. Destructive
/// ones take the error tint so they never look like the gold action.
struct QuietButtonStyle: ButtonStyle {
    var tint: Color = Palette.text
    /// Stretch to the width offered, for buttons laid out in a row.
    var fills = true

    func makeBody(configuration: Configuration) -> some View {
        QuietButton(configuration: configuration, tint: tint, fills: fills)
    }

    private struct QuietButton: View {
        let configuration: ButtonStyleConfiguration
        let tint: Color
        let fills: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
            configuration.label
                .font(TypeScale.status)
                .foregroundStyle(isEnabled ? tint : Palette.muted.opacity(0.6))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: fills ? .infinity : nil)
                .background(shape.fill(hovering && isEnabled ? Palette.elevated : Palette.elevated.opacity(0.6)))
                .overlay(shape.strokeBorder(isEnabled ? tint.opacity(0.35) : Palette.hairline, lineWidth: 1))
                .contentShape(shape)
                .opacity(configuration.isPressed ? 0.8 : 1)
                .onHover { hovering = $0 }
        }
    }
}

// MARK: - Status

/// A coloured dot with a word beside it. Colour is never the only signal.
struct StatusBadge: View {
    enum Kind { case good, waiting, bad, inactive }

    let kind: Kind
    let text: String
    var showsSpinner = false

    var color: Color {
        switch kind {
        case .good: Palette.success
        case .waiting: Palette.warning
        case .bad: Palette.error
        case .inactive: Palette.muted
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            if showsSpinner {
                ProgressView().controlSize(.small).tint(color)
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                    .shadow(color: color.opacity(kind == .inactive ? 0 : 0.7), radius: 4)
            }
            Text(text)
                .font(TypeScale.status)
                .foregroundStyle(Palette.text)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(color.opacity(0.14)))
        .overlay(Capsule().strokeBorder(color.opacity(0.45), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// The link to the headset as a badge, shared by every role's top bar.
struct ConnectionBadge: View {
    @ObservedObject var session: CompanionSession
    @Environment(\.promptLanguage) private var language
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if session.isConnected {
                StatusBadge(kind: .good, text: Copy.linked.in(language))
            } else if session.wasConnected {
                StatusBadge(kind: .waiting, text: Copy.reconnecting.in(language), showsSpinner: true)
            } else {
                StatusBadge(kind: .bad, text: Copy.lookingForHeadset.in(language))
            }
        }
        .animation(Motion.gentle(reduceMotion), value: session.isConnected)
    }
}
