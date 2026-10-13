import Foundation

/// Rehearsal mode: presses the nurse's button on a timer so one person can
/// run the headset scene alone. Goes through the whole sequence, waits one
/// interval at complete, resets, and starts again until switched off.
/// Auto steps are skipped because the button is disabled on them.
@MainActor
public final class RehearsalDriver: ObservableObject {
    public let mirror: SessionMirror
    public let interval: TimeInterval
    @Published public private(set) var isOn = false
    /// Button presses made by the driver, for the UI and tests.
    @Published public private(set) var taps = 0

    private var task: Task<Void, Never>?

    public init(mirror: SessionMirror, interval: TimeInterval) {
        self.mirror = mirror
        self.interval = interval
    }

    public func set(_ on: Bool) {
        guard on != isOn else { return }
        isOn = on
        task?.cancel()
        task = nil
        guard on else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.interval ?? 1))
                guard let self, !Task.isCancelled else { return }
                self.tick()
            }
        }
    }

    private func tick() {
        guard mirror.isButtonEnabled else { return }
        mirror.tapButton()
        taps += 1
    }
}
