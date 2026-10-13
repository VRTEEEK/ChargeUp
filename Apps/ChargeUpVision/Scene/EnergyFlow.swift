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
    let packets: [ModelEntity]
    /// 0 = fully retracted into the lantern, 1 = plugged into the port.
    private(set) var extension_: Float = 0
    private var phase: Float = 0
    private let speed: Float

    init(packetCount: Int, speedMps: Double) {
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
        var list: [ModelEntity] = []
        for i in 0..<max(1, packetCount) {
            let p = ModelEntity(mesh: .generateSphere(radius: Self.packetRadius), materials: [packetMaterial])
            p.name = "packet\(i)"
            p.isEnabled = false
            list.append(p)
        }
        packets = list
    }

    func attach(to content: RealityViewContent) {
        content.add(cable)
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
            for p in packets { p.isEnabled = false }
            return
        }
        let dir = full / length
        let visibleLength = length * extension_
        cable.isEnabled = true
        cable.position = socket + dir * (visibleLength / 2)
        cable.orientation = simd_quatf(from: SIMD3(0, 1, 0), to: dir)
        cable.scale = SIMD3(1, visibleLength, 1)

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
