import XCTest
import CoreMotion
import UIKit
@testable import UIComponents

@MainActor
final class CardGramReflectionTests: XCTestCase {
    func testTelegramV2SymmetricBoundedMotionAndSingularity() throws {
        let zero = CMRotationRate(x: 0, y: 0, z: 0)
        func replay(_ q: CMQuaternion, orientation: UIInterfaceOrientation = .portrait, fps: Int = 60, seconds: Int = 3) -> CardGramReflectionMotion {
            var m = CardGramReflectionMotion()
            m.sample(attitude: gyroQuaternion(pitch: 0, roll: 0), rotationRate: zero, orientation: orientation, by: 1/Double(fps))
            for _ in 0..<(fps*seconds) { m.sample(attitude: q, rotationRate: zero, orientation: orientation, by: 1/Double(fps)); m.advance(by: 1/Double(fps)) }
            return m
        }
        func pose(_ m: CardGramReflectionMotion, limit: Double = 35, sensitivity: Double = 1) throws -> CardGramReflectionPose {
            try XCTUnwrap(m.pose(mode: .telegramV2, press: .zero, aspect: 0.58, v2Limit: limit, v2Sensitivity: sensitivity))
        }
        XCTAssertEqual(CardGramReflectionMode.telegram.rawValue, 1)
        XCTAssertEqual(CardGramReflectionMode.predictable.rawValue, 2)
        XCTAssertEqual(CardGramReflectionMode.physical.rawValue, 3, "Stored old values must not change meanings")
        let angle = 20 * Double.pi / 180
        for orientation: UIInterfaceOrientation in [.portrait, .landscapeLeft, .landscapeRight, .portraitUpsideDown] {
            for q in [gyroQuaternion(pitch: angle, roll: 0), gyroQuaternion(pitch: 0, roll: angle), CMQuaternion(x:0,y:0,z:sin(angle/2),w:cos(angle/2))] {
                let inverse = CMQuaternion(x:-q.x,y:-q.y,z:-q.z,w:q.w)
                let positive = try pose(replay(q, orientation: orientation))
                let negative = try pose(replay(inverse, orientation: orientation))
                XCTAssertEqual(positive.rotation, -negative.rotation, accuracy: 1e-8)
                XCTAssertGreaterThan(abs(positive.rotation), 0.2)
                XCTAssertEqual(positive.energy, 1, accuracy: 1e-8)
            }
        }
        let small = try pose(replay(gyroQuaternion(pitch: 0, roll: .pi/180)))
        XCTAssertGreaterThan(small.rotation, 0.015, "A deliberate one-degree tilt stays visible")
        let tilted = replay(gyroQuaternion(pitch: -angle, roll: angle))
        let widePositive = try XCTUnwrap(tilted.pose(mode: .telegramV2, press: SIMD3(-1,1,1), aspect:0.58, v2Limit:180, v2Sensitivity:2))
        let wideNegative = try XCTUnwrap(replay(gyroQuaternion(pitch: angle, roll: -angle)).pose(mode: .telegramV2, press: SIMD3(1,-1,1), aspect:0.58, v2Limit:180, v2Sensitivity:2))
        XCTAssertGreaterThan(widePositive.rotation, .pi / 2, "The renderer input can exceed the previous90 degree cap")
        XCTAssertLessThan(widePositive.rotation, .pi, "Soft bound remains below180 degrees")
        XCTAssertLessThan(wideNegative.rotation, -.pi / 2)
        XCTAssertGreaterThan(wideNegative.rotation, -.pi)
        XCTAssertEqual(try pose(tilted, limit: 0).rotation, 0)
        XCTAssertLessThan(abs(try pose(tilted, limit: 12).rotation), 12 * .pi / 180)
        XCTAssertGreaterThan(abs(try pose(tilted, sensitivity: 2).rotation), abs(try pose(tilted, sensitivity: 0.25).rotation))
        XCTAssertEqual(try pose(tilted).rotation, try pose(replay(gyroQuaternion(pitch: -angle, roll: angle), seconds: 10)).rotation, accuracy: 1e-8)
        for fps in [30,120] {
            XCTAssertEqual(try pose(replay(gyroQuaternion(pitch: -angle, roll: angle), fps: fps, seconds: 1)).rotation,
                           try pose(replay(gyroQuaternion(pitch: -angle, roll: angle), seconds: 1)).rotation, accuracy: 0.001)
        }
        // Sweep across Telegram's head-on lamp direction: no azimuth jump in v2.
        var previous: Double?
        for degrees in stride(from: -45.0, through: 45.0, by: 1) {
            let q = gyroQuaternion(pitch: degrees * .pi / 180, roll: degrees * .pi / 180)
            let p = try pose(replay(q))
            XCTAssertTrue(p.rotation.isFinite); XCTAssertLessThanOrEqual(abs(p.rotation), 35 * .pi / 180)
            if let previous { XCTAssertLessThan(abs(p.rotation - previous), 0.035) }
            previous = p.rotation
            let negated = CMQuaternion(x:-q.x,y:-q.y,z:-q.z,w:-q.w)
            XCTAssertEqual(p, try pose(replay(negated)), "Quaternion sign must not affect the light")
        }
        for degrees in [159.0, 160, 179, 180, 181, 200] {
            let a = degrees * .pi / 180
            let p = try pose(replay(CMQuaternion(x:0,y:0,z:sin(a/2),w:cos(a/2))))
            XCTAssertTrue(p.rotation.isFinite); XCTAssertLessThan(p.energy, 0.002)
            XCTAssertLessThan(abs(p.rotation), 0.004, "The +/-pi seam is crossed only with an extinguished, settled reflection")
        }
    }

    private func gyroQuaternion(pitch: Double, roll: Double) -> CMQuaternion {
        let p = pitch / 2, r = roll / 2
        return CMQuaternion(x: sin(p) * cos(r), y: cos(p) * sin(r), z: sin(p) * sin(r), w: cos(p) * cos(r))
    }
}
