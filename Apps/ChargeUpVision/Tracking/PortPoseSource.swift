import Foundation
import QuartzCore
import ChargeUpCore

/// Whatever puts the port on the arm. The real anchor and the simulated
/// path both satisfy this; the scene never knows which it has.
@MainActor
protocol PortPoseSource: AnyObject {
    /// Short status for the operator window: "tracked", "simulated", ...
    var statusText: String { get }
    /// True while the source itself stands in for the child's cooperation.
    var reportsPresence: Bool { get }
    func start() async
    func stop()
    func pose(now: TimeInterval) -> PortPose?
    /// World positions of the hands' fingertips and knuckles, for touching
    /// things in the scene. Empty where there are no tracked hands.
    func touchPoints(now: TimeInterval) -> [SIMD3<Float>]
    /// Each tracked hand's centre (its middle knuckle) in world space, keyed
    /// 0 left and 1 right, for recognising a wave. Empty without hands.
    func handCentres(now: TimeInterval) -> [Int: SIMD3<Float>]
}

extension PortPoseSource {
    func touchPoints(now: TimeInterval) -> [SIMD3<Float>] { [] }
    func handCentres(now: TimeInterval) -> [Int: SIMD3<Float>] { [:] }
}

extension ForearmAnchor: PortPoseSource {
    var statusText: String { status.rawValue + (lastError.isEmpty ? "" : " " + lastError) }
    var reportsPresence: Bool { false }
}

/// Fixed path in front of the user for the simulator and desk tests. Only
/// chosen when hand tracking is unsupported and `config.forearm.simulatedForearm`
/// is true. Reports the child as still and looking at the port.
@MainActor
final class SimulatedForearm: PortPoseSource {
    private let config: SimulatedPathConfig
    private var startedAt: TimeInterval?

    init(config: SimulatedPathConfig) {
        self.config = config
    }

    var statusText: String { startedAt == nil ? "simulated, idle" : "simulated" }
    var reportsPresence: Bool { true }

    func start() async {
        startedAt = CACurrentMediaTime()
    }

    func stop() {
        startedAt = nil
    }

    func pose(now: TimeInterval = CACurrentMediaTime()) -> PortPose? {
        guard let startedAt else { return nil }
        return SimulatedForearmPath.pose(at: now - startedAt, config: config)
    }
}
