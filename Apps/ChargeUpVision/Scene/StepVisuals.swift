import Foundation
import RealityKit
import UIKit
import ChargeUpCore

/// One function per step id. `enter` runs once when the host enters a step;
/// `update` runs every frame. Every number comes from config.visuals.
@MainActor
final class StepVisuals {
    private let config: VisualsConfig
    private let rig: PortRig
    private let lantern: ChargeObjectEntity
    private let flow: EnergyFlow

    private var stepId = SessionMarker.idle
    private var enteredAt: TimeInterval = 0
    private var lastUpdate: TimeInterval = 0

    init(config: VisualsConfig, rig: PortRig, lantern: ChargeObjectEntity, flow: EnergyFlow) {
        self.config = config
        self.rig = rig
        self.lantern = lantern
        self.flow = flow
    }

    // MARK: Step entry

    func enter(_ id: String, at now: TimeInterval) {
        stepId = id
        enteredAt = now
        switch id {
        case StepID.hold: hold()
        case StepID.swab: swab()
        case StepID.countdown: countdown()
        case StepID.connect: connect()
        case StepID.charge: charge()
        case StepID.release: release()
        case StepID.seal: seal()
        case SessionMarker.complete: complete()
        default: idle()
        }
    }

    /// Nothing on the arm, lantern dark, cable away.
    private func idle() {
        rig.root.isEnabled = false
        rig.disc.components[OpacityComponent.self]?.opacity = 1
        rig.disc.scale = .one
        rig.placeSparkles(phase: 0, visible: false)
        rig.mark.isEnabled = false
        rig.mark.components[OpacityComponent.self]?.opacity = 0
        rig.seal.isEnabled = false
        rig.seal.components[OpacityComponent.self]?.opacity = 0
        rig.setDisc(tint: PortRig.portBlue, emissive: 2)
        flow.setExtension(0)
        lantern.apply(.dark)
    }

    /// Guide places the charging port on the forearm: soft landing.
    private func hold() {
        idle()
        rig.root.isEnabled = true
        rig.disc.scale = SIMD3(repeating: 0.01)
    }

    /// Port is cooled and polished: frost shimmer.
    private func swab() {
        rig.root.isEnabled = true
        rig.disc.scale = .one
        rig.placeSparkles(phase: 0, visible: true)
    }

    /// Three pulses of light at the port.
    private func countdown() {
        rig.root.isEnabled = true
        rig.disc.scale = .one
        rig.placeSparkles(phase: 0, visible: false)
        rig.setDisc(tint: PortRig.portBlue, emissive: 2)
    }

    /// Cable clicks into the port.
    private func connect() {
        rig.setDisc(tint: PortRig.portBlue, emissive: 3)
        flow.setExtension(0)
    }

    /// Energy flows while the arm is still and the head is on the port.
    private func charge() {
        flow.setExtension(1)
    }

    /// Cable disconnects; lantern fully lit.
    private func release() {
        lantern.apply(.lit)
    }

    /// Seal placed over the port; charge mark remains on the arm.
    private func seal() {
        lantern.apply(.lit)
        flow.setExtension(0)
        rig.mark.isEnabled = true
        rig.seal.isEnabled = true
    }

    /// Port gone, mark stays, lantern stays lit.
    private func complete() {
        lantern.apply(.lit)
        flow.setExtension(0)
        rig.disc.components[OpacityComponent.self]?.opacity = 0
        rig.seal.components[OpacityComponent.self]?.opacity = 1
        rig.mark.components[OpacityComponent.self]?.opacity = 1
    }

    // MARK: Per frame

    func update(now: TimeInterval, charge: Float, isCharging: Bool, portWorld: SIMD3<Float>?, socketWorld: SIMD3<Float>) {
        let dt = Float(max(0, min(0.1, now - lastUpdate)))
        lastUpdate = now
        let t = now - enteredAt

        switch stepId {
        case StepID.hold:
            let u = Float(min(1, t / config.portLanding))
            let eased = 1 - (1 - u) * (1 - u)
            rig.disc.scale = SIMD3(repeating: max(0.01, eased))
            rig.disc.position.y = (1 - eased) * 0.05
        case StepID.swab:
            rig.placeSparkles(phase: Float(t) * 2.5, visible: true)
            let shimmer = 0.5 + 0.5 * sin(Float(t) * 9)
            rig.setDisc(tint: blend(PortRig.portBlue, PortRig.frostWhite, 0.6), emissive: 2 + 2 * shimmer)
        case StepID.countdown:
            let pulseIndex = Int(t / config.countdownPulse)
            if pulseIndex < config.countdownPulseCount {
                let frac = Float((t / config.countdownPulse).truncatingRemainder(dividingBy: 1))
                let bump = sin(frac * .pi)
                rig.setDisc(tint: PortRig.portBlue, emissive: 2 + 8 * bump)
            } else {
                rig.setDisc(tint: PortRig.portBlue, emissive: 2)
            }
        case StepID.connect:
            flow.setExtension(Float(min(1, t / config.cableSnap)))
        case StepID.charge:
            lantern.apply(.charging(level: charge))
        case StepID.release:
            flow.setExtension(Float(max(0, 1 - t / config.cableRetract)))
        case StepID.seal:
            let u = Float(min(1, t / config.sealFade))
            rig.seal.components[OpacityComponent.self]?.opacity = 0.85 * u
            rig.mark.components[OpacityComponent.self]?.opacity = u
            rig.disc.components[OpacityComponent.self]?.opacity = 1 - u
        default:
            break
        }

        if let portWorld {
            flow.update(socket: socketWorld, port: portWorld, flowing: isCharging,
                        showPackets: stepId == StepID.charge, dt: dt)
        } else {
            flow.update(socket: socketWorld, port: socketWorld, flowing: false, showPackets: false, dt: dt)
        }
    }

    private func blend(_ a: UIColor, _ b: UIColor, _ t: CGFloat) -> UIColor {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return UIColor(red: ar + (br - ar) * t, green: ag + (bg - ag) * t, blue: ab + (bb - ab) * t, alpha: 1)
    }
}
