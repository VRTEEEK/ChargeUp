import Foundation
import RealityKit
import ChargeUpCore

/// The companion character beside the lantern, one of
/// config.companion.characters at a time, starting each session on the first.
/// One skinned model per character (its own clip is the breathing idle); the
/// other clips come from the character's clip files and are played on that
/// model by retargeting, verified by a joint-transform probe with an
/// entity-swap fallback. Idle is a real loop and is the one clip that loops;
/// every other clip plays once at config.companion.speed (or its override),
/// a clip the character lacks plays as idle, and every change, including back
/// into idle, cross-fades over crossfadeS.
/// Everything it does is a CompanionCue on a sequence row, with two
/// exceptions: it waves back when the child waves (config.companion.wave)
/// and plays or changes character when touched (config.companion.touch),
/// except on the countdown and the needle.
@MainActor
final class CompanionEntity {
    typealias Clip = CompanionClip

    /// One character, loaded and fitted; only the current one is enabled.
    @MainActor
    private final class Body {
        let character: CompanionCharacter
        let model: Entity
        var clipEntities: [Clip: Entity] = [:]
        var clipResources: [Clip: AnimationResource] = [:]
        var shown: Entity
        var mode: ClipMode = .retargeting
        var status = ""

        /// Nil when the character's model file is absent.
        init?(_ character: CompanionCharacter, assets: AssetCatalog, height: Float) {
            guard let model = assets.characterModel(character.model) else { return nil }
            self.character = character
            self.model = model
            self.shown = model
            CompanionEntity.fit(model, height: height)
            if let own = model.availableAnimations.first { clipResources[.idle] = own.repeat() }
            for (clip, file) in character.clipFiles {
                guard let entity = assets.characterModel(file) else { continue }
                if let res = entity.availableAnimations.first { clipResources[clip] = res }
                CompanionEntity.fit(entity, height: height)
                entity.isEnabled = false
                clipEntities[clip] = entity
            }
            status = "loaded, \(clipResources.count) clips, retargeting"
        }

        /// Off, with the model on top for when it comes back.
        func hide() {
            shown.stopAllAnimations()
            shown.isEnabled = false
            model.isEnabled = false
            shown = model
        }
    }

    /// A change of character under way: fading out toward `to`, or, once
    /// that is nil, the new one fading in.
    private struct Switching {
        var to: Int?
        var started: TimeInterval
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
    private let cast: [Body]
    private var current = 0
    private var body: Body { cast[current] }
    private var switching: Switching?
    /// The release row's heart and cheer are running; nothing cuts in.
    private var celebrating = false
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
    var status: String { "\(body.character.name), \(cast.count) of \(config.characters.count) characters, \(body.status)" }
    /// The current character's voices, by clip name.
    var voices: [String: [String]] { body.character.voices ?? [:] }

    /// Nil when no character's model file is there.
    init?(assets: AssetCatalog, config: CompanionConfig) {
        let cast = config.characters.compactMap { Body($0, assets: assets, height: config.height) }
        guard !cast.isEmpty else { return nil }
        self.config = config
        self.cast = cast
        root.name = "companion"
        for (index, body) in cast.enumerated() {
            root.addChild(body.model)
            for entity in body.clipEntities.values { root.addChild(entity) }
            body.model.isEnabled = index == 0
        }
        root.components.set(OpacityComponent(opacity: 0))
        // Look and pinch target: a capsule standing over its body, in the
        // model's own units (the root scales it with the monkey). No hover
        // highlight (it paled the monkey); LookSparkle answers looking.
        // Off until setPinchable.
        if config.touch.pinch {
            let height = config.height, radius = config.height * Float(config.touch.bodyRadius)
            let capsule = ShapeResource.generateCapsule(height: height, radius: radius)
                .offsetBy(translation: SIMD3(0, height / 2, 0))
            root.components.set(CollisionComponent(shapes: [capsule]))
            var input = InputTargetComponent()
            input.isEnabled = false
            root.components.set(input)
        }
        root.isEnabled = false
        for body in cast {
            AssetCatalog.logger.info("companion \(body.character.name, privacy: .public): clips \(body.clipResources.keys.map(\.rawValue).sorted().joined(separator: ","), privacy: .public)")
        }
    }

    /// Scale so the model stands `height` tall with its feet at the entity's y = 0.
    fileprivate static func fit(_ entity: Entity, height: Float) {
        let b = entity.visualBounds(relativeTo: nil)
        let h = max(0.001, b.max.y - b.min.y)
        let s = height / h
        entity.scale = SIMD3(repeating: s)
        entity.position = SIMD3(-b.center.x * s, -b.min.y * s, -b.center.z * s)
    }

    /// Beside the lantern on the side away from the nurse, feet on the lantern's base plane.
    func place(lanternBaseY: Float, lanternHalfWidth: Float, heldArm: HeldArm) {
        side = heldArm == .left ? 1 : -1
        let halfWidth = (body.model.visualBounds(relativeTo: nil).extents.x) / 2
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
        celebrating = false
        // The row wins: a change of character still fading stops where it is.
        if switching != nil {
            switching = nil
            root.components[OpacityComponent.self]?.opacity = 1
        }
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
            celebrating = true
            play(.heart, then: .cheer, at: now)
        }
    }

    func reset() {
        root.isEnabled = false
        yaw = nil
        switching = nil
        wear(0)
        root.components[OpacityComponent.self]?.opacity = 0
        nextVarietyAt = 0
        lastVariety = nil
        fidgetsThisSession = 0
        idle(now: 0)
    }

