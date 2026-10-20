import RealityKit
import SwiftUI
import UIKit
import ChargeUpCore

/// The cable from the lantern to the port, and the packets that run along
/// it while the charge flows. World-space entities; endpoints are given
/// every frame because the port moves.
@MainActor
final class EnergyFlow {
    private static let cableRadius: Float = 0.004
    private static let packetRadius: Float = 0.006
    private static let cableColor = UIColor(red: 0.25, green: 0.3, blue: 0.4, alpha: 1)
    private static let packetColor = UIColor(red: 1.0, green: 0.85, blue: 0.4, alpha: 1)

    let cable: ModelEntity
    let packets: [Entity]
    /// The single first spark of the flush step, 0 at the port to 1 at the lantern; nil hides it.
    let spark: Entity
    /// The cable end in the port, designed `plug` or a short bright cylinder.
    let plug: Entity
    private var sparkProgress: Float?
    /// 0 = fully retracted into the lantern, 1 = plugged into the port.
    private(set) var extension_: Float = 0
    private var phase: Float = 0
    private let speed: Float

    init(packetCount: Int, speedMps: Double, assets: AssetCatalog? = nil) {
        speed = Float(speedMps)
        var cableMaterial = PhysicallyBasedMaterial()
        cableMaterial.baseColor = .init(tint: Self.cableColor)
        cableMaterial.emissiveColor = .init(color: UIColor(red: 0.4, green: 0.7, blue: 1.0, alpha: 1))
        cableMaterial.emissiveIntensity = 0.6
        cableMaterial.roughness = 0.5
        cable = ModelEntity(mesh: .generateCylinder(height: 1, radius: Self.cableRadius), materials: [cableMaterial])
        cable.name = "cable"
        cable.isEnabled = false

        var packetMaterial = PhysicallyBasedMaterial()
        packetMaterial.baseColor = .init(tint: Self.packetColor)
        packetMaterial.emissiveColor = .init(color: Self.packetColor)
        packetMaterial.emissiveIntensity = 5
        /// Designed spark: a model if there is one, else the PNG as a sprite that
        /// always faces the viewer, else the procedural sphere.
        func makeSpark(scale: Float) -> Entity {
            if let model = assets?.model(.spark) {
                model.scale = SIMD3(repeating: scale)
                return model
            }
            if let assets, let material = assets.spriteMaterial(.spark) {
                // The glyph should read about three packet radii across whatever
                // fraction of its canvas it was drawn on.
                let size = Self.packetRadius * 3 * scale * assets.spriteScale(.spark)
                let sprite = ModelEntity(mesh: .generatePlane(width: size, height: size), materials: [material])
                sprite.components.set(BillboardComponent())
                return sprite
            }
            return ModelEntity(mesh: .generateSphere(radius: Self.packetRadius * scale), materials: [packetMaterial])
        }
        var list: [Entity] = []
        for i in 0..<max(1, packetCount) {
            let p = makeSpark(scale: 1)
            p.name = "packet\(i)"
            p.isEnabled = false
            list.append(p)
        }
        packets = list
        if assets?.model(.spark) != nil || assets?.texture(.spark) != nil {
            spark = makeSpark(scale: 1.6)
        } else {
            var sparkMaterial = packetMaterial
            sparkMaterial.emissiveIntensity = 10
            spark = ModelEntity(mesh: .generateSphere(radius: Self.packetRadius * 1.6), materials: [sparkMaterial])
        }
        spark.name = "spark"
        spark.isEnabled = false
        if let designed = assets?.model(.plug) {
            plug = designed
        } else {
            var plugMaterial = PhysicallyBasedMaterial()
            plugMaterial.baseColor = .init(tint: Self.cableColor)
            plugMaterial.emissiveColor = .init(color: UIColor(red: 0.6, green: 0.85, blue: 1.0, alpha: 1))
            plugMaterial.emissiveIntensity = 1.5
            plugMaterial.metallic = 0.6
            let p = ModelEntity(mesh: .generateCylinder(height: 0.016, radius: Self.cableRadius * 2.2), materials: [plugMaterial])
            p.position.y = 0.008
            let holder = Entity()
            holder.addChild(p)
            plug = holder
        }
        plug.name = "plug"
        plug.isEnabled = false
    }

    func setSpark(_ progress: Float?) {
        sparkProgress = progress
    }

    func attach(to content: RealityViewContent) {
        content.add(cable)
        content.add(spark)
        content.add(plug)
        for p in packets { content.add(p) }
    }

    func setExtension(_ value: Float) {
        extension_ = max(0, min(1, value))
    }

    /// Lay the cable from `socket` toward `port`, `extension_` of the way,
    /// and advance the packets if `flowing`.
    func update(socket: SIMD3<Float>, port: SIMD3<Float>, flowing: Bool, showPackets: Bool, dt: Float) {
        let full = port - socket
        let length = simd_length(full)
        guard extension_ > 0.001, length > 0.01 else {
            cable.isEnabled = false
            spark.isEnabled = false
            plug.isEnabled = false
            for p in packets { p.isEnabled = false }
            return
        }
        let dir = full / length
        let visibleLength = length * extension_
        cable.isEnabled = true
        cable.position = socket + dir * (visibleLength / 2)
        cable.orientation = simd_quatf(from: SIMD3(0, 1, 0), to: dir)
        cable.scale = SIMD3(1, visibleLength, 1)
        // The plug sits in the port once the cable has arrived; its +Y points up the cable.
        plug.isEnabled = extension_ > 0.99
        plug.position = port
        plug.orientation = simd_quatf(from: SIMD3(0, 1, 0), to: -dir)

        if let sparkProgress {
            spark.isEnabled = true
            spark.position = port - dir * (sparkProgress * length)
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
            p.position = port - dir * (u * length)
        }
    }
}
