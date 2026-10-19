import RealityKit
import UIKit
import ChargeUpCore

/// The lantern: the thing the injection charges. Three states; the charging
/// state carries the fill level 0...1. Built from primitives so it needs no
/// Reality Composer Pro package.
@MainActor
final class ChargeObjectEntity {
    enum State: Equatable {
        case dark
        case charging(level: Float)
        case lit
    }

    /// Lantern dimensions in metres. Visual only.
    private static let bodyHeight: Float = 0.16
    private static let bodyRadius: Float = 0.05
    private static let coreRadius: Float = 0.028
    private static let fillRadius: Float = 0.042
    private static let capHeight: Float = 0.012
    private static let glow = UIColor(red: 1.0, green: 0.78, blue: 0.35, alpha: 1)
    private static let glass = UIColor(red: 0.85, green: 0.92, blue: 1.0, alpha: 0.22)
    private static let frame = UIColor(red: 0.18, green: 0.16, blue: 0.14, alpha: 1)

    let root = Entity()
    private let core: ModelEntity
    private let fill: ModelEntity
    private(set) var state: State = .dark
    /// 0...1 extra brightness while the child glances at the lantern during
    /// the infusion. Set by SceneDirector; decays on its own.
    var glance: Float = 0

    /// Where the cable leaves the lantern, in the lantern's local frame.
    var cableSocket: SIMD3<Float> { SIMD3(0, Self.capHeight / 2, Self.bodyRadius) }

    init() {
        root.name = "lantern"

        var glassMaterial = PhysicallyBasedMaterial()
        glassMaterial.baseColor = .init(tint: Self.glass)
        glassMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.22))
        glassMaterial.roughness = 0.1
        glassMaterial.metallic = 0.0
        let body = ModelEntity(mesh: .generateCylinder(height: Self.bodyHeight, radius: Self.bodyRadius),
                               materials: [glassMaterial])
        body.name = "lanternBody"
        root.addChild(body)

        var frameMaterial = PhysicallyBasedMaterial()
        frameMaterial.baseColor = .init(tint: Self.frame)
        frameMaterial.roughness = 0.6
        frameMaterial.metallic = 0.8
        let cap = ModelEntity(mesh: .generateCylinder(height: Self.capHeight, radius: Self.bodyRadius + 0.006),
                              materials: [frameMaterial])
        cap.position.y = Self.bodyHeight / 2 + Self.capHeight / 2
        let base = ModelEntity(mesh: .generateCylinder(height: Self.capHeight, radius: Self.bodyRadius + 0.006),
                               materials: [frameMaterial])
        base.position.y = -Self.bodyHeight / 2 - Self.capHeight / 2
        root.addChild(cap)
        root.addChild(base)
        for i in 0..<4 {
            let bar = ModelEntity(mesh: .generateBox(width: 0.006, height: Self.bodyHeight, depth: 0.006),
                                  materials: [frameMaterial])
            let a = Float(i) * .pi / 2 + .pi / 4
            bar.position = SIMD3(cos(a) * Self.bodyRadius, 0, sin(a) * Self.bodyRadius)
            root.addChild(bar)
        }

        core = ModelEntity(mesh: .generateSphere(radius: Self.coreRadius), materials: [Self.glowMaterial(intensity: 0.05)])
        core.name = "lanternCore"
        root.addChild(core)

        fill = ModelEntity(mesh: .generateCylinder(height: 1, radius: Self.fillRadius), materials: [Self.glowMaterial(intensity: 0.6)])
        fill.name = "lanternFill"
        fill.isEnabled = false
        root.addChild(fill)

        apply(.dark)
    }

    func apply(_ newState: State) {
        state = newState
        switch newState {
        case .dark:
            core.model?.materials = [Self.glowMaterial(intensity: 0.05)]
            fill.isEnabled = false
        case .charging(let level):
            let l = max(0, min(1, level))
            let g = max(0, min(1, glance))
            // Resting during the infusion the lantern is calm; a glance
            // brightens the core and shows the fill clearly, then settles.
            core.model?.materials = [Self.glowMaterial(intensity: 0.2 + 1.5 * l + 3.0 * g)]
            fill.model?.materials = [Self.glowMaterial(intensity: 0.3 + 1.2 * g)]
            setFill(l)
        case .lit:
            core.model?.materials = [Self.glowMaterial(intensity: 4.0)]
            setFill(1)
        }
    }

    private func setFill(_ level: Float) {
        let h = max(0.002, level * (Self.bodyHeight - 0.02))
        fill.isEnabled = level > 0.005
        fill.scale = SIMD3(1, h, 1)
        fill.position.y = -Self.bodyHeight / 2 + 0.01 + h / 2
    }

    private static func glowMaterial(intensity: Float) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: glow)
        m.emissiveColor = .init(color: glow)
        m.emissiveIntensity = intensity
        m.roughness = 0.4
        return m
    }
}
