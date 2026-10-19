import SwiftUI
import ChargeUpCore

@main
struct ChargeUpCompanionApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
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
    }
}

struct RolePicker: View {
    @Binding var languageRaw: String
    let pick: (Role) -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text("Charge Up")
                .font(.largeTitle.bold())
            Text("Who is this device?")
                .font(.title2)
                .foregroundStyle(.secondary)
            Picker("Language", selection: $languageRaw) {
                Text("English").tag(PromptLanguage.en.rawValue)
                Text("العربية").tag(PromptLanguage.ar.rawValue)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)
            ForEach([Role.nurse, .parent, .haptic], id: \.self) { role in
                Button {
                    pick(role)
                } label: {
                    Text(role.rawValue.capitalized)
                        .font(.title.bold())
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
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .safeAreaInset(edge: .top) {
            HStack {
                Button("Change role", action: leave)
                    .font(.footnote)
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
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}
