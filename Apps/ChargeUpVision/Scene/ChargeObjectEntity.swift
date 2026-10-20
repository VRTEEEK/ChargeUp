import RealityKit
import UIKit
import ChargeUpCore

/// The lantern: the thing the infusion charges. Three states; the charging
/// state carries the fill level 0...1. Uses a designed model from the
/// assets package when one is present (its `Glass` material becomes the
/// LanternGlass shader and `fill` drives the rising light); otherwise the
/// procedural placeholder built here from primitives.
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

    /// Emissive levels for designed lanterns, from config.lantern. Set once by
    /// SceneDirector before any lantern is built.
    nonisolated(unsafe) static var glowLevels = (dark: Float(0.3), charging: Float(6), glance: Float(5), lit: Float(9))

    let root = Entity()
    /// Everything visible hangs off `body`, so the lantern can rise while
    /// `root` stays where the sky cluster is anchored.
    let body = Entity()
    /// The designed model, if the slot had a file. Nil means procedural.
    private let model: Entity?
    /// The designed model's bounds in its own frame, before centring.
    private var modelBounds: BoundingBox?
    private let core: ModelEntity
    private let fill: ModelEntity
    private(set) var state: State = .dark
    /// 0...1 extra brightness while the child glances at the lantern during
    /// the infusion. Set by SceneDirector; decays on its own.
    var glance: Float = 0
    /// Overall brightness multiplier for sky lanterns (a half-filled session glows less).
    private var brightness: Float = 1

    func setBrightness(_ value: Float) {
        brightness = max(0, min(1, value))
        apply(state)
    }

    /// Where the cable leaves the lantern, in the lantern's local frame: just
    /// under the cap at the front. From the model's bounds when designed.
    var cableSocket: SIMD3<Float> {
        if let b = modelBounds {
            let h = b.max.y - b.min.y
            return body.convert(position: SIMD3(0, h * 0.36, (b.max.z - b.min.z) * 0.5), to: root)
        }
        return body.convert(position: SIMD3(0, Self.capHeight / 2, Self.bodyRadius), to: root)
    }

    /// - Parameter model: a clone from `AssetCatalog.model(.lanternHero)` or a
    ///   variant, already carrying the Glass shader; nil for the placeholder.
    init(model: Entity? = nil) {
        root.name = "lantern"
        body.name = "lanternBody"
        root.addChild(body)
        self.model = model

        var glassMaterial = PhysicallyBasedMaterial()
        glassMaterial.baseColor = .init(tint: Self.glass)
        glassMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.22))
        glassMaterial.roughness = 0.1
        glassMaterial.metallic = 0.0
        let glass = ModelEntity(mesh: .generateCylinder(height: Self.bodyHeight, radius: Self.bodyRadius),
                                materials: [glassMaterial])
        glass.name = "lanternGlass"
        body.addChild(glass)

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
        body.addChild(cap)
        body.addChild(base)
        for i in 0..<4 {
            let bar = ModelEntity(mesh: .generateBox(width: 0.006, height: Self.bodyHeight, depth: 0.006),
                                  materials: [frameMaterial])
            let a = Float(i) * .pi / 2 + .pi / 4
            bar.position = SIMD3(cos(a) * Self.bodyRadius, 0, sin(a) * Self.bodyRadius)
            body.addChild(bar)
        }

        core = ModelEntity(mesh: .generateSphere(radius: Self.coreRadius), materials: [Self.glowMaterial(intensity: 0.05)])
        core.name = "lanternCore"
        body.addChild(core)

        fill = ModelEntity(mesh: .generateCylinder(height: 1, radius: Self.fillRadius), materials: [Self.glowMaterial(intensity: 0.6)])
        fill.name = "lanternFill"
        fill.isEnabled = false
        body.addChild(fill)

        if let model {
            // Designed lantern: the primitives stay built but hidden, so the
            // placeholder is one flag away if the file is removed. The model's
            // visual bounds are centred on the body origin, so a file whose
            // origin is at its base sits where the placeholder did.
            for child in body.children where child !== model { child.isEnabled = false }
            let bounds = model.visualBounds(relativeTo: nil)
            model.position = -bounds.center
            modelBounds = bounds
            body.addChild(model)
            // The shader masks on object-space height: tell it where this
            // model's glass starts and how tall it is.
            let glass = AssetCatalog.glassBounds(in: model) ?? bounds
            AssetCatalog.setParameter("baseY", glass.min.y, in: model)
            AssetCatalog.setParameter("height", max(0.001, glass.max.y - glass.min.y), in: model)
        }

        apply(.dark)
    }

    /// Designed path: `fill` on the Glass shader, 0...1; glow scaled by brightness and glance.
    private func applyToModel(fill level: Float, glow: Float) {
        guard let model else { return }
        AssetCatalog.setParameter(AssetCatalog.fillParameter, level, in: model)
        AssetCatalog.setParameter(AssetCatalog.glowIntensityParameter, glow, in: model)
    }

    func apply(_ newState: State) {
        state = newState
        if model != nil {
            let g = Self.glowLevels
            switch newState {
            case .dark: applyToModel(fill: 0, glow: g.dark)
            case .charging(let level): applyToModel(fill: max(0, min(1, level)), glow: (g.charging + g.glance * max(0, min(1, glance))) * brightness)
            case .lit: applyToModel(fill: 1, glow: g.lit * brightness)
            }
            return
        }
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
            core.model?.materials = [Self.glowMaterial(intensity: 4.0 * brightness)]
            fill.model?.materials = [Self.glowMaterial(intensity: 0.6 * brightness)]
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
