import SwiftUI
import ChargeUpCore

@main
struct ChargeUpCompanionApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor private var appDelegate: MacAppDelegate
    #endif

    var body: some Scene {
        #if os(macOS)
        // One window, one channel: a second window would join the headset
        // as a second nurse. Resizable down to MacWindow.minSize.
        Window(MacWindow.title(for: nil), id: "nurse") {
            RootView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(MacWindow.size)
        #else
        WindowGroup {
            RootView()
        }
        #endif
    }
}

#if os(macOS)
/// The Mac nurse is a single-window app: closing the window quits it.
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// The Mac window: opens at a size readable from about a metre, titled by role.
enum MacWindow {
    static let size = CGSize(width: 1180, height: 800)
    /// The smallest window that keeps the big button and the link status in view.
    static let minSize = CGSize(width: 760, height: 620)

    static func title(for role: Role?) -> String {
        role == .parent ? "Charge Up — Parent" : "Charge Up — Nurse"
    }
}
#endif

/// The roles this device can take. A Mac has no haptic engine to ramp, so
/// it offers only Nurse and Parent.
enum CompanionRoles {
    static var offered: [Role] {
        #if os(macOS)
        [.nurse, .parent]
        #else
        [.nurse, .parent, .haptic]
        #endif
    }
}

/// Persisted choice of prompt language. Arabic lays the whole companion
/// out right to left at the same type sizes.
struct LanguageSetting {
    static let key = "chargeup.language"

    static func read() -> PromptLanguage {
        PromptLanguage(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .en
    }
}

/// Role picker on launch, then the role's view. Picking a role opens the
/// channel; leaving it closes the channel.
struct RootView: View {
    @State private var session: CompanionSession?
    @AppStorage(LanguageSetting.key) private var languageRaw: String = PromptLanguage.en.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var language: PromptLanguage { PromptLanguage(rawValue: languageRaw) ?? .en }

    var body: some View {
        ZStack {
            ChargeBackground()
            if let session {
                RoleView(session: session) {
                    session.stop()
                    self.session = nil
                }
                .transition(.opacity)
            } else {
                RolePicker(languageRaw: $languageRaw, pick: open)
                    .transition(.opacity)
            }
        }
        .animation(Motion.gentle(reduceMotion, duration: 0.4), value: session == nil)
        .foregroundStyle(Palette.text)
        .tint(Palette.gold)
        .preferredColorScheme(.dark)
        .environment(\.promptLanguage, language)
        .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight)
        .environment(\.locale, Locale(identifier: language.localeIdentifier))
        #if os(macOS)
        .frame(minWidth: MacWindow.minSize.width, idealWidth: MacWindow.size.width, maxWidth: .infinity,
               minHeight: MacWindow.minSize.height, idealHeight: MacWindow.size.height, maxHeight: .infinity)
        .navigationTitle(MacWindow.title(for: session?.role))
        #endif
        #if DEBUG
        .onAppear(perform: openLaunchRole)
        #endif
    }

    private func open(_ role: Role) {
        let s = CompanionSession(role: role)
        s.start()
        session = s
    }

    #if DEBUG
    /// Debug builds only: CHARGEUP_ROLE=nurse or parent opens that role at
    /// launch, for screenshots and rehearsals without clicking.
    private func openLaunchRole() {
        guard session == nil,
              let raw = ProcessInfo.processInfo.environment["CHARGEUP_ROLE"],
              let role = Role(rawValue: raw),
              CompanionRoles.offered.contains(role) else { return }
        open(role)
    }
    #endif
}

struct RolePicker: View {
    @Binding var languageRaw: String
    let pick: (Role) -> Void

    @Environment(\.promptLanguage) private var language

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    LanguageSelector(languageRaw: $languageRaw)
                }
                .padding(.horizontal, 28)
                .padding(.top, 12)

                Spacer(minLength: 8)
                VStack(spacing: 18) {
                    // The key art gives way first when the window is short.
                    hero
                        .frame(height: min(max(geo.size.height - 600, 110), 270))

                    VStack(spacing: 8) {
                        Text("Charge Up")
                            .font(TypeScale.appTitle)
                            .foregroundStyle(LinearGradient(colors: [Palette.brightGold, Palette.gold],
                                                            startPoint: .top, endPoint: .bottom))
                        Text(Copy.tagline.in(language))
                            .font(TypeScale.body)
                            .foregroundStyle(Palette.muted)
                        GoldDivider()
                            .padding(.top, 6)
                    }

                    Text(Copy.whoIsThisDevice.in(language))
                        .font(TypeScale.cardTitle)
                        .padding(.top, 4)

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: Metrics.gap) { cards }
                            .fixedSize(horizontal: false, vertical: true)
                        VStack(spacing: 14) { cards }
                    }
                    .frame(maxWidth: 820)
                }
                .padding(.horizontal, 32)
                Spacer(minLength: 20)
            }
        }
    }

    @ViewBuilder
    private var cards: some View {
        ForEach(CompanionRoles.offered, id: \.self) { role in
            switch role {
            case .nurse:
                RoleCard(icon: "stethoscope", title: Copy.nurse.in(language),
                         detail: Copy.nurseDetail.in(language), action: Copy.nurseAction.in(language),
                         accent: Palette.gold) { pick(.nurse) }
            case .parent:
                RoleCard(icon: "figure.and.child.holdinghands", title: Copy.parent.in(language),
                         detail: Copy.parentDetail.in(language), action: Copy.parentAction.in(language),
                         accent: Palette.coolBlue) { pick(.parent) }
            case .haptic:
                RoleCard(icon: "iphone.radiowaves.left.and.right", title: Copy.haptic.in(language),
                         detail: Copy.hapticDetail.in(language), action: Copy.hapticAction.in(language),
                         accent: Palette.success) { pick(.haptic) }
            case .vision:
                EmptyView()
            }
        }
    }

    /// The key art from the headset's start screen, the logo at its heart.
    private var hero: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        return Color.clear
            .aspectRatio(16 / 7, contentMode: .fit)
            .overlay(Image("KeyArt").resizable().aspectRatio(contentMode: .fill))
            .clipShape(shape)
            .overlay(shape.strokeBorder(Palette.gold.opacity(0.45), lineWidth: 1))
            .shadow(color: Palette.gold.opacity(0.18), radius: 30, y: 10)
            .accessibilityElement()
            .accessibilityLabel("Charge Up")
    }
}

