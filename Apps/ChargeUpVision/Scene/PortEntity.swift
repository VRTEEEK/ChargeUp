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
    /// The glow-style sleeve; nil for the tube style or without the shader.
    let glow: SiteGlowEntity?
    /// Which tile the sleeve got, for the operator window.
    let sleeveTileUsed: String?
    /// A few golden motes drifting up from the port (config.port.motes).
    let motes = Entity()
    private let look: PortLookConfig
    /// The badge's textures, kept to set its glow.
    private var markTexture: (color: TextureResource, alpha: TextureResource?)?
    private var markGlow: Float = -1

    init(visuals: VisualsConfig, look: PortLookConfig, accessSite: AccessSite, plateSize: SIMD2<Float>, sleeveConfig: SleeveConfig,
         forearmRadius: Float, assets: AssetCatalog? = nil, glassMask: Bool = true) {
        self.glassMask = glassMask
        self.look = look
        root.name = "portRoot"
        root.components.set(OpacityComponent(opacity: 1))

        if sleeveConfig.style == .glow {
            sleeve = nil
            if let assets, let g = SiteGlowEntity(assets: assets, sleeve: sleeveConfig, accessSite: accessSite, forearmRadius: forearmRadius) {
                glow = g
                root.addChild(g.root)
                sleeveTileUsed = assets.sleeveTexture(named: sleeveConfig.tile).map { "glow with \($0.slot.rawValue)" } ?? "glow, no tile"
            } else {
                glow = nil
                sleeveTileUsed = "glow shader missing"
            }
        } else if sleeveConfig.style == .tube, let tile = assets?.sleeveTexture(named: sleeveConfig.tile) {
            glow = nil
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
            glow = nil
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
                // The ring's origin is its base; the rig root is the estimated
                // skin plane, and the ring sits config.port.sinkMm into it.
                portModel.position.y = -look.sink
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
            // Amber glass, nearly opaque: a jewel, not a see-through coin.
            AssetCatalog.setColorParameter(AssetCatalog.glassColorParameter, Self.color(look.glassRGB), in: portModel)
            AssetCatalog.setParameter(AssetCatalog.glassOpacityParameter, Float(look.glassOpacity), in: portModel)
        }
        motes.name = "portMotes"
        motes.components.set(Self.motesEmitter(look.motes))
        root.addChild(motes)

        var list: [ModelEntity] = []
        for i in 0..<max(1, visuals.frostSparkleCount) {
            let color = Self.color(visuals.frostSparkleRGB(i))
            let s = ModelEntity(mesh: .generateSphere(radius: Self.sparkleRadius),
                                materials: [Self.discMaterial(tint: color, emissive: 6)])
            s.name = "sparkle\(i)"
            s.components.set(Self.sparkleTrail(color: color, visuals: visuals))
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
        } else if let assets, let badge = assets.spriteTexture(.chargeMark) {
            // The designed badge lying on the skin along the forearm (+X), its
            // opaque content `markLengthMm` long and as wide as the image's
            // shape makes it; it glows in its own colours (setMarkGlow).
            let extent = assets.spriteExtent(.chargeMark)
            let length = Float(visuals.markLengthMm / 1000) / max(0.01, extent.x)
            let width = length * assets.spriteAspect(.chargeMark)
            mark.model = ModelComponent(mesh: .generatePlane(width: length, depth: width),
                                        materials: [AssetCatalog.glowSpriteMaterial(badge.color, alpha: badge.alpha,
                                                                                    brightness: Float(visuals.markGlowBase))])
            mark.position.y = 0.0005
            markTexture = badge
        }

    }

    /// Apply a solved pose to the root. Called every frame; cheap.
    func apply(_ pose: PortPose) {
        root.position = pose.position
        root.orientation = pose.orientation
        root.components[OpacityComponent.self]?.opacity = pose.opacity
    }

    /// Procedural disc: retint it. Designed ring or plate: light its glass
    /// (and any material named `Glow`), always amber, at the step's level
    /// scaled down and capped by config.port, so only the glass glows and
    /// never overexposes.
    func setDisc(tint: UIColor, emissive: Float) {
        if let portModel {
            let amber = Self.color(look.glowRGB), level = look.glow(for: emissive)
            AssetCatalog.setGlow(level, tint: amber, in: portModel)
            AssetCatalog.setParameter(AssetCatalog.glowIntensityParameter, level, in: portModel)
            AssetCatalog.setColorParameter(AssetCatalog.glowColorParameter, amber, in: portModel)
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

    /// The badge's glow, 0...1 of the image's own brightness; small changes are skipped.
    func setMarkGlow(_ brightness: Float) {
        guard let badge = markTexture, abs(brightness - markGlow) > 0.01 else { return }
        markGlow = brightness
        mark.model?.materials = [AssetCatalog.glowSpriteMaterial(badge.color, alpha: badge.alpha, brightness: brightness)]
    }

    /// Start or stop the golden motes; ones already drifting fade out.
    func setMotes(_ on: Bool) {
        guard var p = motes.components[ParticleEmitterComponent.self], p.isEmitting != on else { return }
        p.isEmitting = on
        motes.components.set(p)
    }

    /// Small golden motes born round the port and drifting slowly off the
    /// skin; they ride with the arm.
    private static func motesEmitter(_ m: PortMotesConfig) -> ParticleEmitterComponent {
        var p = ParticleEmitterComponent()
        p.emitterShape = .cylinder
        p.birthLocation = .volume
        p.emitterShapeSize = SIMD3(Float(m.spreadMm / 1000) * 2, 0.002, Float(m.spreadMm / 1000) * 2)
        p.birthDirection = .local
        p.emissionDirection = SIMD3(0, 1, 0)
        p.speed = Float(m.riseMmPerS / 1000)
        p.speedVariation = Float(m.riseMmPerS / 1000) * 0.5
        p.particlesInheritTransform = true
        p.isEmitting = false
        var e = p.mainEmitter
        e.birthRate = Float(m.perSecond)
        e.lifeSpan = m.life
        e.lifeSpanVariation = m.life * 0.3
        e.size = Float(m.sizeMm / 1000)
        e.sizeVariation = Float(m.sizeMm / 1000) * 0.3
        e.color = .constant(.single(color(m.rgb)))
        e.opacityCurve = .gradualFadeInOut
        e.blendMode = .additive
        e.billboardMode = .billboard
        e.noiseStrength = 0.002
        e.noiseScale = 1
        e.noiseAnimationSpeed = 0.2
        e.isLightingEnabled = false
        p.mainEmitter = e
        return p
    }

    /// A short trail of glowing specks in the sparkle's colour, left in
    /// world space as it orbits; a disabled sparkle emits nothing.
    private static func sparkleTrail(color: UIColor, visuals: VisualsConfig) -> ParticleEmitterComponent {
        var p = ParticleEmitterComponent()
        p.emitterShape = .point
        p.speed = 0
        p.particlesInheritTransform = false
        var e = p.mainEmitter
        e.birthRate = Float(visuals.frostSparkleTrailPerSecond)
        e.lifeSpan = visuals.frostSparkleTrailLife
        e.size = sparkleRadius * 1.4
        e.sizeMultiplierAtEndOfLifespan = 0.15
        e.color = .constant(.single(color))
        e.opacityCurve = .linearFadeOut
        e.blendMode = .additive
        e.billboardMode = .billboard
        e.isLightingEnabled = false
        p.mainEmitter = e
        return p
    }

    private static func color(_ rgb: SIMD3<Float>) -> UIColor {
        UIColor(red: CGFloat(rgb.x), green: CGFloat(rgb.y), blue: CGFloat(rgb.z), alpha: 1)
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
