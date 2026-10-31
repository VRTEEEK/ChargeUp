import Foundation
import Testing
import simd
@testable import ChargeUpCore

@Suite struct TreeTests {
    @Test func shippedTreeDecodesWithHooks() throws {
        let tree = try ChargeSequence.shipped().config.tree
        #expect(tree.enabled)
        #expect(tree.hooks.count >= 20)
        #expect(tree.hooks.allSatisfy { $0.count == 4 })
    }

    @Test func treeStandsOnTheFloorAheadOfTheHeadFacingIt() throws {
        let seq = try ChargeSequence.shipped()
        var head = matrix_identity_float4x4
        head.columns.3 = SIMD4(0.3, 1.2, -0.1, 1)      // seated, looking down -Z
        let m = TreePlacement.transform(head: head, lantern: seq.config.lantern, tree: seq.config.tree)
        let p = SIMD3<Float>(m.columns.3.x, m.columns.3.y, m.columns.3.z)
        #expect(abs(p.y) < 1e-6, "base on the floor")
        #expect(abs(p.x - 0.3) < 1e-5)
        #expect(abs(p.z - (-0.1 - Float(seq.config.tree.forwardM))) < 1e-5)
        // Door (+Z) faces back toward the child.
        let door = SIMD3<Float>(m.columns.2.x, m.columns.2.y, m.columns.2.z)
        #expect(simd_dot(door, SIMD3(0, 0, 1)) > 0.999)
    }

    @Test func treeFollowsHeadYawAndSide() throws {
        let seq = try ChargeSequence.shipped()
        var tree = seq.config.tree
        tree.sideM = 0.5
        // Head turned 90 degrees left: looking down -X.
        let head = simd_float4x4(simd_quatf(angle: .pi / 2, axis: SIMD3(0, 1, 0)))
        let m = TreePlacement.transform(head: head, lantern: seq.config.lantern, tree: tree)
        let p = SIMD3<Float>(m.columns.3.x, m.columns.3.y, m.columns.3.z)
        #expect(abs(p.x - (-Float(tree.forwardM))) < 1e-5)
        #expect(abs(p.z - (-0.5)) < 1e-5, "the child's right is -Z when looking down -X")
    }

    @Test func hangsWrapOntoEarlierChainsBelowTheFirstRound() throws {
        let tree = try ChargeSequence.shipped().config.tree
        let n = tree.hooks.count
        let first = TreePlacement.hang(index: 0, tree: tree, modelScale: 2, hungLanternHeight: 0.1)
        let again = TreePlacement.hang(index: n, tree: tree, modelScale: 2, hungLanternHeight: 0.1)
        #expect(first.hook == again.hook)
        #expect(abs(again.drop - first.drop - (0.1 + Float(tree.stackGapMm) / 1000)) < 1e-6)
        #expect(abs(first.hook.y - Float(tree.hooks[0][1]) * 2) < 1e-6)
    }

    @Test func swayStartsAtRestAndStaysWithinAmplitude() throws {
        let tree = try ChargeSequence.shipped().config.tree
        #expect(TreePlacement.sway(age: 0, phase: 1.3, tree: tree) == 0)
        let amp = Float(tree.swayDeg * .pi / 180)
        for t in stride(from: 0.0, through: 20, by: 0.37) {
            #expect(abs(TreePlacement.sway(age: t, phase: 0.7, tree: tree)) <= amp + 1e-6)
        }
    }

    @Test func flightEndsExactlyAtTheHangingSpotAndBowsUp() {
        let a = SIMD3<Float>(0, 1, 0), b = SIMD3<Float>(1, 1.4, -1)
        #expect(TreePlacement.flight(from: a, to: b, u: 0, arc: 0.3) == a)
        #expect(simd_distance(TreePlacement.flight(from: a, to: b, u: 1, arc: 0.3), b) < 1e-6)
        #expect(TreePlacement.flight(from: a, to: b, u: 0.5, arc: 0.3).y > (a.y + b.y) / 2 + 0.29)
    }

