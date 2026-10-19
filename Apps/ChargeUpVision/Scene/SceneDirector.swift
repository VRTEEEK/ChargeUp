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
    private var lastFrameAt: TimeInterval = 0
    private var headWasOnLantern = false

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
        let dt = Float(max(0, min(0.1, now - lastFrameAt)))
        lastFrameAt = now
        let pose = controller.frame(now: now)
        if let pose { rig.apply(pose) }
        stepChanged(now: now)
        let state = controller.state
        updateGlance(dt: dt)
        let socket = lantern.root.convert(position: lantern.cableSocket, to: nil)
        visuals.update(now: now, charge: Float(state.charge),
                       isCharging: state.isCharging(in: controller.sequence),
                       portWorld: pose?.position, socketWorld: socket)
    }

    /// Nice to have from the brief: during the infusion, a head turn toward
    /// the lantern brightens it briefly, then it settles. Edge-triggered on
    /// entering the cone, decays over config.charge.glanceSeconds.
    private func updateGlance(dt: Float) {
        let cfg = controller.sequence.config.charge
        var onLantern = false
        if controller.currentStepId == StepID.charge, let head = controller.headPose.current() {
            let headPos = ForearmPoseSolver.translation(of: head)
            let f = head.columns.2
            let forward = simd_normalize(SIMD3<Float>(-f.x, -f.y, -f.z))
            let toLantern = lantern.root.position - headPos
            if simd_length(toLantern) > 0.01 {
                let cosine = simd_dot(forward, simd_normalize(toLantern))
                onLantern = cosine > cos(Float(cfg.glanceDegrees) * .pi / 180)
            }
        }
        if onLantern && !headWasOnLantern { lantern.glance = 1 }
        headWasOnLantern = onLantern
        if lantern.glance > 0 {
            lantern.glance = max(0, lantern.glance - dt / Float(cfg.glanceSeconds))
        }
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
