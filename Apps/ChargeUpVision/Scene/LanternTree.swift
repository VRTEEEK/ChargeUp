import Foundation
import RealityKit
import UIKit
import SwiftUI
import ChargeUpCore

/// The lantern tree from the `lantern_tree` slot: where every finished
/// session's lantern hangs. It stands on the floor in front of the child,
/// door toward them, fades in when the space opens, breathes a slow glow
/// through its emissive map (the heart, the door, its little baked lights),
/// sheds golden motes through the canopy, and flares when a lantern lands.
/// The lanterns themselves are LanternSky's; they hang under `frame`.
/// Every number comes from config.tree.
@MainActor
final class LanternTree {
    /// Placed, unscaled frame: base centre at the origin, +Z toward the child.
    let frame = Entity()
    /// Model units to metres.
    let modelScale: Float
    let height: Float
    private let model: Entity
    private let config: TreeConfig
    /// The model's PBR materials as loaded, per model component, so the
    /// glow is always set from the original rather than compounded.
    private var glowTargets: [(entity: ModelEntity, materials: [any RealityKit.Material])] = []
    private let motes = Entity()
    private let light = Entity()
    /// Sparks shed by a flying lantern; follows it, particles stay behind.
    let trail = Entity()
    /// The burst where a lantern lands.
    private let burst = Entity()
    private var placedAt: TimeInterval?
    private var flareAt: TimeInterval?
    private var lastGlow: Float = -1
    private(set) var status = "not built"

    init?(assets: AssetCatalog, config: TreeConfig) {
        guard config.enabled, let model = assets.model(.lanternTree) else { return nil }
        self.config = config
        self.model = model
        let bounds = model.visualBounds(relativeTo: nil)
        let modelHeight = max(0.001, bounds.max.y - bounds.min.y)
        modelScale = Float(config.heightM) / modelHeight
        height = Float(config.heightM)
        frame.name = "lanternTree"
        frame.isEnabled = false
        model.scale = SIMD3(repeating: modelScale)
        // Hooks are in the file's frame with its base at y = 0; keep that.
        model.position = SIMD3(0, -bounds.min.y * modelScale, 0)
        frame.addChild(model)

        model.visit { entity in
            guard let m = entity as? ModelEntity, let materials = m.model?.materials,
                  materials.contains(where: { $0 is PhysicallyBasedMaterial }) else { return }
            glowTargets.append((m, materials))
        }

        let width = (bounds.max.x - bounds.min.x) * modelScale
        let depth = (bounds.max.z - bounds.min.z) * modelScale
        buildMotes(width: width, depth: depth)
        light.name = "treeLight"
        light.position = SIMD3(0, Float(config.light.height) * height, Float(config.light.forwardM))
        light.components.set(PointLightComponent(color: Self.color(config.light.rgb), intensity: Float(config.light.intensity),
                                                 attenuationRadius: Float(config.light.attenuationRadiusM)))
        frame.addChild(light)
        buildTrail()
        buildBurst()
        frame.addChild(motes)
        status = String(format: "%.1f m, %d hooks, glow on %d mesh(es)", height, config.hooks.count, glowTargets.count)
    }

    /// World-anchor the tree once, from the same head pose as the lantern.
    func place(_ transform: simd_float4x4, now: TimeInterval) {
        frame.transform = Transform(matrix: transform)
        frame.isEnabled = true
        placedAt = now
        if config.appearSeconds > 0 { frame.components.set(OpacityComponent(opacity: 0)) }
    }

    /// A lantern has just landed at `world`: flare the tree and burst sparks there.
    func lanternLanded(at world: SIMD3<Float>, now: TimeInterval) {
        flareAt = now
        burst.setPosition(world, relativeTo: nil)
        if var p = burst.components[ParticleEmitterComponent.self] {
            p.burst()
            burst.components.set(p)
        }
    }

    /// Start or stop the flight trail.
    func setTrail(emitting: Bool) {
        guard var p = trail.components[ParticleEmitterComponent.self], p.isEmitting != emitting else { return }
        p.isEmitting = emitting
        trail.components.set(p)
    }

    func update(now: TimeInterval) {
        if let placedAt {
            let u = config.appearSeconds > 0 ? Float(min(1, (now - placedAt) / config.appearSeconds)) : 1
            if u >= 1 {
                frame.components.remove(OpacityComponent.self)
                self.placedAt = nil
            } else {
                frame.components.set(OpacityComponent(opacity: u * u * (3 - 2 * u)))
            }
        }
        let g = config.glow
        var glow = Float(g.base * (1 + g.breathe * sin(2 * .pi * now / g.periodS)))
        if let flareAt {
            let t = now - flareAt
            if t > g.landingDecaySeconds * 4 { self.flareAt = nil }
            glow += Float(g.landingBoost * exp(-t / g.landingDecaySeconds))
        }
        // Small steps are invisible; skip the material write.
        guard abs(glow - lastGlow) > 0.005 else { return }
        lastGlow = glow
        if var l = light.components[PointLightComponent.self] {
            l.intensity = Float(config.light.intensity) * glow
            light.components.set(l)
        }
        for target in glowTargets {
            target.entity.model?.materials = target.materials.map { material in
                guard var pbr = material as? PhysicallyBasedMaterial else { return material }
                pbr.emissiveIntensity *= glow
                return pbr
            }
        }
    }

