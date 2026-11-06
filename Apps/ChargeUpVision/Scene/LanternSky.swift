import Foundation
import RealityKit
import UIKit
import ChargeUpCore

/// Past sessions, one lit lantern each, in a fixed place per index so the
/// same sky looks the same every visit. No text.
///
/// With the lantern tree (config.tree.enabled and the model present) each
/// lantern hangs on a chain from one of the tree's hooks and swings gently;
/// `root` is a child of the tree's frame. Without it, the fallback is the
/// floating cluster above and behind the current lantern (config.sky), and
/// `root` is a child of the lantern anchor.
@MainActor
final class LanternSky {
    let root = Entity()
    private let config: SkyConfig
    private let tree: TreeConfig?
    private let treeModelScale: Float
    /// Height of a lantern at scale 1 and the distance from its origin up to the ring top.
    private let lanternHeight: Float
    private let lanternTop: Float
    private let assets: AssetCatalog
    private let chainMaterial: PhysicallyBasedMaterial

    private struct Entry {
        /// At the hook (tree) or the slot (cluster). Swings about its own origin.
        let hanger: Entity
        let lantern: ChargeObjectEntity
        let chain: ModelEntity?
        let chainLength: Float
        /// Hook to the lantern's centre: the pendulum length for a touch.
        let drop: Float
        /// When it was hung, for the swing ramp and the chain growing down.
        let hungAt: TimeInterval
        let growsChain: Bool
        let phase: Double
        let swingAxis: SIMD3<Float>
    }
    private var entries: [Entry] = []
    /// Per entry, same order: the touch trigger and the swing a touch started.
    private struct Touch {
        var trigger = TreeTouch.Trigger()
        var startedAt: TimeInterval?
        var axis = SIMD3<Float>(1, 0, 0)
    }
    private var touches: [Touch] = []
    /// The record each entry shows, in the same order.
    private var records: [SessionRecord] = []

    init(config: SkyConfig, tree: TreeConfig?, treeModelScale: Float,
         lanternHeight: Float, lanternTop: Float, assets: AssetCatalog) {
        self.config = config
        self.tree = tree
        self.treeModelScale = treeModelScale
        self.lanternHeight = lanternHeight
        self.lanternTop = lanternTop
        self.assets = assets
        root.name = tree == nil ? "lanternSky" : "lanternTreeHangings"
        var chain = PhysicallyBasedMaterial()
        let rgb = tree?.chainColorRGB ?? SIMD3(0.85, 0.64, 0.26)
        let color = UIColor(red: CGFloat(rgb.x), green: CGFloat(rgb.y), blue: CGFloat(rgb.z), alpha: 1)
        chain.baseColor = .init(tint: color)
        chain.metallic = 0.9
        chain.roughness = 0.3
        chain.emissiveColor = .init(color: color)
        chain.emissiveIntensity = 0.4
        chainMaterial = chain
    }

    var count: Int { entries.count }
    var isTree: Bool { tree != nil }
    /// Scale of a hung or clustered lantern relative to the current one.
    var lanternScale: Float { Float(tree?.lanternScale ?? config.smallScale) }

    /// Where the hanger for `index` sits and how far below it the lantern's
    /// origin hangs, in `root`'s frame.
    private func hang(_ index: Int) -> (hanger: SIMD3<Float>, drop: Float, chain: Float) {
        guard let tree else { return (clusterSlot(index), 0, 0) }
        let s = lanternScale
        let (hook, chain) = TreePlacement.hang(index: index, tree: tree, modelScale: treeModelScale,
                                               hungLanternHeight: lanternHeight * s)
        return (hook, chain + lanternTop * s, chain)
    }

    /// The resting transform of lantern `index`'s root in `root`'s frame:
    /// where a lantern flying in must end so that hanging it changes nothing.
    func restTransform(_ index: Int) -> Transform {
        let h = hang(index)
        return Transform(scale: SIMD3(repeating: lanternScale), rotation: simd_quatf(angle: 0, axis: SIMD3(0, 1, 0)),
                         translation: h.hanger - SIMD3(0, h.drop, 0))
    }

    /// The floating cluster: alternate left and right, climb slowly, drift back.
    private func clusterSlot(_ index: Int) -> SIMD3<Float> {
        let i = Float(index)
        let side: Float = index % 2 == 0 ? -1 : 1
        let ring = Float(index / 2)
        let x = side * (0.12 + 0.11 * ring) * Float(config.clusterSpreadM) / 0.7
        let y = Float(config.clusterHeightM) + 0.07 * ring + 0.025 * sin(i * 1.7)
        let z = -Float(config.clusterBehindM) - 0.06 * ring + 0.02 * cos(i * 2.3)
        return SIMD3(x, y, z)
    }

