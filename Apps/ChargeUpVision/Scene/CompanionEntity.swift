import Foundation
import RealityKit
import ChargeUpCore

/// The companion character beside the lantern. One skinned model from
/// companion_model; clips from the companion_clip_* files played on it.
/// If a clip from another file does not move this model's skeleton, the
/// clip's own entity (same mesh, same textures) is swapped in its place and
/// the operator window says so. Everything it does is a CompanionCue on a
/// sequence row; between rows it idles on the first frame of Agree with a
/// small procedural bob. Nothing here reacts to presence or charge.
@MainActor
final class CompanionEntity {
    enum Clip: CaseIterable { case agree, heart, cheer, spin
        var slot: AssetSlot {
            switch self {
            case .agree: return .companionClipAgree
            case .heart: return .companionClipHeart
            case .cheer: return .companionClipCheer
            case .spin: return .companionClipSpin
            }
        }
    }

    private enum Phase: Equatable {
        case idle
        case fadingIn(started: TimeInterval)
        case playing(Clip, then: Next)
        case frozen
    }
    private enum Next: Equatable { case idle, freeze, heart }
    private enum ClipMode { case retargeting, swapping }

    let root = Entity()
    private let yawNode = Entity()
    private let bobNode = Entity()
    private let config: CompanionConfig
    private let pulseSeconds: TimeInterval
    /// Per clip: the entity that renders it (the model for retargeting, the
    /// clip's own file for swapping) and the resource.
    private var clipEntities: [Clip: Entity] = [:]
    private var clipResources: [Clip: AnimationResource] = [:]
    private let model: Entity
    private var shown: Entity
    private var mode: ClipMode = .retargeting
    private var controller: AnimationPlaybackController?
    private var phase: Phase = .idle
    private var bobbing = true
    private var probe: (clip: Clip, started: TimeInterval, before: [Transform])?
    /// A controller started paused never evaluates its frame, so "hold this
    /// frame" plays for one tick and pauses on the next update.
    private var pendingHold: (controller: AnimationPlaybackController, time: TimeInterval)?
    private var turning = false
    private var nextTurnAt: TimeInterval = 0
    private var turnStartedAt: TimeInterval = 0
    private var side: Float = 1
    private(set) var status = "off"

    /// Nil when the model slot is empty.
    init?(assets: AssetCatalog, config: CompanionConfig, pulseSeconds: TimeInterval) {
        guard let model = assets.model(.companionModel) else { return nil }
        self.config = config
        self.pulseSeconds = pulseSeconds
        self.model = model
        self.shown = model
        root.name = "companion"
        root.addChild(bobNode)
        bobNode.addChild(yawNode)
        Self.fit(model, height: config.height)
        yawNode.addChild(model)

        // Clips: the model's own animation is Agree unless a separate agree file is present.
        if let own = model.availableAnimations.first { clipResources[.agree] = own }
        for clip in Clip.allCases {
            guard let entity = assets.model(clip.slot) else { continue }
            if let res = entity.availableAnimations.first { clipResources[clip] = res }
            Self.fit(entity, height: config.height)
            entity.isEnabled = false
            yawNode.addChild(entity)
            clipEntities[clip] = entity
        }
        root.components.set(OpacityComponent(opacity: 0))
        root.isEnabled = false
        status = "loaded, \(clipResources.count) clips, retargeting"
        AssetCatalog.logger.info("companion: clips \(self.clipResources.keys.map { "\($0)" }.sorted().joined(separator: ","), privacy: .public)")
    }

    /// Scale so the model stands `height` tall with its feet at the entity's y = 0.
    private static func fit(_ entity: Entity, height: Float) {
        let b = entity.visualBounds(relativeTo: nil)
        let h = max(0.001, b.max.y - b.min.y)
        let s = height / h
        entity.scale = SIMD3(repeating: s)
        entity.position = SIMD3(-b.center.x * s, -b.min.y * s, -b.center.z * s)
    }

    /// Beside the lantern on the side away from the nurse, feet on the lantern's base plane.
    func place(lanternBaseY: Float, lanternHalfWidth: Float, heldArm: HeldArm) {
        side = heldArm == .left ? 1 : -1
        let halfWidth = (model.visualBounds(relativeTo: nil).extents.x) / 2
        root.position = SIMD3(side * (lanternHalfWidth + config.gap + halfWidth), lanternBaseY, 0)
    }

    // MARK: Cues

    func enter(_ cue: CompanionCue, at now: TimeInterval) {
        switch cue {
        case .appear:
            root.isEnabled = true
            root.components[OpacityComponent.self]?.opacity = 0
            phase = .fadingIn(started: now)
            bobbing = true
            holdFirstFrame()
        case .idle:
            idle()
        case .agreeHold:
            bobbing = false
            play(.agree, speedToFit: pulseSeconds, then: .freeze, at: now)
        case .hold:
            break
        case .charging:
            idle()
            scheduleTurn(after: now)
        case .cheerHeart:
            bobbing = false
            play(.cheer, speedToFit: nil, then: .heart, at: now)
        }
    }

    func reset() {
        root.isEnabled = false
        root.components[OpacityComponent.self]?.opacity = 0
        turning = false
        phase = .idle
        holdFirstFrame()
    }

