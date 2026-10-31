import XCTest
import simd
@testable import ChargeUpCore

final class EnergyPathTests: XCTestCase {
    private let port = SIMD3<Float>(-0.2, 1.0, -0.3), up = SIMD3<Float>(0, 1, 0)
    private let lantern = SIMD3<Float>(0.05, 1.25, -0.55)

    func testEndsAndClamping() {
        let p = EnergyPath(port: port, portUp: up, target: lantern, bend: 0.35)
        XCTAssertEqual(simd_distance(p.point(at: 0), port), 0, accuracy: 1e-6)
        XCTAssertEqual(simd_distance(p.point(at: 1), lantern), 0, accuracy: 1e-6)
        XCTAssertEqual(p.point(at: 1.5), p.point(at: 1))
        XCTAssertEqual(p.samples(segments: 8).count, 9)
    }

    /// It leaves straight out of the port's glass and goes into the lantern
    /// level, from the port's side.
    func testLeavesAlongThePortsUpAndEntersTheLanternLevel() {
        let tiltedUp = simd_normalize(SIMD3<Float>(0.2, 1, 0.1))
        let p = EnergyPath(port: port, portUp: tiltedUp, target: lantern, bend: 0.35)
        XCTAssertGreaterThan(simd_dot(p.tangent(at: 0), tiltedUp), 0.9999)
        let end = p.tangent(at: 1)
        XCTAssertEqual(end.y, 0, accuracy: 1e-5, "enters level")
        var away = lantern - port
        away.y = 0
        XCTAssertGreaterThan(simd_dot(end, simd_normalize(away)), 0.9999, "coming from the port's side")
    }

    /// Smooth: the tangent turns gradually everywhere, no corner.
    func testNoSharpCorners() {
        let p = EnergyPath(port: port, portUp: up, target: lantern, bend: 0.35)
        let n = 200
        for i in 1...n {
            let a = p.tangent(at: Float(i - 1) / Float(n)), b = p.tangent(at: Float(i) / Float(n))
            XCTAssertGreaterThan(simd_dot(a, b), 0.995, "kink near u \(Float(i) / Float(n))")
        }
    }

    func testTangentMatchesFiniteDifference() {
        let p = EnergyPath(port: port, portUp: up, target: lantern, bend: 0.35)
        for t in stride(from: Float(0.05), through: 0.95, by: 0.1) {
            let h: Float = 1e-3
            let fd = simd_normalize(p.point(at: t + h) - p.point(at: t - h))
            XCTAssertGreaterThan(simd_dot(fd, p.tangent(at: t)), 0.9999, "t \(t)")
        }
    }

    func testFollowsTheEndpoints() {
        let a = EnergyPath(port: port, portUp: up, target: lantern, bend: 0.35)
        let b = EnergyPath(port: port + SIMD3(0.01, 0, 0), portUp: up, target: lantern, bend: 0.35)
        XCTAssertNotEqual(a.point(at: 0.4), b.point(at: 0.4))
    }

    func testFadeAtBothEnds() {
        XCTAssertEqual(EnergyPath.fade(at: 0, fade: 0.1), 0)
        XCTAssertEqual(EnergyPath.fade(at: 0.05, fade: 0.1), 0.5, accuracy: 1e-6)
        XCTAssertEqual(EnergyPath.fade(at: 0.5, fade: 0.1), 1)
        XCTAssertEqual(EnergyPath.fade(at: 0.95, fade: 0.1), 0.5, accuracy: 1e-5)
        XCTAssertEqual(EnergyPath.fade(at: 1, fade: 0.1), 0)
        XCTAssertEqual(EnergyPath.fade(at: 0, fade: 0), 1)
    }

