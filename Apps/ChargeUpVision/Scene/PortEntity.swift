import RealityKit
import UIKit
import ChargeUpCore

/// Everything that rides on the forearm: the port disc, the frost sparkles,
/// the seal patch and the charge mark. `root` takes the solved pose and the
/// tracking opacity; the children are animated by StepVisuals.
@MainActor
final class PortRig {
    /// Disc diameter and thickness in metres. Visual only; the anchor maths does not use them.
    private static let diameter: Float = 0.040
    private static let thickness: Float = 0.004
    private static let sparkleRadius: Float = 0.0025
    private static let sparkleOrbit: Float = 0.028
    private static let markOuter: Float = 0.026
    private static let sealSize = SIMD3<Float>(0.06, 0.002, 0.045)
    static let portBlue = UIColor(red: 0.2, green: 0.7, blue: 1.0, alpha: 1)
    static let frostWhite = UIColor(red: 0.85, green: 0.95, blue: 1.0, alpha: 1)
    static let markGold = UIColor(red: 1.0, green: 0.8, blue: 0.35, alpha: 1)
    static let sealTint = UIColor(red: 0.95, green: 0.9, blue: 0.85, alpha: 1)

    let root = Entity()
    /// The port visual's node: scale, position and opacity are animated on
    /// it. On the arm it carries the placeholder disc mesh or the designed
    /// ring; on the chest it carries the plate (designed or procedural) and
    /// no disc. The ring and the plate are alternatives, never layered.
    let disc: ModelEntity
    let sparkles: [ModelEntity]
    let mark: ModelEntity
    let seal: ModelEntity
    /// The designed port model (ring or plate), if its slot had a file.
    private let portModel: Entity?
    private let markModel: Entity?
    /// False holds the port model's Glass fill at 1 (constant emissive, no mask).
    private let glassMask: Bool

    init(sparkleCount: Int, accessSite: AccessSite, plateSize: SIMD2<Float>,
         assets: AssetCatalog? = nil, glassMask: Bool = true) {
        self.glassMask = glassMask
        root.name = "portRoot"
        root.components.set(OpacityComponent(opacity: 1))

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
        }

        var sealMaterial = PhysicallyBasedMaterial()
        sealMaterial.baseColor = .init(tint: Self.sealTint)
        sealMaterial.roughness = 0.9
        seal = ModelEntity(mesh: .generateBox(size: Self.sealSize, cornerRadius: 0.004), materials: [sealMaterial])
        seal.name = "sealPatch"
        seal.position.y = Self.thickness
        seal.components.set(OpacityComponent(opacity: 0))
        seal.isEnabled = false
        root.addChild(seal)
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
