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
    /// One wave detector per hand (0 left, 1 right) and the answer chooser.
    private var waveDetectors: [Int: WaveDetector] = [:]
    private var waveResponder = CompanionResponder()
    /// Touching the monkey: one trigger for all hand points.
    private var companionTouch = TreeTouch.Trigger()
    /// Touch and pinch on the monkey share one cooldown: when it last played
    /// a random clip, and which.
    private var lastPlayAt: TimeInterval = -.infinity
    private var lastPlayClip: String?
    private var playRandom = SystemRandomNumberGenerator()
    /// The last chime a pinched lantern played, so the next is different.
    private var lastChime: String?
    /// Sparkles on what the child's head points at (LookSparkle): one
    /// emitter, moved to the picked lantern or the monkey.
    private let lookSparkle: Entity
    private var lookPicker = LookPicker()
    private var lookTarget: String?

    init(controller: SessionController) {
        self.controller = controller
        let config = controller.sequence.config
        let assets = controller.assets
        lookSparkle = Self.makeLookSparkle(config.lookSparkle)
        ChargeObjectEntity.glowLevels = (dark: Float(config.lantern.glowDark), charging: Float(config.lantern.glowCharging),
                                   glance: Float(config.lantern.glowGlance), lit: Float(config.lantern.glowLit))
        func color(_ rgb: SIMD3<Float>) -> UIColor {
            UIColor(red: CGFloat(rgb.x), green: CGFloat(rgb.y), blue: CGFloat(rgb.z), alpha: 1)
        }
        ChargeObjectEntity.lightColors = (bottom: color(config.lantern.lightBottomRGB),
                                          top: color(config.lantern.lightTopRGB),
                                          glass: color(config.lantern.glassRGB))
        let bank = SoundBank(config: config.audio, companionGainDb: config.companion.voiceGainDb,
                             chimeGainDb: config.tree.touch.pinchSoundGainDb)
        sounds = bank
        let portSlot: AssetSlot = config.accessSite == .arm ? .portRing : .portPlate
        rig = PortRig(visuals: config.visuals, look: config.port, accessSite: config.accessSite,
                      plateSize: config.chestPort.plateSize, sleeveConfig: config.sleeve,
                      forearmRadius: config.forearm.forearmRadius, assets: assets,
                      glassMask: controller.sequence.assetOverride(portSlot.rawValue).glassMask)
        controller.noteSleeve(config.sleeve.style == .none ? "none (port alone)"
                              : rig.sleeveTileUsed.map { config.sleeve.style == .glow ? $0 : "\($0) at \(config.sleeve.opacity)" } ?? "no tile; none")
        rig.root.isEnabled = false
        rig.root.addChild(sounds.portSource)
        anchor.name = "lanternAnchor"
        anchor.isEnabled = false
        anchor.addChild(sounds.lanternSource)
        anchor.addChild(sounds.musicSource)
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
            bank.companionSource.position = c.headTop
            c.root.addChild(bank.companionSource)
            let voices = config.companion.voices
            c.onClipStarted = { [weak bank] clip in bank?.playVoice(forClip: clip, voices: voices) }
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
        content.add(lookSparkle)
        content.add(sounds.chimeSource)
    }

    func loadSounds() async {
        let config = controller.sequence.config
        await sounds.load(ids: controller.sequence.audioIds + config.companion.voiceIds + config.tree.touch.pinchSounds)
        sounds.startMusic()
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
        let lanternsReachable = sky.isTree && TreeTouch.isActive(stepId: controller.currentStepId,
                                                                  steps: controller.sequence.steps.map(\.id),
                                                                  touch: controller.sequence.config.tree.touch)
        if lanternsReachable {
            sky.touch(points: controller.portSource.touchPoints(now: now), now: now)
        }
        sky.setPinchable(lanternsReachable && controller.sequence.config.tree.touch.pinch)
        updateLookSparkle(now: now)
        sky.update(now: now)
        let rate = String(format: "%.0f/s", flow.rebuildsPerSecond)
        if rate != controller.cableStatus { controller.noteCable(rate) }
        if let companion {
            answerWaves(companion, now: now)
            answerTouch(companion, now: now)
            let touch = controller.sequence.config.companion.touch
            companion.setPinchable(companion.isPresent && touch.pinch && touch.isActive(stepId: controller.currentStepId))
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
            position: lantern.streamTarget, to: nil)
        visuals.update(now: now, charge: Float(state.charge),
                       isCharging: state.isCharging(in: controller.sequence),
                       portWorld: pose?.position,
                       portUp: pose.map { $0.orientation.act(SIMD3<Float>(0, 1, 0)) } ?? SIMD3(0, 1, 0),
                       socketWorld: socket)
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

    /// The monkey waves back: each hand's side-to-side motion across the
    /// child's head goes through its own WaveDetector; a completed wave gets
    /// the next answer from the WaveResponder, unless the monkey is busy.
    /// Quiet on the countdown and the needle (config.companion.wave).
    private func answerWaves(_ companion: CompanionEntity, now: TimeInterval) {
        let wave = controller.sequence.config.companion.wave
        guard companion.isPresent, wave.isActive(stepId: controller.currentStepId),
              let head = controller.headPose.current() else {
            waveDetectors = [:]
            return
        }
        for (hand, centre) in controller.portSource.handCentres(now: now) {
            let m = WaveDetector.measure(hand: centre, head: head, config: wave)
            var detector = waveDetectors[hand] ?? WaveDetector()
            let waved = detector.observe(lateral: m.lateral, raised: m.raised, time: now, config: wave)
            waveDetectors[hand] = detector
            guard waved else { continue }
            var responder = waveResponder
            if let clip = responder.respond(at: now, config: wave), companion.answer(clip, at: now) {
                waveResponder = responder
            }
        }
    }

    /// Sparkles on the lantern or monkey the head points at. Lanterns are
    /// always candidates; the monkey while it is out and not on a quiet step.
    private func updateLookSparkle(now: TimeInterval) {
        let config = controller.sequence.config.lookSparkle
        guard config.enabled, let head = controller.headPose.current() else {
            setLookSparkle(nil, centre: .zero, radius: 0)
            return
        }
        let eye = ForearmPoseSolver.translation(of: head)
        let f = head.columns.2
        let forward = -SIMD3<Float>(f.x, f.y, f.z)
        var targets: [String: (centre: SIMD3<Float>, radius: Float)] = [:]
        if sky.isTree { for t in sky.lookTargets() { targets[t.key] = (t.centre, t.radius) } }
        if let companion, companion.isPresent,
           controller.sequence.config.companion.touch.isActive(stepId: controller.currentStepId) {
            let base = companion.root.position(relativeTo: nil)
            let height = companion.root.convert(position: companion.headTop, to: nil).y - base.y
            targets["monkey"] = (base + SIMD3(0, height / 2, 0), height / 2)
        }
        let offAxis = targets.mapValues { LookSparkleConfig.offAxis(head: eye, forward: forward, centre: $0.centre, radius: $0.radius) }
        let picked = lookPicker.update(offAxis: offAxis, time: now, config: config)
        if let picked, let t = targets[picked] {
            setLookSparkle(picked, centre: t.centre, radius: t.radius)
        } else {
            setLookSparkle(nil, centre: .zero, radius: 0)
        }
    }

    /// Moves the sparkle emitter onto the picked object every frame (so it
    /// follows a swinging lantern) and sizes it to the object on a change.
    /// Sparkles already shed stay where they are and fade.
    private func setLookSparkle(_ key: String?, centre: SIMD3<Float>, radius: Float) {
        guard var p = lookSparkle.components[ParticleEmitterComponent.self] else { return }
        if key != lookTarget {
            lookTarget = key
            if key != nil { p.emitterShapeSize = SIMD3(repeating: radius * 2) }
            p.isEmitting = key != nil
            lookSparkle.components.set(p)
        }
        if key != nil { lookSparkle.position = centre }
    }

    private static func makeLookSparkle(_ c: LookSparkleConfig) -> Entity {
        let e = Entity()
        e.name = "lookSparkle"
        var p = ParticleEmitterComponent()
        p.emitterShape = .sphere
        p.birthLocation = .surface
        p.birthDirection = .normal
        p.speed = Float(c.speedMmPerS / 1000)
        p.speedVariation = Float(c.speedMmPerS / 1000) * 0.5
        p.particlesInheritTransform = false
        p.isEmitting = false
        var m = p.mainEmitter
        m.birthRate = Float(c.perSecond)
        m.lifeSpan = c.life
        m.lifeSpanVariation = c.life * 0.3
        m.size = Float(c.sizeMm / 1000)
        m.sizeVariation = Float(c.sizeMm / 1000) * 0.4
        m.sizeMultiplierAtEndOfLifespan = 0.2
        m.color = .constant(.single(UIColor(red: CGFloat(c.rgb.x), green: CGFloat(c.rgb.y), blue: CGFloat(c.rgb.z), alpha: 1)))
        m.opacityCurve = .gradualFadeInOut
        m.blendMode = .additive
        m.billboardMode = .billboard
        m.noiseStrength = 0.01
        m.noiseScale = 1
        m.noiseAnimationSpeed = 0.3
        m.isLightingEnabled = false
        p.mainEmitter = m
        e.components.set(p)
        return e
    }

    /// Look and pinch: on a hung lantern it swings away from the child; on
    /// the monkey it plays a random clip, never the same twice running, at
    /// most once per config.companion.touch.cooldownMs.
    func pinch(_ entity: Entity) {
        let now = CACurrentMediaTime()
        if let companion, companion.contains(entity) {
            let touch = controller.sequence.config.companion.touch
            guard companion.isPresent, touch.pinch, touch.isActive(stepId: controller.currentStepId) else { return }
            playRandomClip(companion, now: now)
            return
        }
        let head = controller.headPose.current().map { ForearmPoseSolver.translation(of: $0) }
            ?? SIMD3(0, controller.sequence.config.lantern.fallbackHeadHeight, 0)
        if let centre = sky.pinch(entity, head: head, now: now),
           let chime = controller.sequence.config.tree.touch.randomPinchSound(after: lastChime, using: &playRandom) {
            lastChime = chime
            sounds.playChime(chime, at: centre)
        }
    }

    /// Touching the monkey: a fingertip or knuckle reaching its body (a
    /// standing capsule from its feet to the top of its head) plays the next
    /// cute clip, once until the hand moves away (config.companion.touch).
    private func answerTouch(_ companion: CompanionEntity, now: TimeInterval) {
        let touch = controller.sequence.config.companion.touch
        guard companion.isPresent, touch.isActive(stepId: controller.currentStepId) else {
            companionTouch = TreeTouch.Trigger()
            return
        }
        let points = controller.portSource.touchPoints(now: now)
        guard !points.isEmpty else { return }
        let base = companion.root.position(relativeTo: nil)
        let height = companion.root.convert(position: companion.headTop, to: nil).y - base.y
        let radius = height * Float(touch.bodyRadius)
        let nearest = points.map { CompanionTouchConfig.distanceToBody($0, base: base, height: height, radius: radius) }.min() ?? .infinity
        guard companionTouch.update(distance: nearest, radius: Float(touch.marginMm / 1000), rearm: Float(touch.rearmMm / 1000)) else { return }
        playRandomClip(companion, now: now)
    }

    /// Touch and pinch: a random clip, never the same twice running, at
    /// most once per config.companion.touch.cooldownMs across both.
    private func playRandomClip(_ companion: CompanionEntity, now: TimeInterval) {
        let touch = controller.sequence.config.companion.touch
        guard now - lastPlayAt >= touch.cooldown,
              let clip = touch.randomResponse(after: lastPlayClip, using: &playRandom),
              companion.answer(clip, at: now) else { return }
        lastPlayAt = now
        lastPlayClip = clip
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
        sounds.setMusic(forStep: stepId)
    }
}
