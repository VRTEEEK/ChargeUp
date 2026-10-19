import Foundation
import ARKit
import UIKit
import QuartzCore
import ChargeUpCore

/// Chest port: puts the port on a printed 50 mm marker stuck to the dressing,
/// tracked with ARKit image tracking. Behind the same PortPoseSource protocol
/// as the forearm anchor; chosen only when config.accessSite is chestPort.
/// COMPILE-ONLY: image tracking does not run in the simulator and this has
/// never been run on a headset. Targeted API: visionOS 2.0
/// (ImageTrackingProvider, ReferenceImage(cgimage:physicalSize:), ImageAnchor).
@MainActor
final class MarkerPortPoseSource: PortPoseSource {
    enum Status: String {
        case idle, unsupported, noMarkerImage, failed, searching, tracked, holding, faded
    }

    private(set) var status: Status = .idle
    private(set) var lastError = ""

    private let config: ChestPortConfig
    private let session = ARKitSession()
    private var provider: ImageTrackingProvider?
    /// Hold-and-fade and smoothing are the same as the forearm's; the
    /// values come from config.forearm so they tune in one place.
    private var tracker: ForearmTracker
    private var updates: Task<Void, Never>?

    init(config: ChestPortConfig, smoothing: ForearmConfig) {
        self.config = config
        self.tracker = ForearmTracker(config: smoothing)
    }

    var statusText: String { "marker " + status.rawValue + (lastError.isEmpty ? "" : " " + lastError) }
    var reportsPresence: Bool { false }

    func start() async {
        guard ImageTrackingProvider.isSupported else {
            status = .unsupported
            return
        }
        // Loaded by name from the assets package, so a designed emblem drops in
        // under the same file name at the same printed size.
        guard let image = AssetCatalog.loadImage(named: config.markerImage) else {
            status = .noMarkerImage
            return
        }
        let reference = ReferenceImage(cgimage: image,
                                       physicalSize: CGSize(width: Double(config.markerSize), height: Double(config.markerSize)))
        let provider = ImageTrackingProvider(referenceImages: [reference])
        self.provider = provider
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
            for await update in provider.anchorUpdates {
                guard !Task.isCancelled else { return }
                self?.handle(update)
            }
        }
    }

    func stop() {
        updates?.cancel()
        updates = nil
        session.stop()
        provider = nil
        tracker.reset()
        status = .idle
    }

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

    private func handle(_ update: AnchorUpdate<ImageAnchor>) {
        let now = CACurrentMediaTime()
        let anchor = update.anchor
        guard update.event != .removed, anchor.isTracked else {
            tracker.observe(nil, at: now)
            return
        }
        tracker.observe(MarkerPoseSolver.solve(marker: anchor.originFromAnchorTransform, config: config), at: now)
    }
}