    /// Sky brightness for a record: a session that ended early is a dimmer
    /// lantern, honestly.
    static func brightness(for session: SessionRecord) -> Float {
        Float(max(0.35, session.fill))
    }

    /// A record whose variant names a slot gets that model; "lantern" uses
    /// the light lantern_small if present, else cycles through the three
    /// variants; anything missing falls back to the hero model, then to the
    /// placeholder.
    private func model(for session: SessionRecord, index: Int) -> Entity? {
        if let slot = AssetSlot(rawValue: session.variant), let m = assets.model(slot) { return m }
        if let m = assets.model(.lanternSmall) { return m }
        let variants = AssetSlot.lanternVariants
        if let m = assets.model(variants[index % variants.count]) { return m }
        return assets.model(.lanternHero)
    }

    /// Show exactly these records. Lanterns already showing the same records
    /// in the same order are kept as they are (so a lantern that flew in
    /// stays the very same entity); anything else rebuilds.
    func show(_ sessions: [SessionRecord], now: TimeInterval) {
        if sessions == records { return }
        if sessions.count > records.count, Array(sessions.prefix(records.count)) == records {
            for session in sessions.dropFirst(records.count) {
                hangNew(ChargeObjectEntity(model: model(for: session, index: entries.count)), as: session,
                        now: now, landing: false)
            }
            return
        }
        for e in entries { e.hanger.removeFromParent() }
        entries = []
        touches = []
        records = []
        for session in sessions {
            hangNew(ChargeObjectEntity(model: model(for: session, index: entries.count)), as: session,
                    now: now, landing: false)
        }
    }

    /// The lantern that just flew in becomes the sky's lantern for `session`
    /// at the next place: re-parented under a new hanger with its transform
    /// folded from body to root, so nothing on screen moves and no copy is
    /// made. The caller has flown `lantern.body` to `restTransform(count)`.
    /// On the tree its chain then grows down from the hook to the ring and
    /// its swing eases in from rest.
    func adopt(_ lantern: ChargeObjectEntity, as session: SessionRecord, now: TimeInterval) {
        lantern.root.removeFromParent()
        lantern.body.position = .zero
        lantern.body.orientation = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
        lantern.body.scale = .one
        hangNew(lantern, as: session, now: now, landing: true)
    }

    private func hangNew(_ lantern: ChargeObjectEntity, as session: SessionRecord, now: TimeInterval, landing: Bool) {
        let index = entries.count
        let h = hang(index)
        let hanger = Entity()
        hanger.name = "hanger\(index)"
        hanger.position = h.hanger
        lantern.root.position = SIMD3(0, -h.drop, 0)
        lantern.root.orientation = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
        lantern.root.scale = SIMD3(repeating: lanternScale)
        lantern.glance = 0
        lantern.apply(.lit)
        lantern.setBrightness(Self.brightness(for: session))
        lantern.root.name = "skyLantern\(index)"
        if let tree, tree.touch.pinch {
            // A target round the lantern for look and pinch, scaled with it.
            // No hover highlight: it paled the lantern; LookSparkle answers
            // looking instead, with sparkles, never changing the lantern.
            let radius = Float(tree.touch.pinchTargetMm / 1000) / lanternScale
            lantern.root.components.set(CollisionComponent(shapes: [.generateSphere(radius: radius)]))
            var input = InputTargetComponent()
            input.isEnabled = pinchable
            lantern.root.components.set(input)
        }
        hanger.addChild(lantern.root)

        var chain: ModelEntity?
        if tree != nil, let radius = tree.map({ Float($0.chainMm) / 2000 }), h.chain > 0.001 {
            let c = ModelEntity(mesh: .generateCylinder(height: h.chain, radius: radius), materials: [chainMaterial])
            c.name = "chain\(index)"
            c.position = SIMD3(0, -h.chain / 2, 0)
            if landing { c.scale = SIMD3(1, 0.001, 1) }
            hanger.addChild(c)
            chain = c
        }
        root.addChild(hanger)
        // Deterministic per index: each lantern swings in its own plane and time.
        let phase = Double(index) * 2.399
        let a = Float(phase)
        // Stored lanterns have been hanging a long while: full swing at once.
        let hungAt = landing ? now : now - 3600 - Double(index)
        entries.append(Entry(hanger: hanger, lantern: lantern, chain: chain, chainLength: h.chain, drop: h.drop,
                             hungAt: hungAt, growsChain: landing, phase: phase,
                             swingAxis: SIMD3(cos(a), 0, sin(a))))
        touches.append(Touch())
        records.append(session)
    }