    /// A path that rises through vertical out of the port: transported
    /// normals stay perpendicular, unit length, and never flip.
    func testTransportFramesDoNotFlipThroughVertical() {
        let p = EnergyPath(port: .zero, portUp: up, target: SIMD3(0.002, 0.35, -0.01), bend: 0.35)
        let frames = TransportFrames.frames(along: p.samples(segments: 32))
        XCTAssertEqual(frames.count, 33)
        for (i, f) in frames.enumerated() {
            XCTAssertEqual(simd_length(f.normal), 1, accuracy: 1e-4)
            XCTAssertEqual(simd_dot(f.normal, f.tangent), 0, accuracy: 1e-4)
            if i > 0 { XCTAssertGreaterThan(simd_dot(f.normal, frames[i - 1].normal), 0.9, "jump at \(i)") }
        }
    }

    func testTransportFramesOnAStraightLineKeepOneNormal() {
        let pts = (0...10).map { SIMD3<Float>(0, Float($0) * 0.03, 0) }
        let frames = TransportFrames.frames(along: pts)
        for f in frames { XCTAssertEqual(simd_dot(f.normal, frames[0].normal), 1, accuracy: 1e-5) }
    }

    // MARK: Fireflies

    private func visuals() throws -> VisualsConfig { try ChargeSequence.shipped().config.visuals }

    func testFirefliesSetOffOneAfterAnotherAndKeepFlowing() throws {
        let v = try visuals()
        var swarm = FireflySwarm(visuals: v)
        XCTAssertEqual(swarm.flies.count, v.fireflyCount)
        XCTAssertEqual(swarm.flies.filter(\.isVisible).count, 1, "only the first is out at the start")
        // A few seconds of flow at 90 Hz: most are out, none stuck.
        for _ in 0..<(90 * 4) { swarm.advance(dt: 1.0 / 90, flowing: true, visuals: v) }
        XCTAssertGreaterThan(swarm.flies.filter(\.isVisible).count, v.fireflyCount / 2)
        XCTAssertTrue(swarm.flies.allSatisfy { $0.u < 1 }, "each one that arrives sets off again")
    }

    func testEachFireflyIsDifferentWithinTheJitter() throws {
        let v = try visuals()
        let swarm = FireflySwarm(visuals: v)
        let speeds = Set(swarm.flies.map(\.speed)), sizes = Set(swarm.flies.map(\.size))
        XCTAssertGreaterThan(speeds.count, v.fireflyCount / 2)
        XCTAssertGreaterThan(sizes.count, v.fireflyCount / 2)
        for f in swarm.flies {
            XCTAssertLessThanOrEqual(abs(f.speed - 1), Float(v.fireflySpeedJitter) + 1e-6)
            XCTAssertLessThanOrEqual(abs(f.size - 1), Float(v.fireflySizeJitter) + 1e-6)
        }
        XCTAssertEqual(FireflySwarm(visuals: v), swarm, "seeded: the same run every time")
    }

    func testWhenFlowStopsTheyFinishTheirRunAndWait() throws {
        let v = try visuals()
        var swarm = FireflySwarm(visuals: v)
        for _ in 0..<(90 * 3) { swarm.advance(dt: 1.0 / 90, flowing: true, visuals: v) }
        let waiting = swarm.flies.filter { $0.u < 0 }.map(\.u)
        for _ in 0..<(90 * 6) { swarm.advance(dt: 1.0 / 90, flowing: false, visuals: v) }
        XCTAssertEqual(swarm.flies.filter(\.isVisible).count, 0, "all gone into the lantern")
        XCTAssertEqual(swarm.flies.filter { $0.u < 0 }.map(\.u), waiting, "waiting ones do not set off")
    }

    func testWanderGathersToNothingAtBothEnds() throws {
        let v = try visuals()
        var f = FireflySwarm(visuals: v).flies[0]
        f.u = 0
        XCTAssertLessThan(simd_length(FireflySwarm.wander(f, time: 1.3, visuals: v)), 1e-6)
        f.u = 1
        XCTAssertLessThan(simd_length(FireflySwarm.wander(f, time: 1.3, visuals: v)), 1e-6)
        f.u = 0.5
        let mid = simd_length(FireflySwarm.wander(f, time: 1.3, visuals: v))
        XCTAssertLessThanOrEqual(mid, Float(v.fireflyWanderMm / 1000) * 1.4143)
    }
}
