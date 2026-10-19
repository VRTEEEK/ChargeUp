import Foundation
import RealityKit
import ChargeUpCore

/// Past sessions as a cluster of small lit lanterns above and behind the
/// current one. World-anchored with the current lantern; no text. Slot
/// positions are a deterministic function of the index so the same sky
/// looks the same every visit.
@MainActor
final class LanternSky {
    let root = Entity()
    private let config: SkyConfig
    private var lanterns: [ChargeObjectEntity] = []

    init(config: SkyConfig) {
        self.config = config
        root.name = "lanternSky"
    }

    var count: Int { lanterns.count }

    /// Local position (relative to the current lantern) of sky slot `index`.
    func slot(_ index: Int) -> SIMD3<Float> {
        // Fill a loose arc: alternate left and right, climb slowly, drift back.
        let i = Float(index)
        let side: Float = index % 2 == 0 ? -1 : 1
        let ring = Float(index / 2)
        let x = side * (0.12 + 0.11 * ring) * Float(config.clusterSpreadM) / 0.7
        let y = Float(config.clusterHeightM) + 0.07 * ring + 0.025 * sin(i * 1.7)
        let z = -Float(config.clusterBehindM) - 0.06 * ring + 0.02 * cos(i * 2.3)
        return SIMD3(x, y, z)
    }

    /// Rebuild the cluster from the store. Cheap for a few dozen lanterns.
    func show(_ sessions: [SessionRecord]) {
        for l in lanterns { l.root.removeFromParent() }
        lanterns = []
        for (index, session) in sessions.enumerated() {
            let lantern = ChargeObjectEntity()
            lantern.root.position = slot(index)
            lantern.root.scale = SIMD3(repeating: Float(config.smallScale))
            lantern.apply(.lit)
            // A session that ended early is a dimmer lantern, honestly.
            lantern.glance = 0
            lantern.root.name = "skyLantern\(index)"
            lantern.setBrightness(Float(max(0.35, session.fill)))
            root.addChild(lantern.root)
            lanterns.append(lantern)
        }
    }
}
