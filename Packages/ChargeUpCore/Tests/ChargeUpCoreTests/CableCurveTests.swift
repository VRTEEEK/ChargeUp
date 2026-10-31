import XCTest
import simd
@testable import ChargeUpCore

final class CableCurveTests: XCTestCase {
    func testEndsAndSag() {
        let c = CableCurve(from: SIMD3(0, 0, 0), to: SIMD3(1, 0, 0), sag: 0.1)
        XCTAssertEqual(c.point(at: 0), SIMD3(0, 0, 0))
        XCTAssertEqual(c.point(at: 1), SIMD3(1, 0, 0))
        XCTAssertEqual(c.point(at: 0.5).y, -0.1, accuracy: 1e-6)
        // Clamped outside 0...1.
        XCTAssertEqual(c.point(at: 1.5), SIMD3(1, 0, 0))
    }

    func testTangentMatchesFiniteDifference() {
        let c = CableCurve(from: SIMD3(0.1, -0.3, 0.2), to: SIMD3(-0.2, 0.25, -0.1), sag: 0.03)
        for t in stride(from: Float(0.05), through: 0.95, by: 0.1) {
            let h: Float = 1e-3
            let fd = simd_normalize(c.point(at: t + h) - c.point(at: t - h))
            XCTAssertGreaterThan(simd_dot(fd, c.tangent(at: t)), 0.9999, "t \(t)")
        }
    }

    func testSamplesFollowTheCurrentEndpoints() {
        var c = CableCurve(from: .zero, to: SIMD3(0, 0.3, -0.3), sag: 0.03)
        let before = c.point(at: 0.4)
        c.start = SIMD3(0.01, 0, 0)
        XCTAssertNotEqual(c.point(at: 0.4), before)
        XCTAssertEqual(c.samples(segments: 4).count, 5)
        XCTAssertEqual(c.samples(segments: 4).last, c.end)
    }

    func testSparkOpacityFadesAtBothEnds() {
        XCTAssertEqual(CableCurve.sparkOpacity(at: 0, fade: 0.1), 0)
        XCTAssertEqual(CableCurve.sparkOpacity(at: 0.05, fade: 0.1), 0.5, accuracy: 1e-6)
        XCTAssertEqual(CableCurve.sparkOpacity(at: 0.1, fade: 0.1), 1, accuracy: 1e-6)
        XCTAssertEqual(CableCurve.sparkOpacity(at: 0.5, fade: 0.1), 1)
        XCTAssertEqual(CableCurve.sparkOpacity(at: 0.95, fade: 0.1), 0.5, accuracy: 1e-5)
        XCTAssertEqual(CableCurve.sparkOpacity(at: 1, fade: 0.1), 0)
        XCTAssertEqual(CableCurve.sparkOpacity(at: 0, fade: 0), 1)
    }

    /// The case that twisted the old tube: a cable that rises through
    /// vertical. Transported normals stay perpendicular, unit length, and
    /// turn smoothly between neighbours, never flipping.
    func testTransportFramesDoNotFlipThroughVertical() {
        let c = CableCurve(from: SIMD3(0, 0, 0), to: SIMD3(0.002, 0.35, -0.01), sag: 0.03)
        let frames = TransportFrames.frames(along: c.samples(segments: 24))
        XCTAssertEqual(frames.count, 25)
        for (i, f) in frames.enumerated() {
            XCTAssertEqual(simd_length(f.normal), 1, accuracy: 1e-4)
            XCTAssertEqual(simd_dot(f.normal, f.tangent), 0, accuracy: 1e-4)
            if i > 0 {
                XCTAssertGreaterThan(simd_dot(f.normal, frames[i - 1].normal), 0.9, "jump at \(i)")
            }
        }
    }

    func testTransportFramesOnAStraightLineKeepOneNormal() {
        let pts = (0...10).map { SIMD3<Float>(0, Float($0) * 0.03, 0) }
        let frames = TransportFrames.frames(along: pts)
        for f in frames { XCTAssertEqual(simd_dot(f.normal, frames[0].normal), 1, accuracy: 1e-5) }
    }
}
