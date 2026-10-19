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
    let lantern: ChargeObjectEntity
    let flow: EnergyFlow
    let sounds: SoundBank
    let visuals: StepVisuals
    let sky: LanternSky
    private var lastStepId: String?
    /// Rise animation state: start time and the slot the lantern is heading for.
    private var riseStartedAt: TimeInterval?
    private var riseTarget: SIMD3<Float> = .zero
    private var lastFrameAt: TimeInterval = 0
    private var headWasOnLantern = false

    init(controller: SessionController) {
        self.controller = controller
        let config = controller.sequence.config
        let assets = controller.assets
        ChargeObjectEntity.glowLevels = (dark: Float(config.lantern.glowDark), charging: Float(config.lantern.glowCharging),
                                   glance: Float(config.lantern.glowGlance), lit: Float(config.lantern.glowLit))
        sounds = SoundBank(config: config.audio)
        rig = PortRig(sparkleCount: config.visuals.frostSparkleCount, assets: assets)
        if config.accessSite == .chestPort {
            rig.root.addChild(DressingPlateEntity.make(size: config.chestPort.plateSize, assets: assets))
        }
        rig.root.isEnabled = false
        rig.root.addChild(sounds.portSource)
        lantern = ChargeObjectEntity(model: assets.model(.lanternHero))
        lantern.root.isEnabled = false
        lantern.root.addChild(sounds.lanternSource)
        flow = EnergyFlow(packetCount: config.visuals.flowPacketCount, speedMps: config.visuals.flowSpeedMps, assets: assets)
        visuals = StepVisuals(config: config.visuals, rig: rig, lantern: lantern, flow: flow)
        sky = LanternSky(config: config.sky, assets: assets)
        lantern.root.addChild(sky.root)
        sky.show(controller.skySessions)
        controller.onSkyChanged = { [weak self] sessions in self?.sky.show(sessions) }
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
        updateRise(now: now)
        let socket = lantern.root.convert(position: lantern.cableSocket, to: nil)
        visuals.update(now: now, charge: Float(state.charge),
                       isCharging: state.isCharging(in: controller.sequence),
                       portWorld: pose?.position, socketWorld: socket)
    }

    /// At release the current lantern rises into the next free sky slot over
    /// config.sky.riseSeconds; the record is written as the rise starts. On
    /// the next idle the risen lantern is rebuilt as part of the sky and the
    /// main lantern comes back dark for the next session.
    private func updateRise(now: TimeInterval) {
        guard let riseStartedAt else { return }
        let u = Float(min(1, (now - riseStartedAt) / controller.sequence.config.sky.rise))
        let eased = 1 - (1 - u) * (1 - u)
        lantern.body.position = riseTarget * eased
        lantern.body.scale = SIMD3(repeating: 1 - (1 - Float(controller.sequence.config.sky.smallScale)) * eased)
        if u >= 1 { self.riseStartedAt = nil }
    }

    private func startRise(now: TimeInterval) {
        riseTarget = sky.slot(sky.count)
        riseStartedAt = now
        controller.sessionReleased()
    }

    private func resetRise() {
        riseStartedAt = nil
        lantern.body.position = .zero
        lantern.body.scale = .one
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
        switch stepId {
        case StepID.release: startRise(now: now)
        case SessionMarker.idle, StepID.cream: resetRise()
        default: break
        }
        if let step = controller.currentStep {
            sounds.play(step.audio)
        } else {
            sounds.stopLoop()
        }
    }
}
