import Foundation
import ARKit
import QuartzCore

/// One-shot device pose for placing the lantern at session start. Not the
/// attention proxy (Milestone 2 task 4); that is a separate, untouched task.
@MainActor
final class HeadPose {
    /// Fresh on every start: a stopped provider cannot be run again.
    private var session = ARKitSession()
    private var provider = WorldTrackingProvider()
    private var running = false

    var isSupported: Bool { WorldTrackingProvider.isSupported }

    func start() async {
        guard !running, isSupported else { return }
        session = ARKitSession()
        provider = WorldTrackingProvider()
        do {
            try await session.run([provider])
            running = true
        } catch {
            running = false
        }
    }

    func stop() {
        guard running else { return }
        session.stop()
        running = false
    }

    /// Origin-from-device transform, or nil until world tracking has one.
    func current() -> simd_float4x4? {
        guard running, provider.state == .running,
              let anchor = provider.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()),
              anchor.isTracked else { return nil }
        let m = anchor.originFromAnchorTransform
        // Right after `run` the simulator hands back an identity pose at the
        // floor origin; that is not a head position.
        let p = SIMD3<Float>(m.columns.3.x, m.columns.3.y, m.columns.3.z)
        guard simd_length(p) > 0.05 else { return nil }
        return m
    }

    /// Wait up to `timeout` for the first pose. Nil means use the fallback.
    func first(timeout: TimeInterval) async -> simd_float4x4? {
        let deadline = CACurrentMediaTime() + timeout
        while CACurrentMediaTime() < deadline {
            if let m = current() { return m }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return current()
    }
}
