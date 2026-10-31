import Foundation
import Testing
import simd
@testable import ChargeUpCore

@Suite struct LookSparkleTests {
    private func config() throws -> LookSparkleConfig { try ChargeSequence.shipped().config.lookSparkle }

    @Test func offAxisIsMeasuredToTheObjectsEdge() {
        let head = SIMD3<Float>(0, 1.2, 0), forward = SIMD3<Float>(0, 0, -1)
        #expect(LookSparkleConfig.offAxis(head: head, forward: forward, centre: SIMD3(0, 1.2, -2.5), radius: 0.05) == 0)
        // 10 cm to the side at 2.5 m, 5 cm radius: about 1.1 degrees off the edge.
        let a = LookSparkleConfig.offAxis(head: head, forward: forward, centre: SIMD3(0.1, 1.2, -2.5), radius: 0.05)
        #expect(abs(a - (atan(Float(0.1) / 2.5) - atan(Float(0.05) / 2.5))) < 1e-3)
    }

    @Test func picksAfterTheDwellHoldsBrieflyAndNeverFlickers() throws {
        let c = try config()
        var p = LookPicker()
        let dwell = Double(c.dwellMs) / 1000, hold = Double(c.holdMs) / 1000
        #expect(p.update(offAxis: ["lantern3": 0.01], time: 0, config: c) == nil, "not straight away")
        #expect(p.update(offAxis: ["lantern3": 0.01], time: dwell + 0.01, config: c) == "lantern3")
        // A neighbour briefly nearer does not steal it before its own dwell.
        #expect(p.update(offAxis: ["lantern3": 0.03, "lantern4": 0.01], time: dwell + 0.05, config: c) == "lantern3")
        // Out of the cone: kept for the hold, then let go.
        #expect(p.update(offAxis: ["lantern3": 1], time: dwell + 0.1, config: c) == "lantern3")
        #expect(p.update(offAxis: [:], time: dwell + 0.1 + hold + 0.2, config: c) == nil)
    }

    @Test func gentleAndGolden() throws {
        let c = try config()
        #expect(c.enabled && c.coneDeg <= 8, "a narrow cone, so it is the one looked at")
        #expect(c.perSecond <= 40 && c.sizeMm <= 8, "a few small sparkles, not a glow")
        let rgb = c.rgb
        #expect(rgb.x > rgb.y && rgb.y > rgb.z, "golden")
    }
}