    /// The breathing loop, cross-faded in.
    private func idle(now: TimeInterval) {
        phase = .idle
        celebrating = false
        guard let res = body.clipResources[.idle] else { return }
        show(body.model)
        let c = body.model.playAnimation(res, transitionDuration: config.crossfadeS, startsPaused: false)
        c.speed = Float(config.speed(for: Clip.idle.rawValue))
        controller = c
    }

    private func play(_ wanted: Clip, then next: Next, at now: TimeInterval) {
        let clip = wanted.orIdle(in: Set(body.clipResources.keys))
        guard clip != .idle, let res = body.clipResources[clip] else { idle(now: now); return }
        let entity = entity(for: clip)
        show(entity)
        let c = entity.playAnimation(res, transitionDuration: config.crossfadeS, startsPaused: false)
        c.speed = Float(config.speed(for: clip.rawValue))
        controller = c
        phase = .playing(clip, then: next)
        onClipStarted?(clip.rawValue)
        if body.mode == .retargeting, entity === body.model {
            probe = (clip, now, Self.jointTransforms(of: body.model))
        }
    }

    private func entity(for clip: Clip) -> Entity {
        if body.mode == .swapping, let own = body.clipEntities[clip] { return own }
        return body.model
    }

    private func show(_ entity: Entity) {
        guard entity !== body.shown else { return }
        body.shown.isEnabled = false
        entity.isEnabled = true
        body.shown = entity
    }

    /// Puts on character `index`, not fading, with no clip running yet.
    private func wear(_ index: Int) {
        guard index != current else { return }
        body.hide()
        probe = nil
        current = index
        body.model.isEnabled = true
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
        if let s = switching {
            let u = Float(min(1, (now - s.started) / config.switchFadeS))
            root.components[OpacityComponent.self]?.opacity = s.to == nil ? u : 1 - u
            if u >= 1 {
                if let to = s.to {
                    let charging = nextVarietyAt != 0
                    wear(to)
                    idle(now: now)
                    if charging { scheduleVariety(after: now) }
                    switching = Switching(to: nil, started: now)
                } else {
                    switching = nil
                }
            }
        }
        if case .fadingIn(let started) = phase {
            let u = Float(min(1, (now - started) / config.fadeS))
            root.components[OpacityComponent.self]?.opacity = u
            if u >= 1 { play(.wave, then: .idle, at: now) }
        }
        // Retargeting probe: 0.4 s into a foreign clip the pose must have changed.
        if let p = probe, now - p.started > 0.4 {
            probe = nil
            if Self.jointTransforms(of: body.model) == p.before, let own = body.clipEntities[p.clip] {
                body.mode = .swapping
                body.status = "loaded, \(body.clipResources.count) clips, swap fallback (retarget moved no joints)"
                AssetCatalog.logger.error("companion: clip \(p.clip.rawValue, privacy: .public) did not move the model's skeleton; switching to entity swap")
                if case .playing(let clip, let next) = phase, clip == p.clip, let res = body.clipResources[clip] {
                    let elapsed = controller?.time ?? 0
                    show(own)
                    let c = own.playAnimation(res, transitionDuration: 0, startsPaused: false)
                    c.time = elapsed
                    c.speed = Float(config.speed(for: clip.rawValue))
                    controller = c
                    phase = .playing(clip, then: next)
                }
            } else if body.mode == .retargeting {
                body.status = "loaded, \(body.clipResources.count) clips, retargeting works"
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
            var pool = config.chargeVariety.compactMap { Clip(rawValue: $0) }.filter { body.clipResources[$0] != nil }
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

    /// Told the name of each clip as it starts (not the idle loop), for its voice.
    var onClipStarted: ((String) -> Void)?
    /// Where its voice comes from: the top of its head, in the root's frame.
    var headTop: SIMD3<Float> { SIMD3(0, config.height, 0) }

    /// Turns look and pinch on or off.
    func setPinchable(_ on: Bool) {
        guard var input = root.components[InputTargetComponent.self], input.isEnabled != on else { return }
        input.isEnabled = on
        root.components.set(input)
    }

    /// Whether `entity` is the companion or part of it.
    func contains(_ entity: Entity) -> Bool {
        var node: Entity? = entity
        while let n = node {
            if n === root { return true }
            node = n.parent
        }
        return false
    }

    /// On the arm's side of the scene and visible: a session is running.
    var isPresent: Bool { root.isEnabled }

    /// Answers the child's wave or touch with `clipName` if it can: not while it is
    /// still walking in, and not over the celebration (heart, cheer); it
    /// may cut in on idle, a variety clip, listening or looking. Returns
    /// false when it did not answer, so the wave is not spent. A clip this
    /// character lacks is answered with idle.
    func answer(_ clipName: String, at now: TimeInterval) -> Bool {
        guard let clip = Clip(rawValue: clipName), switching == nil else { return false }
        switch phase {
        case .fadingIn: return false
        case .playing(let current, let next):
            if current == .heart || current == .cheer || next == .cheer { return false }
        case .idle: break
        }
        play(clip, then: .idle, at: now)
        return true
    }

    /// Fades to the character `step` places along the list (CompanionSwitch)
    /// and on into idle: not while it is walking in, over the celebration or
    /// already changing, and only if there is another character.
    func switchCharacter(by step: Int, at now: TimeInterval) {
        guard cast.count > 1, switching == nil, !celebrating else { return }
        if case .fadingIn = phase { return }
        switching = Switching(to: CompanionSwitch.index(from: current, by: step, count: cast.count), started: now)
    }

    /// Leaving the charge step: no more variety clips.
    func stopVariety() {
        if nextVarietyAt > 0 { nextVarietyAt = 0 }
    }
}
