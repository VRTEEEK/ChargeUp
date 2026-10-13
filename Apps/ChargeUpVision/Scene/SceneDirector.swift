import Foundation
import RealityKit
import SwiftUI
import QuartzCore
import ChargeUpCore

/// Owns every entity in the child's view and drives them from the session
/// state once per frame. The ImmersiveView is a thin shell around this.
@MainActor
final class SceneDirector {
    let controller: SessionController
    let rig: PortRig
    let lantern = ChargeObjectEntity()
    let flow: EnergyFlow
    let sounds: SoundBank
    let visuals: StepVisuals
    private var lastStepId: String?

    init(controller: SessionController) {
        self.controller = controller
        let config = controller.sequence.config
        sounds = SoundBank(config: config.audio)
        rig = PortRig(sparkleCount: config.visuals.frostSparkleCount)
        rig.root.isEnabled = false
        rig.root.addChild(sounds.portSource)
        lantern.root.isEnabled = false
        lantern.root.addChild(sounds.lanternSource)
        flow = EnergyFlow(packetCount: config.visuals.flowPacketCount, speedMps: config.visuals.flowSpeedMps)
        visuals = StepVisuals(config: config.visuals, rig: rig, lantern: lantern, flow: flow)
    }

    func attach(to content: RealityViewContent) {
        content.add(rig.root)
        content.add(lantern.root)
        flow.attach(to: content)
    }

    func loadSounds() async {
        await sounds.load(ids: controller.sequence.audioIds)
        controller.noteAudio(sounds.status)
    }

    /// World-anchor the lantern once from the head pose (or the fallback).
    func placeLantern(head: simd_float4x4?) {
        lantern.root.transform = Transform(matrix: LanternPlacement.transform(
            head: head, config: controller.sequence.config.lantern, simulated: controller.isSimulatedForearm))
        lantern.root.isEnabled = true
    }

    func frame(now: TimeInterval) {
        let pose = controller.frame(now: now)
        if let pose { rig.apply(pose) }
        stepChanged(now: now)
        let state = controller.state
        let socket = lantern.root.convert(position: lantern.cableSocket, to: nil)
        visuals.update(now: now, charge: Float(state.charge),
                       isCharging: state.isCharging(in: controller.sequence),
                       portWorld: pose?.position, socketWorld: socket)
    }

    /// Fires once per step entry: visuals and sound for the row.
    private func stepChanged(now: TimeInterval) {
        let stepId = controller.currentStepId
        guard stepId != lastStepId else { return }
        lastStepId = stepId
        visuals.enter(stepId, at: now)
        if let step = controller.currentStep {
            sounds.play(step.audio)
        } else {
            sounds.stopLoop()
        }
    }
}