    @Test func companionTurnsToFaceTheChildAtACappedRate() throws {
        // Tree frame: the child is 2.5 m out along +Z; the monkey stands
        // 1.1 m out and 0.55 m to the right, so it must turn left to look.
        let monkey = SIMD3<Float>(0.55, 0, 1.1), child = SIMD3<Float>(0, 1.2, 2.5)
        let full = TreePlacement.faceYaw(current: 0, position: monkey, target: child, maxStep: .pi)
        #expect(abs(full - atan2(-0.55, 1.4)) < 1e-5)
        let facing = SIMD3<Float>(sin(full), 0, cos(full))
        #expect(simd_dot(facing, simd_normalize(SIMD3<Float>(child.x - monkey.x, 0, child.z - monkey.z))) > 0.9999)
        // Capped: one small step the right way, never past the target.
        let step = TreePlacement.faceYaw(current: 0, position: monkey, target: child, maxStep: 0.05)
        #expect(abs(step + 0.05) < 1e-6)
        // The short way round across ±π, and a target overhead changes nothing.
        let behind = TreePlacement.faceYaw(current: 3.0, position: .zero, target: SIMD3(-0.1, 0, -1), maxStep: 1)
        #expect(behind > 3.0)
        #expect(TreePlacement.faceYaw(current: 0.4, position: .zero, target: SIMD3(0, 2, 0), maxStep: 1) == 0.4)
        #expect(try ChargeSequence.shipped().config.tree.companion.turnDegPerSecond > 0)
    }

    @Test func touchWorksFromTheInfusionOnAndNeverBeforeTheNeedle() throws {
        let seq = try ChargeSequence.shipped()
        let touch = seq.config.tree.touch, ids = seq.steps.map(\.id)
        #expect(touch.fromStep == StepID.charge)
        for id in [SessionMarker.idle, StepID.cream, StepID.clean, StepID.countdown, StepID.connect, StepID.flush] {
            #expect(!TreeTouch.isActive(stepId: id, steps: ids, touch: touch), "\(id)")
        }
        for id in [StepID.charge, StepID.release, SessionMarker.complete] {
            #expect(TreeTouch.isActive(stepId: id, steps: ids, touch: touch), "\(id)")
        }
    }

    @Test func aRestingHandPushesOnceUntilItMovesAway() throws {
        let touch = try ChargeSequence.shipped().config.tree.touch
        let r = Float(touch.radiusMm / 1000), rearm = Float(touch.rearmMm / 1000)
        var t = TreeTouch.Trigger()
        // Outside; enter; stay; just outside; back in; far enough; back in.
        let distances: [Float] = [r + 0.01, r - 0.01, r - 0.02, r + rearm / 2, r - 0.01, r + rearm + 0.01, r - 0.01]
        var fired: [Bool] = []
        for d in distances { fired.append(t.update(distance: d, touch: touch)) }
        #expect(fired == [false, true, false, false, false, false, true],
                "pushes on entering, not while resting or just outside, again only after moving well away")
    }

    @Test func aPushSwingsTheLanternAwayFromTheHandAndDiesDown() throws {
        let touch = try ChargeSequence.shipped().config.tree.touch
        // A hand on the lantern's -X side pushes it toward +X.
        let push = SIMD3<Float>(1, 0.3, 0)
        let axis = try #require(TreeTouch.swingAxis(push: push))
        let period = TreeTouch.period(length: 0.19)
        #expect(abs(period - 2 * .pi * sqrt(0.19 / 9.81)) < 1e-5)
        let quarter = TreeTouch.angle(age: Double(period) / 4, period: period, touch: touch)
        #expect(quarter > 0)
        let lantern = simd_quatf(angle: quarter, axis: axis).act(SIMD3<Float>(0, -0.19, 0))
        #expect(lantern.x > 0.02 && abs(lantern.z) < 1e-5, "moves along the push, not sideways")
        #expect(TreeTouch.angle(age: 0, period: period, touch: touch) == 0, "starts from rest")
        let late = TreeTouch.angle(age: touch.decaySeconds * 5 + Double(period) / 4, period: period, touch: touch)
        #expect(abs(late) < quarter * 0.01)
        #expect(!TreeTouch.hasSettled(age: touch.decaySeconds, touch: touch))
        #expect(TreeTouch.hasSettled(age: touch.decaySeconds * 6.1, touch: touch))
        #expect(TreeTouch.swingAxis(push: SIMD3(0, 1, 0)) == nil, "straight down onto it: no swing")
    }

    @Test func malformedHooksOrAMissingTreeFailToDecode() throws {
        let url = try #require(Bundle.module.url(forResource: "sequence", withExtension: "json"))
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        var config = json["config"] as! [String: Any]
        var tree = config["tree"] as! [String: Any]
        tree["hooks"] = [[1, 2]]
        config["tree"] = tree
        json["config"] = config
        #expect(throws: DecodingError.self) { try ChargeSequence.load(from: JSONSerialization.data(withJSONObject: json)) }
        config.removeValue(forKey: "tree")
        json["config"] = config
        #expect(throws: DecodingError.self) { try ChargeSequence.load(from: JSONSerialization.data(withJSONObject: json)) }
    }
}
