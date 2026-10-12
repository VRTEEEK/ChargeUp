import Foundation
import ChargeUpCore

/// Debug only, default off. With `CHARGEUP_DEBUG_FILE_CONTROL=1` in the
/// environment, the operator side polls `Documents/control.txt` and applies
/// one command per file: `start`, `tap`, `connect`, `next` (tap or connect,
/// whichever the current step takes), `reset`. The file is deleted after
/// use. This exists so the simulator, which cannot reach a companion over
/// Multipeer from this Mac, can be stepped through the sequence from a
/// script. Nothing here touches the child's view.
@MainActor
final class DebugFileControl {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["CHARGEUP_DEBUG_FILE_CONTROL"] == "1"
    }

    private let host: SessionHost
    private var task: Task<Void, Never>?
    private static let pollInterval: Duration = .milliseconds(250)

    private var fileURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("control.txt")
    }

    init(host: SessionHost) {
        self.host = host
    }

    func start() {
        guard Self.isEnabled, task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: DebugFileControl.pollInterval)
                self?.poll()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func poll() {
        guard let url = fileURL, let raw = try? String(contentsOf: url, encoding: .utf8) else { return }
        try? FileManager.default.removeItem(at: url)
        let command = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = host.clock()
        switch command {
        case "start":
            host.begin()
        case "tap":
            host.apply(.nurseTap(at: now))
        case "connect":
            host.apply(.connect(nurseTimestamp: now, at: now))
        case "next":
            if host.state.phase == .idle {
                host.begin()
            } else if host.currentStepId == StepID.countdown {
                host.apply(.connect(nurseTimestamp: now, at: now))
            } else {
                host.apply(.nurseTap(at: now))
            }
        case "reset":
            host.reset()
        default:
            break
        }
    }
}
