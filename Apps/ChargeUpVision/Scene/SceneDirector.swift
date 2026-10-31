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
    /// World-anchored once at session start. The current lantern, the sky,
    /// the companion and the lantern's audio hang off it, so a lantern can
    /// leave for the sky and a fresh one take its place without moving them.
    let anchor = Entity()
    /// This session's lantern. After release it flies into the sky and the
    /// sky keeps that very entity; a fresh dark lantern replaces it here.
    private(set) var lantern: ChargeObjectEntity
    let flow: EnergyFlow
    let sounds: SoundBank
    let visuals: StepVisuals
    let sky: LanternSky
    /// Nil unless config.tree.enabled and the lantern_tree slot has a file;
    /// then the sky's lanterns hang on it instead of floating in a cluster.
    let tree: LanternTree?
    /// Nil unless config.companion.enabled and the model slot has a file.
    let companion: CompanionEntity?
    private var lastStepId: String?
    /// Flight to the sky: when it started. The target is re-read every frame.
    private var riseStartedAt: TimeInterval?
    /// True only while this director writes the session record, so the sky
    /// update that write triggers can tell which record is the flying one.
    private var holdingNewest = false
    /// The record of the lantern in flight. The sky leaves it out until the
    /// lantern lands and is adopted, so there is never a copy waiting there.
    private var pendingRecord: SessionRecord?
    private var lastFrameAt: TimeInterval = 0
    private var headWasOnLantern = false

    init(controller: SessionController) {
        self.controller = controller
        let config = controller.sequence.config
        let assets = controller.assets
        ChargeObjectEntity.glowLevels = (dark: Float(config.lantern.glowDark), charging: Float(config.lantern.glowCharging),
                                   glance: Float(config.lantern.glowGlance), lit: Float(config.lantern.glowLit))
        func color(_ rgb: SIMD3<Float>) -> UIColor {
            UIColor(red: CGFloat(rgb.x), green: CGFloat(rgb.y), blue: CGFloat(rgb.z), alpha: 1)
        }
        ChargeObjectEntity.lightColors = (bottom: color(config.lantern.lightBottomRGB),
                                          top: color(config.lantern.lightTopRGB),
                                          glass: color(config.lantern.glassRGB))
        sounds = SoundBank(config: config.audio)
        let portSlot: AssetSlot = config.accessSite == .arm ? .portRing : .portPlate
        rig = PortRig(sparkleCount: config.visuals.frostSparkleCount, accessSite: config.accessSite,
                      plateSize: config.chestPort.plateSize, sleeveConfig: config.sleeve,
                      forearmRadius: config.forearm.forearmRadius, assets: assets,
                      glassMask: controller.sequence.assetOverride(portSlot.rawValue).glassMask)
        controller.noteSleeve(rig.sleeveTileUsed.map { config.sleeve.style == .glow ? $0 : "\($0) at \(config.sleeve.opacity)" } ?? "no tile; none")
        rig.root.isEnabled = false
        rig.root.addChild(sounds.portSource)
        anchor.name = "lanternAnchor"
        anchor.isEnabled = false
        anchor.addChild(sounds.lanternSource)
        lantern = ChargeObjectEntity(model: assets.model(.lanternHero))
        anchor.addChild(lantern.root)
        flow = EnergyFlow(config: config.visuals, cable: config.cable, assets: assets)
        visuals = StepVisuals(config: config.visuals, rig: rig, lantern: lantern, flow: flow)
        tree = LanternTree(assets: assets, config: config.tree)
        sky = LanternSky(config: config.sky, tree: tree == nil ? nil : config.tree,
                         treeModelScale: tree?.modelScale ?? 1,
                         lanternHeight: lantern.height, lanternTop: lantern.topY, assets: assets)
        if let tree {
            tree.frame.addChild(sky.root)
        } else {
            anchor.addChild(sky.root)
        }
        controller.noteTree(tree?.status ?? (config.tree.enabled ? "enabled but lantern_tree missing; floating sky" : "off; floating sky"))
        if config.companion.enabled,
           let c = CompanionEntity(assets: assets, config: config.companion) {
            if let tree {
                let t = config.tree.companion
                c.placeUnderTree(forward: Float(t.forwardM), sideOffset: Float(t.sideM), height: Float(t.heightM),
                                 heldArm: config.forearm.heldArm)
                tree.frame.addChild(c.root)
            } else {
                c.place(lanternBaseY: lantern.baseY, lanternHalfWidth: lantern.halfWidth, heldArm: config.forearm.heldArm)
                anchor.addChild(c.root)
            }
            companion = c
            controller.noteCompanion(c.status)
        } else {
            companion = nil
            controller.noteCompanion(config.companion.enabled ? "enabled but companion_model missing" : "off")
        }
        sky.show(controller.skySessions, now: CACurrentMediaTime())
        controller.onSkyChanged = { [weak self] sessions in self?.skyChanged(sessions) }
    }

    func attach(to content: RealityViewContent) {
        content.add(rig.root)
        content.add(anchor)
        tree?.attach(to: content)
        flow.attach(to: content)
    }

    func loadSounds() async {
        await sounds.load(ids: controller.sequence.audioIds)
        controller.noteAudio(sounds.status)
    }

    /// World-anchor the lantern once from the head pose (or the fallback).
    func placeLantern(head: simd_float4x4?) {
        anchor.transform = Transform(matrix: LanternPlacement.transform(
            head: head, config: controller.sequence.config.lantern, simulated: controller.isSimulatedForearm))
        anchor.isEnabled = true
        tree?.place(TreePlacement.transform(head: head, lantern: controller.sequence.config.lantern,
                                            tree: controller.sequence.config.tree,
                                            simulated: controller.isSimulatedForearm),
                    now: CACurrentMediaTime())
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
        tree?.update(now: now)
        if sky.isTree, TreeTouch.isActive(stepId: controller.currentStepId,
                                          steps: controller.sequence.steps.map(\.id),
                                          touch: controller.sequence.config.tree.touch) {
            sky.touch(points: controller.portSource.touchPoints(now: now), now: now)
        }
        sky.update(now: now)
        let rate = String(format: "%.0f/s", flow.rebuildsPerSecond)
        if rate != controller.cableStatus { controller.noteCable(rate) }
        if let companion {
            if tree != nil {
                // Under the tree it stands to one side; turn it to look at the child.
                let config = controller.sequence.config
                let head = controller.headPose.current().map { ForearmPoseSolver.translation(of: $0) }
                    ?? SIMD3(0, config.lantern.fallbackHeadHeight, 0)
                companion.face(head, maxStep: Float(config.tree.companion.turnDegPerSecond) * .pi / 180 * dt)
            }
            companion.update(now: now)
            if companion.status != controller.companionStatus { controller.noteCompanion(companion.status) }
        }
        let socket = lantern.root.convert(
            position: lantern.cableSocket(aboveCap: controller.sequence.config.visuals.cableSocketAboveCap), to: nil)
        visuals.update(now: now, charge: Float(state.charge),
                       isCharging: state.isCharging(in: controller.sequence),
                       portWorld: pose?.position, socketWorld: socket)
    }

    /// At release the current lantern flies to its place over
    /// config.sky.riseSeconds: a hook on the tree (arcing up on the way,
    /// shedding sparks) or the next cluster slot. The record is written as
    /// the flight starts, but the sky leaves it out until the lantern lands.
    /// On landing the sky adopts the flying lantern itself (no copy, no
    /// swap), the tree flares, and a fresh dark lantern waits, hidden, for
    /// the next session.
    private func updateRise(now: TimeInterval) {
        guard let riseStartedAt else { return }
        let u = Float(min(1, (now - riseStartedAt) / controller.sequence.config.sky.rise))
        // Ease in and out: it lifts off gently and settles onto its chain.
        let eased = u * u * (3 - 2 * u)
        flyLantern(eased: eased)
        if u >= 1 { land(now: now) }
    }

    /// Body toward the next sky slot, shrinking to the sky's scale and
    /// settling to the brightness the sky gives this record, so landing
    /// changes nothing on screen.
    private func flyLantern(eased: Float) {
        // Re-aimed every frame: the place moves only if the sky changed mid-flight.
        let target = lantern.root.convert(transform: sky.restTransform(sky.count), from: sky.root)
        let arc = sky.isTree ? Float(controller.sequence.config.tree.flightArcM) : 0
        lantern.body.position = TreePlacement.flight(from: .zero, to: target.translation, u: eased, arc: arc)
        lantern.body.orientation = simd_slerp(simd_quatf(angle: 0, axis: SIMD3(0, 1, 0)), target.rotation, eased)
        lantern.body.scale = SIMD3(repeating: 1) + (target.scale - SIMD3(repeating: 1)) * eased
        tree?.trail.setPosition(lantern.body.position(relativeTo: nil), relativeTo: nil)
        if let pendingRecord {
            lantern.setBrightness(1 - (1 - LanternSky.brightness(for: pendingRecord)) * eased)
        }
    }

    private func startRise(now: TimeInterval) {
        guard riseStartedAt == nil else { return }
        riseStartedAt = now
        tree?.trail.setPosition(lantern.body.position(relativeTo: nil), relativeTo: nil)
        tree?.setTrail(emitting: true)
        holdingNewest = true
        controller.sessionReleased()
        holdingNewest = false
    }

    private func skyChanged(_ sessions: [SessionRecord]) {
        if holdingNewest, let newest = sessions.last { pendingRecord = newest }
        let now = CACurrentMediaTime()
        if let pendingRecord {
            sky.show(sessions.filter { $0 != pendingRecord }, now: now)
        } else {
            sky.show(sessions, now: now)
        }
    }

    /// The flying lantern becomes the sky's lantern for its record. If the
    /// record never made it to the store (write failed, or the operator
    /// reset the sky mid-flight) it is not adopted and waits where it is
    /// until the next session brings it back.
    private func land(now: TimeInterval) {
        riseStartedAt = nil
        tree?.setTrail(emitting: false)
        guard let record = pendingRecord else { return }
        pendingRecord = nil
        guard controller.skySessions.contains(record) else {
            sky.show(controller.skySessions, now: now)
            return
        }
        sky.adopt(lantern, as: record, now: now)
        tree?.lanternLanded(at: lantern.root.position(relativeTo: nil), now: now)
        let fresh = ChargeObjectEntity(model: controller.assets.model(.lanternHero))
        fresh.root.isEnabled = false
        anchor.addChild(fresh.root)
        lantern = fresh
        visuals.lantern = fresh
    }

    /// Next session (idle or cream): a lantern still in flight lands at
    /// once, then the current lantern is shown dark at the anchor.
    private func resetRise() {
        if riseStartedAt != nil {
            flyLantern(eased: 1)
            land(now: CACurrentMediaTime())
        }
        lantern.body.position = .zero
        lantern.body.orientation = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
        lantern.body.scale = .one
        lantern.setBrightness(1)
        lantern.root.isEnabled = true
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
            let toLantern = anchor.position - headPos
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
        // A lantern still flying lands before the next session's visuals
        // touch the current lantern; release enters lit, then starts the rise.
        if stepId == SessionMarker.idle || stepId == StepID.cream { resetRise() }
        visuals.enter(stepId, at: now)
        if stepId == StepID.release { startRise(now: now) }
        if let companion {
            if stepId == SessionMarker.idle {
                companion.reset()
            } else if let step = controller.currentStep {
                if step.id != StepID.charge { companion.stopVariety() }
                companion.enter(step.companion ?? .idle, at: now)
            } else {
                companion.stopVariety()
                companion.enter(.idle, at: now)
            }
        }
        if let step = controller.currentStep {
            sounds.play(step.audio)
        } else {
            sounds.stopLoop()
        }
    }
}
