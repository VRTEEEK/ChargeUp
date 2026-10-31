import Foundation
import RealityKit
import ChargeUpCore

/// The companion character beside the lantern. One skinned model from
/// companion_model (its own clip is the breathing idle); the other clips
/// come from the companion_clip_* files and are played on that model by
/// retargeting, verified by a joint-transform probe with an entity-swap
/// fallback. Idle is a real loop and is the one clip that loops; every
/// other clip plays once at config.companion.speed (or its override) and
/// every change, including back into idle, cross-fades over crossfadeS.
/// Everything it does is a CompanionCue on a sequence row. It reacts to
/// nothing else.
@MainActor
final class CompanionEntity {
    enum Clip: String, CaseIterable {
        case idle, idleAlt, wave, listen, look, sway, fidget, heart, cheer

        var slot: AssetSlot? {
            switch self {
            case .idle: return nil   // the model's own clip
            case .idleAlt: return .companionClipIdleAlt
            case .wave: return .companionClipWave
            case .listen: return .companionClipListen
            case .look: return .companionClipLook
            case .sway: return .companionClipSway
            case .fidget: return .companionClipFidget
            case .heart: return .companionClipHeart
            case .cheer: return .companionClipCheer
            }
        }
    }

    private enum Phase: Equatable {
        case idle
        case fadingIn(started: TimeInterval)
        case playing(Clip, then: Next)
    }
    private enum Next: Equatable { case idle, cheer }
    private enum ClipMode { case retargeting, swapping }

    let root = Entity()
    private let config: CompanionConfig
    private var clipEntities: [Clip: Entity] = [:]
    private var clipResources: [Clip: AnimationResource] = [:]
    private let model: Entity
    private var shown: Entity
    private var mode: ClipMode = .retargeting
    private var controller: AnimationPlaybackController?
    private var phase: Phase = .idle
    private var probe: (clip: Clip, started: TimeInterval, before: [Transform])?
    private var side: Float = 1
    /// Turn about the vertical, toward the child; nil until first faced, so
    /// the first turn snaps instead of spinning in.
    private var yaw: Float?
    /// 0 = no variety, >0 = due at that time, -1 = a variety clip is running.
    private var nextVarietyAt: TimeInterval = 0
    private var lastVariety: Clip?
    private var fidgetsThisSession = 0
    private(set) var status = "off"