    // MARK: Particles

    private func buildMotes(width: Float, depth: Float) {
        let m = config.motes
        var p = ParticleEmitterComponent()
        p.emitterShape = .box
        p.birthLocation = .volume
        p.emitterShapeSize = SIMD3(Float(m.box[0]) * width, Float(m.box[1]) * height, Float(m.box[2]) * depth)
        p.birthDirection = .world
        p.emissionDirection = SIMD3(0, 1, 0)
        p.speed = Float(m.speedMps)
        p.speedVariation = Float(m.speedMps) * 0.5
        var e = p.mainEmitter
        e.birthRate = Float(m.birthRate)
        e.lifeSpan = m.lifeSpanS
        e.lifeSpanVariation = m.lifeSpanS * 0.3
        e.size = Float(m.sizeMm / 1000)
        e.sizeVariation = Float(m.sizeMm / 1000) * 0.5
        e.color = .constant(.single(Self.color(m.rgb)))
        e.opacityCurve = .gradualFadeInOut
        e.blendMode = .additive
        e.billboardMode = .billboard
        e.noiseStrength = 0.02
        e.noiseScale = 1
        e.noiseAnimationSpeed = 0.2
        e.isLightingEnabled = false
        p.mainEmitter = e
        motes.name = "treeMotes"
        motes.position = SIMD3(0, Float(m.centreHeight) * height, 0)
        motes.components.set(p)
    }

    private func buildTrail() {
        let t = config.trail
        var p = ParticleEmitterComponent()
        p.emitterShape = .sphere
        p.emitterShapeSize = SIMD3(repeating: 0.03)
        p.birthLocation = .volume
        p.speed = 0.02
        p.particlesInheritTransform = false
        p.isEmitting = false
        var e = p.mainEmitter
        e.birthRate = Float(t.birthRate)
        e.lifeSpan = t.lifeSpanS
        e.lifeSpanVariation = t.lifeSpanS * 0.3
        e.size = Float(t.sizeMm / 1000)
        e.sizeMultiplierAtEndOfLifespan = 0.1
        e.color = .constant(.single(Self.color(config.motes.rgb)))
        e.opacityCurve = .linearFadeOut
        e.blendMode = .additive
        e.billboardMode = .billboard
        e.acceleration = SIMD3(0, -0.05, 0)
        e.isLightingEnabled = false
        p.mainEmitter = e
        trail.name = "lanternTrail"
        trail.components.set(p)
    }

    private func buildBurst() {
        let b = config.landingBurst
        var p = ParticleEmitterComponent()
        p.emitterShape = .sphere
        p.emitterShapeSize = SIMD3(repeating: 0.02)
        p.birthLocation = .surface
        p.birthDirection = .normal
        p.speed = Float(b.speedMps)
        p.speedVariation = Float(b.speedMps) * 0.4
        p.burstCount = b.count
        p.burstCountVariation = b.count / 5
        p.isEmitting = false
        var e = p.mainEmitter
        e.birthRate = 0
        e.lifeSpan = b.lifeSpanS
        e.lifeSpanVariation = b.lifeSpanS * 0.3
        e.size = Float(b.sizeMm / 1000)
        e.sizeMultiplierAtEndOfLifespan = 0.2
        e.color = .constant(.single(Self.color(config.motes.rgb)))
        e.opacityCurve = .quickFadeInOut
        e.blendMode = .additive
        e.billboardMode = .billboard
        e.dampingFactor = 2
        e.acceleration = SIMD3(0, -0.08, 0)
        e.isLightingEnabled = false
        p.mainEmitter = e
        burst.name = "landingBurst"
        burst.components.set(p)
    }

    /// The trail and the burst live in world space, beside the tree.
    func attach(to content: RealityViewContent) {
        content.add(frame)
        content.add(trail)
        content.add(burst)
    }

    private static func color(_ rgb: SIMD3<Float>) -> UIColor {
        UIColor(red: CGFloat(rgb.x), green: CGFloat(rgb.y), blue: CGFloat(rgb.z), alpha: 1)
    }
}

private extension Entity {
    func visit(_ body: (Entity) -> Void) {
        body(self)
        for child in children { child.visit(body) }
    }
}
