import RealityKit
import SwiftUI
import UIKit
import ChargeUpCore

/// The energy stream from the port to the lantern: golden fireflies flowing
/// along a curved path (EnergyPath, a cubic Bezier from the port's glass into
/// the lantern's glass, rebuilt from the current endpoints every frame) over
/// a very thin, faint amber core that breathes. Each firefly is a tiny light
/// with a short soft trail; they fade in at the port and fade and shrink
/// into the lantern, so none pops. The core tube is rebuilt on the cable
/// throttle; the fireflies and the flush spark ride the path every frame.
/// Every entity is made once and reused. Invisible until connect.
@MainActor
final class EnergyFlow {
    private static let segments = 32
    private static let sides = 16

    let core: ModelEntity
    private let flies: [Entity]
    /// The single first spark of the flush step, 0 at the port to 1 at the lantern; nil hides it.
    private let spark: Entity
    private var swarm: FireflySwarm
    private var coreMaterial: ShaderGraphMaterial?
    private var sparkProgress: Float?
    /// 0 = nothing, 1 = lit all the way to the lantern.
    private(set) var extension_: Float = 0
    private var visible = false
    private let config: VisualsConfig
    private let throttle: CableConfig
    private var lastLit: Float = -1
    private var lastOpacity: Float = -1
    /// True once a tube mesh has been built.
    private var hasMesh = false
    private var builtPort = SIMD3<Float>(repeating: .nan)
    private var builtTarget = SIMD3<Float>(repeating: .nan)
    private var builtAt: TimeInterval = -1
    /// Rebuild counter and the time it was last reset, for the operator window.
    private var rebuildCount = 0
    private var countSince: TimeInterval = 0
    private(set) var rebuildsPerSecond: Double = 0

    init(config: VisualsConfig, cable: CableConfig, assets: AssetCatalog? = nil) {
        self.config = config
        self.throttle = cable
        swarm = FireflySwarm(visuals: config)

        let color = Self.color(config.cableRGB)
        let coreLight: any RealityKit.Material
        if var m = assets?.cableLight {
            try? m.setParameter(name: "color", value: .color(color.cgColor))
            try? m.setParameter(name: "halo", value: .float(0))
            try? m.setParameter(name: "baseOpacity", value: .float(Float(config.streamCoreOpacity)))
            try? m.setParameter(name: "intensity", value: .float(1.5))
            coreLight = m
        } else {
            var u = UnlitMaterial(color: color)
            u.blending = .transparent(opacity: .init(floatLiteral: Float(config.streamCoreOpacity)))
            coreLight = u
        }
        core = ModelEntity(mesh: .generateSphere(radius: 0.001), materials: [coreLight])
        core.name = "streamCore"
        coreMaterial = coreLight as? ShaderGraphMaterial
        core.isEnabled = false

        flies = (0..<max(1, config.fireflyCount)).map { i in
            let f = Self.firefly(rgb: config.fireflyRGB(i), scale: 1, config: config)
            f.name = "firefly\(i)"
            return f
        }
        // The first spark is a larger pale-gold firefly.
        spark = Self.firefly(rgb: config.fireflyRGB(config.fireflyColors.count - 1), scale: Float(config.sparkScale), config: config)
        spark.name = "firstSpark"
    }

    func attach(to content: RealityViewContent) {
        content.add(core)
        content.add(spark)
        for f in flies { content.add(f) }
    }

    /// How far the stream is lit, 0...1. Also shows it; `hide()` removes it entirely.
    func setExtension(_ value: Float) {
        extension_ = max(0, min(1, value))
        visible = extension_ > 0.001
    }

    /// Gone, and the fireflies wait at the port again for next time.
    func hide() {
        extension_ = 0
        visible = false
        swarm = FireflySwarm(visuals: config)
    }

    func setSpark(_ progress: Float?) {
        sparkProgress = progress
    }

