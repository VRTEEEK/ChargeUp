import Foundation
import ARKit
import QuartzCore
import ChargeUpCore

/// Subscribes to ARKit hand tracking and keeps a smoothed port pose on the
/// held forearm. The maths and the hold-and-fade behaviour live in
/// ChargeUpCore (`ForearmPoseSolver`, `ForearmTracker`); this class is the
/// only thing that touches ARKit. Targeted API: visionOS 2.0
/// (`HandTrackingProvider`, `HandAnchor`, `HandSkeleton.JointName.forearmWrist`
/// and `.forearmArm`, which exist since visionOS 1.0).
@MainActor
final class ForearmAnchor: ObservableObject {
    enum Status: String {
        case idle, unsupported, unauthorized, failed
        case searching, tracked, holding, faded
    }

    /// For the operator window only. Changes rarely.
    @Published private(set) var status: Status = .idle
    @Published private(set) var lastError = ""

    private let config: ForearmConfig
    private let session = ARKitSession()
    private let provider = HandTrackingProvider()
    private var tracker: ForearmTracker
    private var updates: Task<Void, Never>?

    init(config: ForearmConfig) {
        self.config = config
        self.tracker = ForearmTracker(config: config)
    }

    func start() async {
        guard HandTrackingProvider.isSupported else {
            status = .unsupported
            return
        }
        let auth = await session.requestAuthorization(for: [.handTracking])
        guard auth[.handTracking] == .allowed else {
            status = .unauthorized
            return
        }
        do {
            try await session.run([provider])
        } catch {
            status = .failed
            lastError = error.localizedDescription
            return
        }
        status = .searching
        updates?.cancel()
        updates = Task { [weak self] in
            guard let self else { return }
            for await update in provider.anchorUpdates {
                guard !Task.isCancelled else { return }
                self.handle(update)
            }
        }
    }

    func stop() {
        updates?.cancel()
        updates = nil
        session.stop()
        tracker.reset()
        status = .idle
    }

    /// Called once per rendered frame by the scene. Returns nil until the
    /// held hand has been seen at least once.
    func pose(now: TimeInterval = CACurrentMediaTime()) -> PortPose? {
        let pose = tracker.pose(at: now)
        if let pose {
            let s: Status
            switch pose.status {
            case .searching: s = .searching
            case .tracked: s = .tracked
            case .holding: s = .holding
            case .faded: s = .faded
            }
            if s != status { status = s }
        }
        return pose
    }

    private var heldChirality: HandAnchor.Chirality {
        config.heldArm == .left ? .left : .right
    }

    private func handle(_ update: AnchorUpdate<HandAnchor>) {
        let anchor = update.anchor
        guard anchor.chirality == heldChirality else { return }
        let now = CACurrentMediaTime()
        guard update.event != .removed, anchor.isTracked, let skeleton = anchor.handSkeleton else {
            tracker.observe(nil, at: now)
            return
        }
        let wrist = skeleton.joint(.forearmWrist)
        let arm = skeleton.joint(.forearmArm)
        guard wrist.isTracked, arm.isTracked else {
            tracker.observe(nil, at: now)
            return
        }
        let origin = anchor.originFromAnchorTransform
        let raw = ForearmPoseSolver.solve(wrist: origin * wrist.anchorFromJointTransform,
                                          arm: origin * arm.anchorFromJointTransform,
                                          config: config)
        tracker.observe(raw, at: now)
    }
}
