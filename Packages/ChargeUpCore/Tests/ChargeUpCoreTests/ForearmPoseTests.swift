import Foundation
import Testing
import simd
@testable import ChargeUpCore

@Suite struct ForearmPoseTests {
    let config = try! ChargeSequence.shipped().config.forearm

    private func transform(at p: SIMD3<Float>, rotation: simd_float3x3 = matrix_identity_float3x3) -> simd_float4x4 {
        var m = matrix_identity_float4x4
        m.columns.0 = SIMD4(rotation.columns.0, 0)
        m.columns.1 = SIMD4(rotation.columns.1, 0)
        m.columns.2 = SIMD4(rotation.columns.2, 0)
        m.columns.3 = SIMD4(p, 1)
        return m
    }

    private func close(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ eps: Float = 1e-4) -> Bool {
        simd_length(a - b) < eps
    }

    @Test func configIsShipped() {
        #expect(config.heldArm == .left)
        #expect(config.portOffsetProximalMm == 60)
        #expect(config.forearmRadiusMm == 25)
        #expect(config.dorsalAxis == SignedAxis(axis: .y, sign: 1))
        #expect(config.holdLastPoseMs == 2000)
        #expect(config.occludedOpacity == 0.5)
    }

    @Test func badAxisFails() throws {
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(SignedAxis.self, from: Data("\"up\"".utf8)) }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(SignedAxis.self, from: Data("\"y\"".utf8)) }
        #expect(try JSONDecoder().decode(SignedAxis.self, from: Data("\"-z\"".utf8)) == SignedAxis(axis: .z, sign: -1))
    }

    @Test func portSits60mmProximalAnd25mmDorsal() throws {
        // Forearm along +X toward the elbow, wrist joint +Y is dorsal.
        let wrist = transform(at: SIMD3(0, 1, 0))
        let arm = transform(at: SIMD3(0.25, 1, 0))
        let pose = try #require(ForearmPoseSolver.solve(wrist: wrist, arm: arm, config: config))
        #expect(close(pose.position, SIMD3(0.060, 1.025, 0)))
        // +X of the port frame points toward the hand, +Y out of the skin.
        let x = pose.orientation.act(SIMD3<Float>(1, 0, 0))
        let y = pose.orientation.act(SIMD3<Float>(0, 1, 0))
        #expect(close(x, SIMD3(-1, 0, 0)))
        #expect(close(y, SIMD3(0, 1, 0)))
    }

    @Test func dorsalAxisIsMadePerpendicularToForearm() throws {
        // Wrist joint tilted so its +Y leans toward the elbow; the port normal must not.
        let tilt = simd_float3x3(simd_quatf(angle: .pi / 6, axis: SIMD3(0, 0, 1)))
        let wrist = transform(at: .zero, rotation: tilt)
        let arm = transform(at: SIMD3(0.2, 0, 0))
        let pose = try #require(ForearmPoseSolver.solve(wrist: wrist, arm: arm, config: config))
        let y = pose.orientation.act(SIMD3<Float>(0, 1, 0))
        #expect(abs(simd_dot(y, SIMD3(1, 0, 0))) < 1e-4)
        #expect(close(y, SIMD3(0, 1, 0)))
    }

    @Test func flippedDorsalAxisFlipsThePort() throws {
        var flipped = config
        flipped.dorsalAxis = SignedAxis(axis: .y, sign: -1)
        let pose = try #require(ForearmPoseSolver.solve(wrist: transform(at: .zero), arm: transform(at: SIMD3(0.2, 0, 0)), config: flipped))
        #expect(close(pose.position, SIMD3(0.060, -0.025, 0)))
    }

    @Test func coincidentJointsGiveNoPose() {
        #expect(ForearmPoseSolver.solve(wrist: transform(at: .zero), arm: transform(at: .zero), config: config) == nil)
    }

    @Test func oneEuroPassesFirstSampleAndSmoothsJitter() {
        var f = OneEuroFilter(minCutoff: 1, beta: 0, derivativeCutoff: 1)
        #expect(f.filter(10, dt: 0) == 10)
        var out = 10.0
        for i in 0..<20 { out = f.filter(i % 2 == 0 ? 10.1 : 9.9, dt: 1.0 / 90) }
        #expect(abs(out - 10) < 0.05, "jitter of ±0.1 at 90 Hz is attenuated, got \(out)")
    }

    @Test func oneEuroFollowsFastMotion() {
        // Shipped values: at 0.9 m/s the cutoff rises to ~2.8 Hz, so the lag
        // behind a moving arm stays under about 7 cm.
        var f = OneEuroFilter(minCutoff: config.filterMinCutoffHz, beta: config.filterBeta,
                              derivativeCutoff: config.filterDerivativeCutoffHz)
        _ = f.filter(0, dt: 0)
        var out = 0.0
        for i in 1...45 { out = f.filter(Double(i) * 0.01, dt: 1.0 / 90) }  // 0.9 m/s for 0.5 s
        #expect(out > 0.38, "after 0.5 s of steady motion the filter lags the input (0.45) by under 7 cm, got \(out)")
    }

    @Test func trackerHoldsThenFadesThenRecovers() {
        var t = ForearmTracker(config: config)
        #expect(t.pose(at: 0) == nil)
        let raw = (position: SIMD3<Float>(0.1, 1, -0.3), orientation: simd_quatf(angle: 0, axis: SIMD3(0, 1, 0)))
        t.observe(raw, at: 0)
        let p0 = t.pose(at: 0.01)!
        #expect(p0.status == .tracked)
        #expect(p0.opacity == 1)
        #expect(p0.position == raw.position)

        // Tracking drops: pose frozen, opaque, for holdLastPoseMs.
        let hold = t.pose(at: 1.0)!
        #expect(hold.status == .holding)
        #expect(hold.opacity == 1)
        #expect(hold.position == raw.position)

        // Past the hold: fades to occludedOpacity over fadeMs, never snaps away.
        var now = 2.2
        var p = t.pose(at: now)!
        #expect(p.status == .faded)
        #expect(p.opacity < 1 && p.opacity > Float(config.occludedOpacity))
        while now < 2.2 + config.fade + 0.1 { now += 1.0 / 90; p = t.pose(at: now)! }
        #expect(abs(p.opacity - Float(config.occludedOpacity)) < 1e-4)
        #expect(p.position == raw.position)

        // Re-acquired 20 cm away: eases toward it instead of jumping.
        let moved = (position: raw.position + SIMD3<Float>(0.2, 0, 0), orientation: raw.orientation)
        t.observe(moved, at: now)
        let back = t.pose(at: now)!
        #expect(back.status == .tracked)
        #expect(simd_length(back.position - raw.position) < 0.2 * 0.9, "first frame after re-acquire moved less than 90% of the gap")
        for _ in 0..<90 { now += 1.0 / 90; t.observe(moved, at: now); p = t.pose(at: now)! }
        #expect(simd_length(p.position - moved.position) < 0.01)
        #expect(abs(p.opacity - 1) < 1e-4)
    }

    @Test func trackerIgnoresNilObservations() {
        var t = ForearmTracker(config: config)
        t.observe(nil, at: 1)
        #expect(t.pose(at: 1) == nil)
    }
}

@Suite struct SimulatedForearmTests {
    let config = try! ChargeSequence.shipped().config.forearm

    @Test func flagIsOnInShippedConfig() {
        #expect(config.simulatedForearm)
        #expect(config.simulatedPath.periodS == 8)
    }

    @Test func pathIsACircleAboutTheCentreFacingTheNormal() {
        let c = config.simulatedPath
        let p0 = SimulatedForearmPath.pose(at: 0, config: c)
        #expect(abs(simd_length(p0.position - c.centre) - c.radius) < 1e-5)
        #expect(p0.status == .tracked)
        #expect(p0.opacity == 1)
        let normal = p0.orientation.act(SIMD3<Float>(0, 1, 0))
        #expect(simd_length(normal - simd_normalize(c.normalVector)) < 1e-4)
        // Half a lap later the port is on the far side of the circle.
        let pHalf = SimulatedForearmPath.pose(at: c.periodS / 2, config: c)
        #expect(abs(simd_length(pHalf.position - p0.position) - 2 * c.radius) < 1e-4)
        // A whole lap returns to the start.
        let pLap = SimulatedForearmPath.pose(at: c.periodS, config: c)
        #expect(simd_length(pLap.position - p0.position) < 1e-4)
    }
}