    /// `portUp` is the port's out-of-skin direction: the stream leaves its
    /// glass along it. `showFlow` lets fireflies out (the charge step);
    /// `flowing` keeps new ones setting off. When either stops, the ones in
    /// flight finish into the lantern rather than vanishing.
    func update(target: SIMD3<Float>, port: SIMD3<Float>, portUp: SIMD3<Float>, flowing: Bool, showFlow: Bool,
                dt: Float, now: TimeInterval) {
        let start = port + portUp * config.streamPortLift
        guard visible, simd_length(target - start) > 0.01 else {
            core.isEnabled = false
            spark.isEnabled = false
            for f in flies { f.isEnabled = false }
            return
        }
        let path = EnergyPath(port: start, portUp: portUp, target: target, bend: Float(config.streamBend))

        // Rebuild the core only when an endpoint moved past the threshold or
        // the lit value changed, and never faster than config.cable.rebuildHz.
        let litChanged = extension_ != lastLit
        let moved = builtPort.x.isNaN
            || simd_length(start - builtPort) > throttle.moveThreshold
            || simd_length(target - builtTarget) > throttle.moveThreshold
        if (moved || litChanged) && now - builtAt >= throttle.minInterval {
            if let mesh = CableMesh.tube(along: path.samples(segments: Self.segments),
                                         radius: Float(config.streamCoreMm / 2000), sides: Self.sides) {
                core.model?.mesh = mesh
                hasMesh = true
            }
            builtPort = start
            builtTarget = target
            builtAt = now
            rebuildCount += 1
            if litChanged {
                lastLit = extension_
                setCore("lit", extension_)
            }
        }
        if now - countSince >= 1 {
            rebuildsPerSecond = Double(rebuildCount) / max(0.001, now - countSince)
            rebuildCount = 0
            countSince = now
        }
        // The core breathes, gently; small steps are skipped.
        let breath = 1 + Float(config.streamPulseDepth) * sin(2 * .pi * Float(config.streamPulseHz) * Float(now))
        let opacity = Float(config.streamCoreOpacity) * breath
        if abs(opacity - lastOpacity) > 0.005 {
            lastOpacity = opacity
            setCore("baseOpacity", opacity)
        }
        core.isEnabled = hasMesh

        let fade = Float(config.flowFadeFraction)
        if let sparkProgress {
            place(spark, on: path, u: sparkProgress, wander: .zero, size: 1, opacity: EnergyPath.fade(at: sparkProgress, fade: fade))
        } else {
            spark.isEnabled = false
        }

        // Fireflies: out only once the stream reaches the lantern; while it
        // draws back they dim with it rather than vanish.
        if showFlow && extension_ > 0.99 || flies.contains(where: \.isEnabled) {
            swarm.advance(dt: dt, flowing: flowing && showFlow, visuals: config)
        }
        for (i, f) in flies.enumerated() {
            let fly = swarm.flies[i]
            guard fly.isVisible, extension_ > 0.001 else {
                f.isEnabled = false
                continue
            }
            place(f, on: path, u: fly.u, wander: FireflySwarm.wander(fly, time: now, visuals: config), size: fly.size,
                  opacity: EnergyPath.fade(at: fly.u, fade: fade) * extension_)
        }
    }

    /// Puts a firefly on the path at `u`, offset sideways by `wander` across
    /// the path, shrinking as it goes into the lantern's glass.
    private func place(_ f: Entity, on path: EnergyPath, u: Float, wander: SIMD2<Float>, size: Float, opacity: Float) {
        f.isEnabled = opacity > 0.001
        guard f.isEnabled else { return }
        let t = path.tangent(at: u)
        var side = simd_cross(t, SIMD3<Float>(0, 1, 0))
        if simd_length(side) < 1e-4 { side = simd_cross(t, SIMD3<Float>(1, 0, 0)) }
        side = simd_normalize(side)
        let across = simd_cross(side, t)
        f.position = path.point(at: u) + side * wander.x + across * wander.y
        let arriving = max(0, min(1, (u - 0.85) / 0.15))
        f.scale = SIMD3(repeating: size * (1 - 0.6 * arriving * arriving * (3 - 2 * arriving)))
        f.components.set(OpacityComponent(opacity: opacity))
    }

    private func setCore(_ name: String, _ value: Float) {
        guard var m = coreMaterial else { return }
        try? m.setParameter(name: name, value: .float(value))
        coreMaterial = m
        core.model?.materials = [m]
    }

    /// A tiny unlit light (it shows its colour exactly, never blown out to
    /// white) with a short soft trail of warm specks left behind in world space.
    private static func firefly(rgb: SIMD3<Float>, scale: Float, config: VisualsConfig) -> Entity {
        let color = Self.color(rgb)
        let size = Float(config.fireflySizeMm / 1000) * scale
        let head = ModelEntity(mesh: .generateSphere(radius: size / 2), materials: [UnlitMaterial(color: color)])
        var p = ParticleEmitterComponent()
        p.emitterShape = .point
        p.speed = 0
        p.particlesInheritTransform = false
        var e = p.mainEmitter
        e.birthRate = Float(config.fireflyTrailPerSecond)
        e.lifeSpan = config.fireflyTrailLife * Double(scale)
        e.size = size * 0.9
        e.sizeMultiplierAtEndOfLifespan = 0.1
        e.color = .constant(.single(color))
        e.opacityCurve = .linearFadeOut
        e.blendMode = .additive
        e.billboardMode = .billboard
        e.isLightingEnabled = false
        p.mainEmitter = e
        head.components.set(p)
        head.components.set(OpacityComponent(opacity: 0))
        head.isEnabled = false
        return head
    }

    private static func color(_ rgb: SIMD3<Float>) -> UIColor {
        UIColor(red: CGFloat(rgb.x), green: CGFloat(rgb.y), blue: CGFloat(rgb.z), alpha: 1)
    }
}
