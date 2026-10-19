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
    @Published private(set) var audioStatus = "not loaded"
    /// Last per-session CSV written to Documents, for the operator window.
    @Published private(set) var lastRecording = "none yet"
    private var recorder = SessionRecorder()
    /// The lantern sky on this headset. Seeded on first launch from config.sky.
    private var store: SessionStore?
    @Published private(set) var skySessions: [SessionRecord] = []
    @Published private(set) var skyStatus = "not loaded"
    var onSkyChanged: (([SessionRecord]) -> Void)?
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
        switch sequence.config.accessSite {
        case .arm:
            if forearm.simulatedForearm && !HandTrackingProvider.isSupported {
                portSource = SimulatedForearm(config: forearm.simulatedPath)
                isSimulatedForearm = true
            } else {
                portSource = ForearmAnchor(config: forearm)
                isSimulatedForearm = false
            }
        case .chestPort:
            // Compile-only path; never the default. Same simulated fallback.
            if forearm.simulatedForearm && !ImageTrackingProvider.isSupported {
                portSource = SimulatedForearm(config: forearm.simulatedPath)
                isSimulatedForearm = true
            } else {
                portSource = MarkerPortPoseSource(config: sequence.config.chestPort, smoothing: forearm)
                isSimulatedForearm = false
            }
        }
        loadSky()
        host.onTick = { [weak self] state, now in self?.recordTick(state, at: now) }
        host.onPhaseChanged = { [weak self] state in self?.phaseChanged(state) }
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
        finishRecording()
    }

    // MARK: Lantern sky

    private func loadSky() {
        guard let dir = documentsDirectory else { return }
        do {
            var s = try SessionStore(directory: dir)
            if s.count == 0, sequence.config.sky.seededSessions > 0 {
                try s.seed(count: sequence.config.sky.seededSessions, variant: sequence.object)
            }
            store = s
            publishSky()
        } catch {
            skyStatus = "sessions.json failed: \(error.localizedDescription)"
        }
    }

    private func publishSky() {
        guard let store else { return }
        skySessions = store.sorted
        skyStatus = "\(store.count) lanterns"
        host.updateSky(skySessions)
        onSkyChanged?(skySessions)
    }

    /// Needle out: this session's lantern joins the sky and the record is written.
    func sessionReleased() {
        guard var s = store else { return }
        do {
            try s.append(SessionRecord(date: Date(), variant: sequence.object, fill: state.charge))
            store = s
            publishSky()
        } catch {
            skyStatus = "write failed: \(error.localizedDescription)"
        }
    }

    /// Operator only. Clears sessions.json and re-seeds from config.
    func resetSky() {
        guard var s = store else { return }
        do {
            try s.reset(seeding: sequence.config.sky.seededSessions, variant: sequence.object)
            store = s
            publishSky()
        } catch {
            skyStatus = "reset failed: \(error.localizedDescription)"
        }
    }

    // MARK: Recording (Milestone 3 task 3)

    private var documentsDirectory: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    private func recordTick(_ state: SessionState, at now: TimeInterval) {
        guard state.phase != .idle else { return }
        recorder.record(stepId: host.currentStepId, hostTimestamp: now,
                        armStill: state.armStill, headOnPort: state.headOnPort, charge: state.charge)
    }

    /// A session is one run from the first step to complete (or a reset).
    private func phaseChanged(_ state: SessionState) {
        switch state.phase {
        case .step(0):
            if !recorder.isRecording { recorder.begin(at: host.clock()) }
        case .complete, .idle:
            finishRecording()
        default:
            break
        }
    }

    private func finishRecording() {
        guard recorder.isRecording, let dir = documentsDirectory else { return }
        do {
            if let url = try recorder.finish(into: dir) {
                lastRecording = url.lastPathComponent
            }
        } catch {
            lastRecording = "write failed: \(error.localizedDescription)"
        }
    }

    func reset() { host.reset() }

    func noteAudio(_ status: String) { audioStatus = status }

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
