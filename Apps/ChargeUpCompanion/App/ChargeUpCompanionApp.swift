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
        // as a second nurse. Fixed size, sized by RootView.
        Window(MacWindow.title(for: nil), id: "nurse") {
            RootView()
        }
        .windowResizability(.contentSize)
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

/// The Mac window: a fixed size readable from about a metre, titled by role.
enum MacWindow {
    static let size = CGSize(width: 1180, height: 800)

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

    private var language: PromptLanguage { PromptLanguage(rawValue: languageRaw) ?? .en }

    var body: some View {
        Group {
            if let session {
                RoleView(session: session, language: language) {
                    session.stop()
                    self.session = nil
                }
            } else {
                RolePicker(languageRaw: $languageRaw) { role in
                    let s = CompanionSession(role: role)
                    s.start()
                    session = s
                }
            }
        }
        .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight)
        .environment(\.locale, Locale(identifier: language.localeIdentifier))
        #if os(macOS)
        .frame(width: MacWindow.size.width, height: MacWindow.size.height)
        .navigationTitle(MacWindow.title(for: session?.role))
        #endif
    }
}

struct RolePicker: View {
    @Binding var languageRaw: String
    let pick: (Role) -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text("Charge Up")
                .font(.companion(.largeTitle).bold())
            Text("Who is this device?")
                .font(.companion(.title2))
                .foregroundStyle(.secondary)
            Picker("Language", selection: $languageRaw) {
                Text("English").tag(PromptLanguage.en.rawValue)
                Text("العربية").tag(PromptLanguage.ar.rawValue)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)
            ForEach(CompanionRoles.offered, id: \.self) { role in
                Button {
                    pick(role)
                } label: {
                    Text(role.rawValue.capitalized)
                        .font(.companion(.title).bold())
                        .frame(maxWidth: 420, minHeight: 88)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}

struct RoleView: View {
    @ObservedObject var session: CompanionSession
    let language: PromptLanguage
    let leave: () -> Void

    var body: some View {
        Group {
            switch session.role {
            case .nurse: NurseView(session: session)
            case .parent: ParentView(session: session, language: language)
            case .haptic: HapticView(session: session)
            case .vision: Text("This app never runs as vision.")
            }
        }
        .modifier(KeepAwake())
        .safeAreaInset(edge: .top) {
            HStack {
                Button("Change role", action: leave)
                    .font(.companion(.footnote))
                Spacer()
                ConnectionBadge(session: session)
            }
            .padding(.horizontal)
            .padding(.top, 4)
        }
    }
}

struct ConnectionBadge: View {
    @ObservedObject var session: CompanionSession

    var body: some View {
        HStack(spacing: 6) {
            if session.isConnected {
                Circle().fill(Color.green).frame(width: 12, height: 12)
                Text("Linked to headset")
            } else if session.wasConnected {
                ProgressView().controlSize(.mini)
                Text("Reconnecting to headset, step held")
            } else {
                Circle().fill(Color.red).frame(width: 12, height: 12)
                Text("Looking for headset")
            }
        }
        .font(.companion(.footnote))
        .foregroundStyle(.secondary)
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
