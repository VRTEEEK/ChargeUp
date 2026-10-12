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
    let portRoot: Entity
    let lantern = ChargeObjectEntity()
    let sounds: SoundBank
    private var lastStepId: String?

    init(controller: SessionController) {
        self.controller = controller
        sounds = SoundBank(config: controller.sequence.config.audio)
        portRoot = PortEntity.make()
        portRoot.isEnabled = false
        portRoot.addChild(sounds.portSource)
        lantern.root.isEnabled = false
        lantern.root.addChild(sounds.lanternSource)
    }

    func loadSounds() async {
        await sounds.load(ids: controller.sequence.audioIds)
        controller.noteAudio(sounds.status)
    }

    func attach(to content: RealityViewContent) {
        content.add(portRoot)
        content.add(lantern.root)
    }

    /// World-anchor the lantern once from the head pose (or the fallback).
    func placeLantern(head: simd_float4x4?) {
        lantern.root.transform = Transform(matrix: LanternPlacement.transform(
            head: head, config: controller.sequence.config.lantern, simulated: controller.isSimulatedForearm))
        lantern.root.isEnabled = true
    }

    func frame(now: TimeInterval) {
        if let pose = controller.frame(now: now) {
            portRoot.isEnabled = true
            PortEntity.apply(pose, to: portRoot)
        } else {
            portRoot.isEnabled = false
        }
        updateLantern()
        stepChanged()
    }

    /// Fires once per step entry: per-step sound, loop handling.
    private func stepChanged() {
        let stepId = controller.currentStepId
        guard stepId != lastStepId else { return }
        lastStepId = stepId
        if let step = controller.currentStep {
            sounds.play(step.audio)
        } else {
            sounds.stopLoop()
        }
    }

    /// Lantern state from the session. Task 5 moves this into StepVisuals.
    private func updateLantern() {
        let state = controller.state
        let step = controller.currentStepId
        let target: ChargeObjectEntity.State
        switch step {
        case StepID.charge:
            target = .charging(level: Float(state.charge))
        case StepID.release, StepID.seal, SessionMarker.complete:
            target = .lit
        default:
            target = .dark
        }
        if target != lantern.state { lantern.apply(target) }
    }
}
