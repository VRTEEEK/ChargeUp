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
        case StepID.cream: cream()
        case StepID.clean: clean()
        case StepID.countdown: countdown()
        case StepID.connect: connect()
        case StepID.flush: flush()
        case StepID.charge: charge()
        case StepID.release: release()
        case SessionMarker.complete: complete()
        default: idle()
        }
    }

    /// Nothing on the access site, lantern dark, cable away.
    private func idle() {
        rig.root.isEnabled = false
        rig.disc.components[OpacityComponent.self]?.opacity = 1
        rig.disc.scale = .one
        rig.disc.position = .zero
        rig.placeSparkles(phase: 0, visible: false)
        rig.mark.isEnabled = false
        rig.mark.components[OpacityComponent.self]?.opacity = 0
        rig.setDisc(tint: PortRig.portBlue, emissive: 2)
        flow.setExtension(0)
        flow.setSpark(nil)
        lantern.apply(.dark)
    }

    /// The port glow grows under the skin as the cream works.
    private func cream() {
        idle()
        rig.root.isEnabled = true
        rig.disc.components[OpacityComponent.self]?.opacity = 0
        rig.setDisc(tint: PortRig.portBlue, emissive: 0.2)
    }

    /// Port polished: frost shimmer.
    private func clean() {
        rig.root.isEnabled = true
        rig.disc.components[OpacityComponent.self]?.opacity = 1
        rig.placeSparkles(phase: 0, visible: true)
    }

    /// Three pulses of light at the port. The child holds still here.
    private func countdown() {
        rig.root.isEnabled = true
        rig.disc.components[OpacityComponent.self]?.opacity = 1
        rig.placeSparkles(phase: 0, visible: false)
        rig.setDisc(tint: PortRig.portBlue, emissive: 2)
    }

    /// Cable clicks into the port. The needle moment.
    private func connect() {
        rig.setDisc(tint: PortRig.portBlue, emissive: 3)
        flow.setExtension(0)
    }

    /// The first spark runs up the cable and the lantern wakes.
    private func flush() {
        flow.setExtension(1)
        flow.setSpark(0)
        lantern.apply(.charging(level: 0))
    }

    /// The lantern fills on its own time. No one is held here.
    private func charge() {
        flow.setExtension(1)
        flow.setSpark(nil)
    }

    /// Cable disconnects; lantern fully lit; the mark fades onto the dressing.
    private func release() {
        lantern.apply(.lit)
        flow.setSpark(nil)
        rig.setRingFill(1)
        rig.mark.isEnabled = true
    }

    /// Port gone, mark stays on the dressing, lantern stays lit.
    private func complete() {
        lantern.apply(.lit)
        flow.setExtension(0)
        rig.disc.components[OpacityComponent.self]?.opacity = 0
        rig.mark.components[OpacityComponent.self]?.opacity = 1
    }

    // MARK: Per frame

    func update(now: TimeInterval, charge: Float, isCharging: Bool, portWorld: SIMD3<Float>?, socketWorld: SIMD3<Float>) {
        let dt = Float(max(0, min(0.1, now - lastUpdate)))
        lastUpdate = now
        let t = now - enteredAt

        switch stepId {
        case StepID.cream:
            let u = Float(min(1, t / config.creamGlow))
            let eased = u * u
            rig.disc.components[OpacityComponent.self]?.opacity = 0.15 + 0.85 * eased
            rig.setDisc(tint: PortRig.portBlue, emissive: 0.2 + 1.8 * eased)
        case StepID.clean:
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
        case StepID.flush:
            let u = Float(min(1, t / config.flushSpark))
            flow.setSpark(u < 1 ? u : nil)
            if u >= 1 { lantern.apply(.charging(level: max(charge, 0.02))) }
        case StepID.charge:
            lantern.apply(.charging(level: charge))
            rig.setRingFill(charge)
        case StepID.release:
            flow.setExtension(Float(max(0, 1 - t / config.cableRetract)))
            let u = Float(min(1, t / config.markFade))
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