/// A thin gold rule with a star at its centre.
struct GoldDivider: View {
    var body: some View {
        HStack(spacing: 10) {
            line(fadingTo: .leading)
            Sparkle()
                .fill(Palette.brightGold)
                .frame(width: 12, height: 12)
            line(fadingTo: .trailing)
        }
        .frame(width: 220)
        .accessibilityHidden(true)
    }

    private func line(fadingTo edge: UnitPoint) -> some View {
        Rectangle()
            .fill(LinearGradient(colors: [Palette.gold.opacity(0.8), Palette.gold.opacity(0)],
                                 startPoint: edge == .leading ? .trailing : .leading, endPoint: edge))
            .frame(height: 1)
    }
}

/// One role on the picker: icon, name, what it is for, and how to enter.
struct RoleCard: View {
    let icon: String
    let title: String
    let detail: String
    let action: String
    let accent: Color
    let pick: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        Button(action: pick) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(accent)
                    .frame(width: 58, height: 58)
                    .background(Circle().fill(accent.opacity(0.14)))
                    .overlay(Circle().strokeBorder(accent.opacity(0.4), lineWidth: 1))
                Text(title)
                    .font(TypeScale.heading)
                    .foregroundStyle(Palette.text)
                Text(detail)
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                HStack(spacing: 8) {
                    Text(action)
                    Image(systemName: "arrow.forward")
                }
                .font(TypeScale.status.weight(.semibold))
                .foregroundStyle(accent)
            }
            .padding(24)
            .frame(maxWidth: 400, minHeight: 230, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .fill(hovering ? Palette.elevated : Palette.surface)
                    .shadow(color: hovering ? accent.opacity(0.25) : .black.opacity(0.25),
                            radius: hovering ? 24 : 10, y: hovering ? 10 : 4))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .strokeBorder(accent.opacity(hovering ? 0.9 : 0.35), lineWidth: hovering ? 1.5 : 1))
            .offset(y: hovering && !reduceMotion ? -3 : 0)
            .contentShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.gentle(reduceMotion, duration: 0.2), value: hovering)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(detail)")
        .accessibilityHint(action)
    }
}

/// English or Arabic for prompts and interface text. Arabic lays the
/// companion out right to left.
struct LanguageSelector: View {
    @Binding var languageRaw: String
    @Environment(\.promptLanguage) private var language

    var body: some View {
        HStack(spacing: 2) {
            ForEach(PromptLanguage.allCases, id: \.self) { option in
                let selected = option == language
                Button {
                    languageRaw = option.rawValue
                } label: {
                    Text(option == .en ? "English" : "العربية")
                        .font(TypeScale.status.weight(.semibold))
                        .foregroundStyle(selected ? Palette.background : Palette.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(selected ? Palette.gold : Color.clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Palette.surface))
        .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Copy.language.in(language))
    }
}

struct RoleView: View {
    @ObservedObject var session: CompanionSession
    let leave: () -> Void

    @Environment(\.promptLanguage) private var language

    var body: some View {
        Group {
            switch session.role {
            case .nurse: NurseView(session: session)
            case .parent: ParentView(session: session)
            case .haptic: HapticView(session: session)
            case .vision: Text("This app never runs as vision.")
            }
        }
        .modifier(KeepAwake())
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 14) {
                Button(action: leave) {
                    Label(Copy.changeRole.in(language), systemImage: "chevron.backward")
                }
                .buttonStyle(QuietButtonStyle(tint: Palette.muted, fills: false))
                Spacer()
                ConnectionBadge(session: session)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
    }
}

/// While a role is open the screen stays on. On a Mac this also keeps App
/// Nap from throttling the link to the headset when the window is covered.
struct KeepAwake: ViewModifier {
    #if os(macOS)
    @State private var activity: NSObjectProtocol?
    #endif

    func body(content: Content) -> some View {
        content
            .onAppear {
                #if os(macOS)
                activity = ProcessInfo.processInfo.beginActivity(
                    options: [.idleDisplaySleepDisabled, .userInitiated],
                    reason: "Charge Up session in progress")
                #else
                UIApplication.shared.isIdleTimerDisabled = true
                #endif
            }
            .onDisappear {
                #if os(macOS)
                if let activity { ProcessInfo.processInfo.endActivity(activity) }
                activity = nil
                #else
                UIApplication.shared.isIdleTimerDisabled = false
                #endif
            }
    }
}
