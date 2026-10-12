import Foundation
import Combine
import ARKit
import ChargeUpCore

/// The headset's side of the session: owns the SessionHost (reducer, clock,
/// channel) and the port pose source, and exposes what the operator window
/// and the scene need.
@MainActor
final class SessionController: ObservableObject {
    let sequence: ChargeSequence
    let host: SessionHost
    /// Real forearm anchor on a headset; the simulated path where hand
    /// tracking is unsupported and the config flag allows it.
    let portSource: any PortPoseSource
    let isSimulatedForearm: Bool
    let headPose = HeadPose()
    private let debugControl: DebugFileControl

    @Published private(set) var isRunning = false
    /// Mirrors `portSource.statusText`; updated from the frame loop only when it changes.
    @Published private(set) var forearmStatus = "idle"
    /// "head pose" once the lantern was placed from world tracking, "fallback" otherwise.
    @Published private(set) var lanternPlacement = "not placed"
    private var bag = Set<AnyCancellable>()

    init() {
        do {
            sequence = try ChargeSequence.shipped()
        } catch {
            fatalError("sequence.json failed to load: \(error)")
        }
        host = SessionHost(sequence: sequence)
        debugControl = DebugFileControl(host: host)
        let forearm = sequence.config.forearm
        if forearm.simulatedForearm && !HandTrackingProvider.isSupported {
            portSource = SimulatedForearm(config: forearm.simulatedPath)
            isSimulatedForearm = true
        } else {
            portSource = ForearmAnchor(config: forearm)
            isSimulatedForearm = false
        }
        host.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        host.channel.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
    }

    var currentStepId: String { host.currentStepId }
    var currentStep: Step? { host.currentStep }
    var state: SessionState { host.state }
    var peers: [PeerInfo] { host.channel.peers }

    /// Operator pressed Start: advertise and tick. The nurse's START begins the sequence.
    func start() {
        guard !isRunning else { return }
        isRunning = true
        host.start()
        debugControl.start()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        debugControl.stop()
        host.stop()
    }

    func reset() { host.reset() }

    func noteLanternPlacement(fromHeadPose: Bool, head: SIMD3<Float>?, lantern: SIMD3<Float>) {
        let h = head.map { String(format: "head (%.2f, %.2f, %.2f) ", $0.x, $0.y, $0.z) } ?? ""
        lanternPlacement = (fromHeadPose ? "head pose " : "fallback ") + h + String(format: "lantern (%.2f, %.2f, %.2f)", lantern.x, lantern.y, lantern.z)
    }

    /// Called every rendered frame by the scene.
    func frame(now: TimeInterval) -> PortPose? {
        let pose = portSource.pose(now: now)
        let status = portSource.statusText
        if status != forearmStatus { forearmStatus = status }
        // The simulated forearm stands in for a still arm and a head on the port.
        if portSource.reportsPresence, pose != nil, !(host.state.armStill && host.state.headOnPort) {
            host.updatePresence(armStill: true, headOnPort: true)
        }
        return pose
    }
}