    private func idle() {
        phase = .idle
        bobbing = true
        turning = false
        holdFirstFrame()
    }

    /// First frame of Agree, paused.
    private func holdFirstFrame() {
        guard let agree = clipResources[.agree] else { return }
        show(model)
        let c = model.playAnimation(agree, transitionDuration: 0.15, startsPaused: false)
        c.time = 0
        controller = c
        pendingHold = (c, 0)
    }

    private func freezeLastFrame(_ clip: Clip) {
        guard let res = clipResources[clip] else { return }
        let entity = entity(for: clip)
        show(entity)
        let hold = max(0, res.definition.duration - 1.0 / 30)
        let c = entity.playAnimation(res, transitionDuration: 0, startsPaused: false)
        c.time = hold
        controller = c
        pendingHold = (c, hold)
        phase = .frozen
    }

    private func play(_ clip: Clip, speedToFit: TimeInterval?, then next: Next, at now: TimeInterval) {
        guard let res = clipResources[clip] else { idle(); return }
        let entity = entity(for: clip)
        show(entity)
        let c = entity.playAnimation(res, transitionDuration: 0.1, startsPaused: false)
        if let fit = speedToFit, fit > 0 { c.speed = Float(res.definition.duration / fit) }
        controller = c
        phase = .playing(clip, then: next)
        // Retargeting probe: a clip from another file must move this skeleton.
        if mode == .retargeting, clip != .agree, entity === model {
            probe = (clip, now, Self.jointTransforms(of: model))
        }
    }

    private func entity(for clip: Clip) -> Entity {
        if mode == .swapping, let own = clipEntities[clip] { return own }
        return model
    }

    private func show(_ entity: Entity) {
        guard entity !== shown else { return }
        shown.isEnabled = false
        entity.isEnabled = true
        shown = entity
    }

    /// The first skinned entity in the tree and its current joint transforms.
    private static func jointTransforms(of entity: Entity) -> [Transform] {
        if let poses = entity.components[SkeletalPosesComponent.self]?.poses.default {
            return Array(poses.jointTransforms)
        }
        for child in entity.children {
            let t = jointTransforms(of: child)
            if !t.isEmpty { return t }
        }
        return []
    }

    // MARK: Per frame

    func update(now: TimeInterval) {
        if let hold = pendingHold {
            pendingHold = nil
            hold.controller.time = hold.time
            hold.controller.pause()
        }
        // Fade in.
        if case .fadingIn(let started) = phase {
            let u = Float(min(1, (now - started) / config.fadeS))
            root.components[OpacityComponent.self]?.opacity = u
            if u >= 1 {
                phase = .idle
                play(.agree, speedToFit: nil, then: .idle, at: now)
            }
        }
        // Retargeting probe: 0.4 s into a foreign clip the pose must have changed.
        if let p = probe, now - p.started > 0.4 {
            probe = nil
            if Self.jointTransforms(of: model) == p.before, let own = clipEntities[p.clip] {
                mode = .swapping
                status = "loaded, \(clipResources.count) clips, swap fallback (retarget moved no joints)"
                AssetCatalog.logger.error("companion: clip \(String(describing: p.clip), privacy: .public) did not move the model's skeleton; switching to entity swap")
                // Restart the clip on its own entity, from where the model would be.
                if case .playing(let clip, let next) = phase, clip == p.clip, let res = clipResources[clip] {
                    let elapsed = controller?.time ?? 0
                    show(own)
                    let c = own.playAnimation(res, transitionDuration: 0, startsPaused: false)
                    c.time = elapsed
                    controller = c
                    phase = .playing(clip, then: next)
                }
            } else if mode == .retargeting {
                status = "loaded, \(clipResources.count) clips, retargeting works"
            }
        }
        // Clip completion.
        if case .playing(let clip, let next) = phase, let c = controller, c.isComplete {
            switch next {
            case .idle: idle()
            case .freeze: freezeLastFrame(clip)
            case .heart: play(.heart, speedToFit: nil, then: .idle, at: now)
            }
        }
        // Bob.
        let bob: Float = bobbing ? config.bobAmplitude * sin(Float(now / config.bobPeriodS) * 2 * .pi) : 0
        bobNode.position.y = bob
        // Slow turn toward the lantern during charge, then back.
        if turning {
            let t = now - turnStartedAt
            let d = config.turnDurationS, h = config.turnHoldS
            let u: Double
            if t < d { u = t / d } else if t < d + h { u = 1 } else if t < 2 * d + h { u = 1 - (t - d - h) / d } else { u = 0; turning = false; scheduleTurn(after: now) }
            let eased = Float(u * u * (3 - 2 * u))
            // The lantern is on the -side of the companion; face it by yawing a quarter turn.
            yawNode.orientation = simd_quatf(angle: -side * (.pi / 2) * eased, axis: SIMD3(0, 1, 0))
        } else if nextTurnAt > 0, now >= nextTurnAt, phase == .idle {
            turning = true
            turnStartedAt = now
        }
    }

    private func scheduleTurn(after now: TimeInterval) {
        nextTurnAt = now + Double.random(in: config.turnEverySMin...config.turnEverySMax)
    }

    func stopTurning() {
        nextTurnAt = 0
        turning = false
        yawNode.orientation = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
    }
}
