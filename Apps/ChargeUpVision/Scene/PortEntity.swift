import RealityKit
import UIKit
import ChargeUpCore

/// Everything that rides on the forearm: the port disc, the frost sparkles,
/// the charge mark. `root` takes the solved pose and the
/// tracking opacity; the children are animated by StepVisuals.
@MainActor
final class PortRig {
    /// Disc diameter and thickness in metres. Visual only; the anchor maths does not use them.
    private static let diameter: Float = 0.040
    private static let thickness: Float = 0.004
    private static let sparkleRadius: Float = 0.0025
    private static let sparkleOrbit: Float = 0.028
    private static let markOuter: Float = 0.026
    static let portBlue = UIColor(red: 0.2, green: 0.7, blue: 1.0, alpha: 1)
    static let frostWhite = UIColor(red: 0.85, green: 0.95, blue: 1.0, alpha: 1)
    static let markGold = UIColor(red: 1.0, green: 0.8, blue: 0.35, alpha: 1)

    let root = Entity()
    /// The port visual's node: scale, position and opacity are animated on
    /// it. On the arm it carries the placeholder disc mesh or the designed
    /// ring; on the chest it carries the plate (designed or procedural) and
    /// no disc. The ring and the plate are alternatives, never layered.
    let disc: ModelEntity
    let sparkles: [ModelEntity]
    let mark: ModelEntity
    /// The designed port model (ring or plate), if its slot had a file.
    private let portModel: Entity?
    private let markModel: Entity?
    /// False holds the port model's Glass fill at 1 (constant emissive, no mask).
    private let glassMask: Bool
    /// The tiled surface: a tube along the forearm (arm) or a flat surround
    /// under the plate (chest). Placeholder geometry only; Milestone 2 task 2
    /// (the real sleeve with occlusion) is untouched. Nil without a tile.
    let sleeve: ModelEntity?
    /// Which tile the sleeve got, for the operator window.
    let sleeveTileUsed: String?

