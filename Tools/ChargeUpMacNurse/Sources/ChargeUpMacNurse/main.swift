import Foundation
import ChargeUpCore

// The Mac as the nurse. Same SessionMirror and PeerChannel the iPad uses;
// nothing here talks to the network directly. Keys: space = next,
// return = CONNECT (only on the countdown step), r = reset, q = quit.
// The message log goes to ~/Documents/chargeup-macnurse-<date>.csv on quit.

@MainActor
final class NurseConsole {
    let sequence: ChargeSequence
    let mirror: SessionMirror
    private var lastPresence: (head: Bool, still: Bool)?
    private var lastSkyCount = -1
    private var lastLinked = false
    private var stdinSource: DispatchSourceRead?
    private var originalTermios = termios()

    init() throws {
        sequence = try ChargeSequence.shipped()
        let host = Host.current().localizedName ?? "mac"
        mirror = SessionMirror(sequence: sequence, channel: PeerChannel(role: .nurse, displayName: "nurse-\(host)"))
        mirror.onStepChanged = { [weak self] id, step in self?.stepChanged(id, step) }
        mirror.channel.onPeerJoined = { [weak self] peer in
            guard peer.role == .vision else { return }
            self?.line("linked to headset \(peer.id)")
            self?.lastLinked = true
            self?.showPrompt()
        }
        mirror.channel.onPeerLeft = { [weak self] peer in
            guard peer.role == .vision else { return }
            self?.line("headset \(peer.id) left; browsing again, the session is held")
            self?.lastLinked = false
        }
    }

    func run() {
        enableRawInput()
        mirror.channel.start()
        line("browsing for a headset advertising _chargeup._tcp on this network (ctrl-c or q to quit)")
        // Presence at 10 Hz: print only when a flag changes.
        Task { @MainActor [weak self] in
            while let self {
                try? await Task.sleep(for: .milliseconds(200))
                if self.mirror.channel.isConnected, self.mirror.sessions.count != self.lastSkyCount {
                    self.lastSkyCount = self.mirror.sessions.count
                    self.line("sky  \(self.lastSkyCount) lanterns")
                }
                let now = (self.mirror.headOnPort, self.mirror.armStill)
                if self.lastPresence == nil || self.lastPresence! != now {
                    self.lastPresence = now
                    if self.mirror.channel.isConnected {
                        self.line("presence  head on port: \(now.0 ? "YES" : "no ")   arm still: \(now.1 ? "YES" : "no ")")
                    }
                }
            }
        }
        stdinSource = DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO, queue: .main)
        stdinSource?.setEventHandler { [weak self] in
            var byte: UInt8 = 0
            guard read(STDIN_FILENO, &byte, 1) == 1 else { return }
            Task { @MainActor in self?.key(byte) }
        }
        stdinSource?.resume()
        signal(SIGINT, SIG_IGN)
        let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        sigint.setEventHandler { Task { @MainActor in NurseConsole.shared?.quit() } }
        sigint.resume()
        _ = Unmanaged.passRetained(sigint)
    }

    nonisolated(unsafe) static var shared: NurseConsole?

    private func key(_ byte: UInt8) {
        switch byte {
        case 0x20: // space
            guard mirror.channel.isConnected else { return line("not linked yet") }
            if mirror.currentStepId == StepID.countdown {
                return line("this is the countdown step: press return to CONNECT")
            }
            guard mirror.isButtonEnabled else { return line("button disabled on this step (\(mirror.currentStepId))") }
            line("tap  \(mirror.buttonLabel)")
            mirror.tapButton()
        case 0x0A, 0x0D: // return
            guard mirror.channel.isConnected else { return line("not linked yet") }
            guard mirror.currentStepId == StepID.countdown else {
                return line("CONNECT only works on the countdown step (now: \(mirror.currentStepId))")
            }
            line("tap  CONNECT")
            mirror.tapButton()
        case UInt8(ascii: "r"), UInt8(ascii: "R"):
            guard mirror.channel.isConnected else { return line("not linked yet") }
            line("reset")
            mirror.sendReset()
        case UInt8(ascii: "k"), UInt8(ascii: "K"):
            guard mirror.channel.isConnected else { return line("not linked yet") }
            line("reset sky (back to the seeded lanterns)")
            mirror.sendResetSky()
        case UInt8(ascii: "q"), UInt8(ascii: "Q"), 0x03:
            quit()
        default:
            break
        }
    }

    private func stepChanged(_ id: String, _ step: Step?) {
        if let step, let index = sequence.index(of: step.id) {
            line("step \(index + 1)/\(sequence.steps.count)  \(step.name)")
        } else {
            line("step \(id)")
        }
        if id == StepID.connect, let ms = mirror.lastConnectRoundTripMs {
            line(String(format: "connect round trip %.1f ms (CONNECT sent to stepChanged received)", ms))
        }
        showPrompt()
    }

    private func showPrompt() {
        let label = mirror.buttonLabel
        if mirror.currentStepId == StepID.countdown {
            line("  [return] \(label)   [r] reset   [k] reset sky   [q] quit")
        } else {
            line("  [space] \(label)   [r] reset   [k] reset sky   [q] quit")
        }
    }

    private func quit() {
        let csv = mirror.channel.log.csv()
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory())
        let url = dir.appendingPathComponent("chargeup-macnurse-\(f.string(from: Date())).csv")
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            line("log written: \(url.path) (\(mirror.channel.log.count) entries)")
        } catch {
            line("log write failed: \(error.localizedDescription)")
        }
        mirror.channel.stop()
        restoreInput()
        exit(0)
    }

    private func line(_ text: String) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        print("\(f.string(from: Date()))  \(text)\r")
        fflush(stdout)
    }

    private func enableRawInput() {
        guard isatty(STDIN_FILENO) == 1 else { return }
        tcgetattr(STDIN_FILENO, &originalTermios)
        var raw = originalTermios
        raw.c_lflag &= ~tcflag_t(ECHO | ICANON)
        raw.c_cc.16 = 1   // VMIN
        raw.c_cc.17 = 0   // VTIME
        tcsetattr(STDIN_FILENO, TCSANOW, &raw)
    }

    private func restoreInput() {
        guard isatty(STDIN_FILENO) == 1 else { return }
        tcsetattr(STDIN_FILENO, TCSANOW, &originalTermios)
    }
}

do {
    let console = try NurseConsole()
    NurseConsole.shared = console
    console.run()
} catch {
    FileHandle.standardError.write(Data("sequence.json failed to load: \(error)\n".utf8))
    exit(1)
}
RunLoop.main.run()