    /// Nil when the model slot is empty.
    init?(assets: AssetCatalog, config: CompanionConfig) {
        guard let model = assets.model(.companionModel) else { return nil }
        self.config = config
        self.model = model
        self.shown = model
        root.name = "companion"
        Self.fit(model, height: config.height)
        root.addChild(model)

        if let own = model.availableAnimations.first { clipResources[.idle] = own.repeat() }
        for clip in Clip.allCases {
            guard let slot = clip.slot, let entity = assets.model(slot) else { continue }
            if let res = entity.availableAnimations.first { clipResources[clip] = res }
            Self.fit(entity, height: config.height)
            entity.isEnabled = false
            root.addChild(entity)
            clipEntities[clip] = entity
        }
        root.components.set(OpacityComponent(opacity: 0))
        root.isEnabled = false
        status = "loaded, \(clipResources.count) clips, retargeting"
        AssetCatalog.logger.info("companion: clips \(self.clipResources.keys.map(\.rawValue).sorted().joined(separator: ","), privacy: .public)")
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

    /// Under the lantern tree (the caller parents it to the tree's frame):
    /// on the floor in front of the trunk, on the side away from the nurse,
    /// scaled up from config.heightM to `height` so it reads at that distance.
    func placeUnderTree(forward: Float, sideOffset: Float, height: Float, heldArm: HeldArm) {
        side = heldArm == .left ? 1 : -1
        root.scale = SIMD3(repeating: height / max(0.001, config.height))
        root.position = SIMD3(side * sideOffset, 0, forward)
    }

    /// Turn the body to face `target` (world space) across the floor, at
    /// most `maxStep` radians this call; the first call snaps. The clips play
    /// on underneath, so only the facing changes.
    func face(_ target: SIMD3<Float>, maxStep: Float) {
        guard let parent = root.parent else { return }
        let local = parent.convert(position: target, from: nil)
        let next = TreePlacement.faceYaw(current: yaw ?? 0, position: root.position, target: local,
                                         maxStep: yaw == nil ? .pi : maxStep)
        yaw = next
        root.orientation = simd_quatf(angle: next, axis: SIMD3(0, 1, 0))
    }

    // MARK: Cues

    func enter(_ cue: CompanionCue, at now: TimeInterval) {
        nextVarietyAt = 0
        switch cue {
        case .waveIn:
            root.isEnabled = true
            root.components[OpacityComponent.self]?.opacity = 0
            idle(now: now)
            phase = .fadingIn(started: now)
        case .idle:
            idle(now: now)
        case .listen:
            // Continues across steps that also say listen; do not restart it.
            if case .playing(.listen, _) = phase { return }
            play(.listen, then: .idle, at: now)
        case .lookOnce:
            play(.look, then: .idle, at: now)
        case .charging:
            idle(now: now)
            scheduleVariety(after: now)
        case .heartCheer:
            play(.heart, then: .cheer, at: now)
        }
    }

    func reset() {
        root.isEnabled = false
        yaw = nil
        root.components[OpacityComponent.self]?.opacity = 0
        nextVarietyAt = 0
        lastVariety = nil
        fidgetsThisSession = 0
        idle(now: 0)
    }

    /// The breathing loop, cross-faded in.
    private func idle(now: TimeInterval) {
        phase = .idle
        guard let res = clipResources[.idle] else { return }
        show(model)
        let c = model.playAnimation(res, transitionDuration: config.crossfadeS, startsPaused: false)
        c.speed = Float(config.speed(for: Clip.idle.rawValue))
        controller = c
    }

    private func play(_ clip: Clip, then next: Next, at now: TimeInterval) {
        guard let res = clipResources[clip] else { idle(now: now); return }
        let entity = entity(for: clip)
        show(entity)
        let c = entity.playAnimation(res, transitionDuration: config.crossfadeS, startsPaused: false)
        c.speed = Float(config.speed(for: clip.rawValue))
        controller = c
        phase = .playing(clip, then: next)
        if mode == .retargeting, entity === model {
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
        if case .fadingIn(let started) = phase {
            let u = Float(min(1, (now - started) / config.fadeS))
            root.components[OpacityComponent.self]?.opacity = u
            if u >= 1 { play(.wave, then: .idle, at: now) }
        }
        // Retargeting probe: 0.4 s into a foreign clip the pose must have changed.
        if let p = probe, now - p.started > 0.4 {
            probe = nil
            if Self.jointTransforms(of: model) == p.before, let own = clipEntities[p.clip] {
                mode = .swapping
                status = "loaded, \(clipResources.count) clips, swap fallback (retarget moved no joints)"
                AssetCatalog.logger.error("companion: clip \(p.clip.rawValue, privacy: .public) did not move the model's skeleton; switching to entity swap")
                if case .playing(let clip, let next) = phase, clip == p.clip, let res = clipResources[clip] {
                    let elapsed = controller?.time ?? 0
                    show(own)
                    let c = own.playAnimation(res, transitionDuration: 0, startsPaused: false)
                    c.time = elapsed
                    c.speed = Float(config.speed(for: clip.rawValue))
                    controller = c
                    phase = .playing(clip, then: next)
                }
            } else if mode == .retargeting {
                status = "loaded, \(clipResources.count) clips, retargeting works"
            }
        }
        if case .playing(_, let next) = phase, let c = controller, c.isComplete {
            switch next {
            case .idle:
                let wasVariety = nextVarietyAt < 0
                idle(now: now)
                if wasVariety { scheduleVariety(after: now) }
            case .cheer:
                play(.cheer, then: .idle, at: now)
            }
        }
        // Charge variety: one clip from the list, never the same twice running.
        if nextVarietyAt > 0, now >= nextVarietyAt, phase == .idle {
            var pool = config.chargeVariety.compactMap { Clip(rawValue: $0) }.filter { clipResources[$0] != nil }
            if fidgetsThisSession >= config.fidgetMaxPerSession { pool.removeAll { $0 == .fidget } }
            if pool.count > 1, let last = lastVariety { pool.removeAll { $0 == last } }
            if let pick = pool.randomElement() {
                if pick == .fidget { fidgetsThisSession += 1 }
                lastVariety = pick
                nextVarietyAt = -1
                play(pick, then: .idle, at: now)
            } else {
                nextVarietyAt = 0
            }
        }
    }

    private func scheduleVariety(after now: TimeInterval) {
        nextVarietyAt = now + Double.random(in: config.chargeVarietyEverySMin...config.chargeVarietyEverySMax)
    }

    /// Leaving the charge step: no more variety clips.
    func stopVariety() {
        if nextVarietyAt > 0 { nextVarietyAt = 0 }
    }
}