    init(sparkleCount: Int, accessSite: AccessSite, plateSize: SIMD2<Float>, sleeveConfig: SleeveConfig,
         forearmRadius: Float, assets: AssetCatalog? = nil, glassMask: Bool = true) {
        self.glassMask = glassMask
        root.name = "portRoot"
        root.components.set(OpacityComponent(opacity: 1))

        if let tile = assets?.sleeveTexture(named: sleeveConfig.tile) {
            let material = AssetCatalog.sleeveMaterial(tile.texture, opacity: Float(sleeveConfig.opacity),
                                                       tiling: Float(sleeveConfig.tileRepeat))
            let entity: ModelEntity
            switch accessSite {
            case .arm:
                // A tube around the forearm axis (+X toward the hand), its surface at the skin.
                entity = ModelEntity(mesh: .generateCylinder(height: sleeveConfig.length, radius: forearmRadius),
                                     materials: [material])
                entity.orientation = simd_quatf(from: SIMD3(0, 1, 0), to: SIMD3(1, 0, 0))
                entity.position = SIMD3(0, -forearmRadius, 0)
            case .chestPort:
                // A flat surround under the plate on the skin plane.
                let size = sleeveConfig.surroundSize
                entity = ModelEntity(mesh: .generatePlane(width: size.x, depth: size.y, cornerRadius: min(size.x, size.y) * 0.2),
                                     materials: [material])
                entity.position = SIMD3(0, -0.0015, 0)
            }
            entity.name = "sleeve"
            sleeve = entity
            sleeveTileUsed = tile.slot.rawValue
            root.addChild(entity)
        } else {
            sleeve = nil
            sleeveTileUsed = nil
        }

        disc = ModelEntity()
        disc.name = "portVisual"
        disc.components.set(OpacityComponent(opacity: 1))
        root.addChild(disc)
        switch accessSite {
        case .arm:
            portModel = assets?.model(.portRing)
            if let portModel {
                // The ring's origin is its base; the rig root is the skin plane.
                disc.addChild(portModel)
            } else {
                disc.model = ModelComponent(mesh: .generateCylinder(height: Self.thickness, radius: Self.diameter / 2),
                                            materials: [Self.discMaterial(tint: Self.portBlue, emissive: 2)])
            }
        case .chestPort:
            let plate = DressingPlateEntity.make(size: plateSize, assets: assets, glassMask: glassMask)
            portModel = plate.name == DressingPlateEntity.designedName ? plate : nil
            disc.addChild(plate)
        }
        if let portModel {
            AssetCatalog.setParameter(AssetCatalog.fillParameter, glassMask ? 0 : 1, in: portModel)
        }

        var list: [ModelEntity] = []
        for i in 0..<max(1, sparkleCount) {
            let s = ModelEntity(mesh: .generateSphere(radius: Self.sparkleRadius),
                                materials: [Self.discMaterial(tint: Self.frostWhite, emissive: 6)])
            s.name = "sparkle\(i)"
            s.isEnabled = false
            root.addChild(s)
            list.append(s)
        }
        sparkles = list

        mark = ModelEntity(mesh: .generateCylinder(height: Self.thickness / 2, radius: Self.markOuter),
                           materials: [Self.discMaterial(tint: Self.markGold, emissive: 3)])
        mark.name = "chargeMark"
        mark.position.y = -Self.thickness / 4
        mark.components.set(OpacityComponent(opacity: 0))
        mark.isEnabled = false
        root.addChild(mark)
        markModel = assets?.model(.chargeMark)
        if let markModel {
            mark.components.remove(ModelComponent.self)
            mark.addChild(markModel)
        } else if let assets, let sprite = assets.spriteMaterial(.chargeMark) {
            // The designed mark as a sprite lying on the skin, alpha from the PNG,
            // sized so its opaque content spans the mark's diameter.
            let size = Self.markOuter * 2 * assets.spriteScale(.chargeMark)
            mark.model = ModelComponent(mesh: .generatePlane(width: size, depth: size), materials: [sprite])
            mark.position.y = 0.0005
        }

    }

    /// Apply a solved pose to the root. Called every frame; cheap.
    func apply(_ pose: PortPose) {
        root.position = pose.position
        root.orientation = pose.orientation
        root.components[OpacityComponent.self]?.opacity = pose.opacity
    }

    /// Procedural disc: retint it. Designed ring or plate: drive the Glass
    /// shader's glow colour and intensity (and any material named `Glow`).
    func setDisc(tint: UIColor, emissive: Float) {
        if let portModel {
            AssetCatalog.setGlow(emissive, tint: tint, in: portModel)
            AssetCatalog.setParameter(AssetCatalog.glowIntensityParameter, emissive, in: portModel)
            AssetCatalog.setColorParameter(AssetCatalog.glowColorParameter, tint, in: portModel)
        } else if disc.model != nil {
            disc.model?.materials = [Self.discMaterial(tint: tint, emissive: emissive)]
        }
    }

    /// Designed port model with the mask on: its glass fills with the charge.
    func setRingFill(_ fill: Float) {
        guard let portModel, glassMask else { return }
        AssetCatalog.setParameter(AssetCatalog.fillParameter, fill, in: portModel)
    }

    /// Place the sparkles on an orbit around the disc at `phase` radians.
    func placeSparkles(phase: Float, visible: Bool) {
        for (i, s) in sparkles.enumerated() {
            s.isEnabled = visible
            guard visible else { continue }
            let a = phase + Float(i) / Float(sparkles.count) * 2 * .pi
            let lift = 0.006 + 0.004 * sin(phase * 2 + Float(i))
            s.position = SIMD3(cos(a) * Self.sparkleOrbit, lift, sin(a) * Self.sparkleOrbit)
        }
    }

    static func discMaterial(tint: UIColor, emissive: Float) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: tint)
        m.emissiveColor = .init(color: tint)
        m.emissiveIntensity = emissive
        m.roughness = 0.3
        return m
    }
}
