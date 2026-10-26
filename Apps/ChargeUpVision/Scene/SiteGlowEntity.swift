import Foundation
import RealityKit
import UIKit
import ChargeUpCore

/// The glow sleeve: a soft-edged patch lying against the skin at the port,
/// amber at the centre fading to nothing, the tile faint inside it. On the
/// arm it stretches along the forearm with the charge; on the chest it is a
/// disc around the dome. The falloff is in the SiteGlow shader on UV
/// distance from the centre, so the patch mesh never shows an edge.
@MainActor
final class SiteGlowEntity {
    let root = Entity()
    private let patch: ModelEntity
    private let config: SiteGlowConfig
    private let accessSite: AccessSite
    private var material: ShaderGraphMaterial?
    private var pulse: Float = 0
    private let lift: Float = 0.0008

    init?(assets: AssetCatalog, sleeve: SleeveConfig, accessSite: AccessSite, forearmRadius: Float) {
        guard var m = assets.siteGlow else { return nil }
        config = sleeve.glow
        self.accessSite = accessSite
        try? m.setParameter(name: "intensity", value: .float(Float(config.intensity)))
        try? m.setParameter(name: "tileOpacity", value: .float(Float(config.tileOpacity)))
        if let tile = assets.sleeveTexture(named: sleeve.tile) {
            try? m.setParameter(name: "tile", value: .textureResource(tile.texture))
            try? m.setParameter(name: "hasTile", value: .float(1))
        }
        material = m
        // A unit plane on the skin (XZ), +Y out; scaled per frame to the extent.
        patch = ModelEntity(mesh: .generatePlane(width: 1, depth: 1), materials: [m])
        patch.name = "siteGlow"
        patch.position.y = lift
        root.name = "siteGlowRoot"
        root.addChild(patch)
        setExtent(charge: 0)
    }

    /// Arm: `charge` 0...1 grows the extent along the forearm (the rig's X).
    func setExtent(charge: Float) {
        switch accessSite {
        case .arm:
            let along = config.extentMin + (config.extentMax - config.extentMin) * max(0, min(1, charge))
            // The shader's falloff reaches zero at UV radius 0.5, the plane's edge,
            // so the plane's size is the glow's full extent.
            patch.scale = SIMD3(along, 1, config.width)
        case .chestPort:
            patch.scale = SIMD3(config.chestDisc, 1, config.chestDisc)
        }
    }

    /// 0...1 momentary brightening, decays by the caller each frame.
    func setPulse(_ value: Float) {
        guard value != pulse, var m = material else { return }
        pulse = value
        try? m.setParameter(name: "intensity", value: .float(Float(config.intensity) * (1 + Float(config.pulseGain) * value)))
        material = m
        patch.model?.materials = [m]
    }

    func setVisible(_ on: Bool) { root.isEnabled = on }
}
