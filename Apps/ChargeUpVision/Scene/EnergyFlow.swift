import RealityKit
import SwiftUI
import UIKit
import ChargeUpCore

/// The cable of light from the port to the lantern socket, and the sparks
/// that run along it. A warm core with a soft halo, sagging between its
/// ends, lit from the port end toward the lantern as `extension_` grows.
/// Invisible until connect; rebuilt each frame because the port moves.
@MainActor
final class EnergyFlow {
    private static let packetRadius: Float = 0.006
    private static let segments = 24

    let core: ModelEntity
    let halo: ModelEntity
    let packets: [Entity]
    /// The single first spark of the flush step, 0 at the port to 1 at the lantern; nil hides it.
    let spark: Entity
    /// The cable end in the port, designed `plug` or a short bright cylinder.
    let plug: Entity
    private var coreMaterial: ShaderGraphMaterial?
    private var haloMaterial: ShaderGraphMaterial?
    private var sparkProgress: Float?
    /// 0 = nothing, 1 = lit all the way to the lantern.
    private(set) var extension_: Float = 0
    private var visible = false
    private var phase: Float = 0
    private let speed: Float
    private let config: VisualsConfig
    private var lastLit: Float = -1

    init(config: VisualsConfig, assets: AssetCatalog? = nil) {
        self.config = config
        speed = Float(config.flowSpeedMps)
        let rgb = config.cableRGB
        let color = UIColor(red: CGFloat(rgb.x), green: CGFloat(rgb.y), blue: CGFloat(rgb.z), alpha: 1)

        func lightMaterial(halo: Bool) -> any RealityKit.Material {
            if var m = assets?.cableLight {
                try? m.setParameter(name: "color", value: .color(color.cgColor))
                try? m.setParameter(name: "halo", value: .float(halo ? 1 : 0))
                try? m.setParameter(name: "baseOpacity", value: .float(halo ? Float(config.cableHaloOpacity) : 1))
                try? m.setParameter(name: "intensity", value: .float(halo ? 1.5 : 3))
                return m
            }
            var u = UnlitMaterial(color: color)
            u.blending = .transparent(opacity: .init(floatLiteral: halo ? Float(config.cableHaloOpacity) : 1))
            return u
        }
        core = ModelEntity(mesh: .generateSphere(radius: 0.001), materials: [lightMaterial(halo: false)])
        core.name = "cableCore"
        halo = ModelEntity(mesh: .generateSphere(radius: 0.001), materials: [lightMaterial(halo: true)])
        halo.name = "cableHalo"
        coreMaterial = core.model?.materials.first as? ShaderGraphMaterial
        haloMaterial = halo.model?.materials.first as? ShaderGraphMaterial
        core.isEnabled = false
        halo.isEnabled = false

        var packetMaterial = PhysicallyBasedMaterial()
        packetMaterial.baseColor = .init(tint: color)
        packetMaterial.emissiveColor = .init(color: color)
        packetMaterial.emissiveIntensity = 5
        func makeSpark(scale: Float) -> Entity {
            if let model = assets?.model(.spark) {
                model.scale = SIMD3(repeating: scale)
                return model
            }
            if let assets, let material = assets.spriteMaterial(.spark) {
                let size = Self.packetRadius * 3 * scale * assets.spriteScale(.spark)
                let sprite = ModelEntity(mesh: .generatePlane(width: size, height: size), materials: [material])
                sprite.components.set(BillboardComponent())
                return sprite
            }
            return ModelEntity(mesh: .generateSphere(radius: Self.packetRadius * scale), materials: [packetMaterial])
        }
        var list: [Entity] = []
        for i in 0..<max(1, config.flowPacketCount) {
            let p = makeSpark(scale: 1)
            p.name = "packet\(i)"
            p.isEnabled = false
            list.append(p)
        }
        packets = list
        spark = makeSpark(scale: 1.6)
        spark.name = "spark"
        spark.isEnabled = false
        if let designed = assets?.model(.plug) {
            plug = designed
        } else {
            var plugMaterial = PhysicallyBasedMaterial()
            plugMaterial.baseColor = .init(tint: color)
            plugMaterial.emissiveColor = .init(color: color)
            plugMaterial.emissiveIntensity = 2
            plugMaterial.metallic = 0.3
            let p = ModelEntity(mesh: .generateCylinder(height: 0.016, radius: config.cableCore * 1.1), materials: [plugMaterial])
            p.position.y = 0.008
            let holder = Entity()
            holder.addChild(p)
            plug = holder
        }
        plug.name = "plug"
        plug.isEnabled = false
    }

    func attach(to content: RealityViewContent) {
        content.add(halo)
        content.add(core)
        content.add(spark)
        content.add(plug)
        for p in packets { content.add(p) }
    }

    /// How far the cable is lit, 0...1. Also shows it; `hide()` removes it entirely.
    func setExtension(_ value: Float) {
        extension_ = max(0, min(1, value))
        visible = extension_ > 0.001
    }

    func hide() {
        extension_ = 0
        visible = false
    }

    func setSpark(_ progress: Float?) {
        sparkProgress = progress
    }

    func update(socket: SIMD3<Float>, port: SIMD3<Float>, flowing: Bool, showPackets: Bool, dt: Float) {
        let length = simd_length(socket - port)
        guard visible, length > 0.01 else {
            core.isEnabled = false
            halo.isEnabled = false
            spark.isEnabled = false
            plug.isEnabled = false
            for p in packets { p.isEnabled = false }
            return
        }
        let points = CableMesh.catenaryPoints(from: port, to: socket, sag: config.cableSag, segments: Self.segments)
        if let coreMesh = CableMesh.tube(along: points, radius: config.cableCore / 2),
           let haloMesh = CableMesh.tube(along: points, radius: config.cableHalo / 2) {
            core.model?.mesh = coreMesh
            halo.model?.mesh = haloMesh
        }
        if extension_ != lastLit {
            lastLit = extension_
            if var m = coreMaterial { try? m.setParameter(name: "lit", value: .float(extension_)); coreMaterial = m; core.model?.materials = [m] }
            if var m = haloMaterial { try? m.setParameter(name: "lit", value: .float(extension_)); haloMaterial = m; halo.model?.materials = [m] }
        }
        core.isEnabled = true
        halo.isEnabled = true
        plug.isEnabled = true
        plug.position = port
        plug.orientation = simd_quatf(from: SIMD3(0, 1, 0), to: simd_normalize(points[1] - points[0]))

        if let sparkProgress {
            spark.isEnabled = true
            spark.position = CableMesh.point(on: points, at: sparkProgress)
        } else {
            spark.isEnabled = false
        }
        if flowing { phase += speed * dt / length }
        phase = phase.truncatingRemainder(dividingBy: 1)
        let show = showPackets && extension_ > 0.99
        for (i, p) in packets.enumerated() {
            p.isEnabled = show
            guard show else { continue }
            // Packets travel from the port into the lantern.
            let u = (phase + Float(i) / Float(packets.count)).truncatingRemainder(dividingBy: 1)
            p.position = CableMesh.point(on: points, at: u)
        }
    }
}