    /// Every hung lantern as a look target: a stable key, its centre in the
    /// world, and its radius.
    func lookTargets() -> [(key: String, centre: SIMD3<Float>, radius: Float)] {
        let radius = lanternHeight * lanternScale / 2
        return entries.enumerated().map { ("lantern\($0.offset)", $0.element.lantern.body.position(relativeTo: nil), radius) }
    }

    /// Whether the lanterns take look and pinch now (only while touch is active).
    private var pinchable = false

    func setPinchable(_ on: Bool) {
        guard on != pinchable else { return }
        pinchable = on
        for e in entries {
            guard var input = e.lantern.root.components[InputTargetComponent.self] else { continue }
            input.isEnabled = on
            e.lantern.root.components.set(input)
        }
    }

    /// A pinch on `entity` (a hung lantern or part of one): it swings away
    /// from the child's head, the same swing as a touch. Returns the
    /// lantern's centre in the world, or nil if it was not a hung lantern.
    func pinch(_ entity: Entity, head: SIMD3<Float>, now: TimeInterval) -> SIMD3<Float>? {
        guard pinchable else { return nil }
        var node: Entity? = entity
        var index: Int?
        while let n = node, index == nil {
            index = entries.firstIndex { $0.lantern.root === n }
            node = n.parent
        }
        guard let i = index else { return nil }
        let centre = entries[i].lantern.body.position(relativeTo: nil)
        let push = root.convert(direction: centre - head, from: nil)
        guard let axis = TreeTouch.swingAxis(push: push) else { return nil }
        touches[i].axis = axis
        touches[i].startedAt = now
        return centre
    }

    /// Per frame while touch is active (config.tree.touch): a hand point
    /// reaching a lantern pushes it away from the hand. `points` are world
    /// positions; the caller decides when touch is active. Returns the world
    /// centre of each lantern newly pushed this frame (its chime plays there).
    @discardableResult
    func touch(points: [SIMD3<Float>], now: TimeInterval) -> [SIMD3<Float>] {
        guard let tree, !points.isEmpty else { return [] }
        var pushed: [SIMD3<Float>] = []
        for i in entries.indices {
            let centre = entries[i].lantern.body.position(relativeTo: nil)
            guard let nearest = points.min(by: { simd_distance($0, centre) < simd_distance($1, centre) }) else { continue }
            guard touches[i].trigger.update(distance: simd_distance(nearest, centre), touch: tree.touch) else { continue }
            // The swing axis lives in the hanger's frame, which is upright like the tree.
            let push = root.convert(direction: centre - nearest, from: nil)
            guard let axis = TreeTouch.swingAxis(push: push) else { continue }
            touches[i].axis = axis
            touches[i].startedAt = now
            pushed.append(centre)
        }
        return pushed
    }

    /// Per frame on the tree: swing every lantern about its hook, plus any
    /// touch swing on top, and grow any new chain down from the hook.
    /// Nothing moves in the cluster.
    func update(now: TimeInterval) {
        guard let tree else { return }
        for (i, e) in entries.enumerated() {
            let age = now - e.hungAt
            var orientation = simd_quatf(angle: TreePlacement.sway(age: age, phase: e.phase, tree: tree), axis: e.swingAxis)
            if let started = touches[i].startedAt {
                let t = now - started
                if TreeTouch.hasSettled(age: t, touch: tree.touch) {
                    touches[i].startedAt = nil
                } else {
                    let swing = TreeTouch.angle(age: t, period: TreeTouch.period(length: e.drop), touch: tree.touch)
                    orientation = simd_quatf(angle: swing, axis: touches[i].axis) * orientation
                }
            }
            e.hanger.orientation = orientation
            if e.growsChain, let chain = e.chain, age <= tree.chainGrowSeconds + 0.1 {
                let g = tree.chainGrowSeconds > 0 ? Float(min(1, age / tree.chainGrowSeconds)) : 1
                chain.scale = SIMD3(1, max(0.001, g), 1)
                chain.position = SIMD3(0, -e.chainLength * g / 2, 0)
            }
        }
    }
}
