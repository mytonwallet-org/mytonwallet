import CoreMotion
import Testing
import UIKit
@testable import UIComponents

@Suite("Card device tilt calibration")
struct CardDeviceTiltTests {
    private func sample(_ input: inout CardDeviceTilt, pitch: Double, speed: Double = 0,
                        touch: Bool = false, settled: Bool = true, dt: Double = 1.0 / 60,
                        orientation: UIInterfaceOrientation = .portrait) -> (tilt: CGPoint, angularSpeed: Double) {
        let halfAngle = pitch * .pi / 360
        return input.update(attitude: CMQuaternion(x: sin(halfAngle), y: 0, z: 0, w: cos(halfAngle)),
                            rotationRate: CMRotationRate(x: speed, y: 0, z: 0),
                            orientation: orientation, touchActive: touch,
                            lightIsSettled: settled, sensitivity: 1.5, by: dt)
    }

    @Test func pitchingTopEdgeTowardViewerProducesPositivePitchFromAnyRestingPose() {
        for restingPitch in [0.0, 40, 80, -30] {
            var input = CardDeviceTilt()
            #expect(sample(&input, pitch: restingPitch).tilt == .zero)
            let toward = sample(&input, pitch: restingPitch + 20, speed: 0.6)
            let away = sample(&input, pitch: restingPitch - 20, speed: -0.6)
            #expect(toward.tilt.y > 0)
            #expect(abs(toward.tilt.y + away.tilt.y) < 1e-12)
            #expect(toward.tilt.x == 0 && away.tilt.x == 0)
            #expect(toward.angularSpeed == away.angularSpeed)
        }
    }

    @Test(arguments: [30, 60])
    func idlePoseBecomesNeutralAndNextInteractionStartsThere(_ fps: Int) {
        var input = CardDeviceTilt()
        let dt = 1 / Double(fps)
        _ = sample(&input, pitch: 40, dt: dt)
        #expect(sample(&input, pitch: 60, speed: 0.6, dt: dt).tilt.y > 0)
        for _ in 0..<(fps * 2) {
            #expect(sample(&input, pitch: 60, speed: 0.01, dt: dt).tilt.y > 0)
        }
        for _ in 0..<(fps * 2) { _ = sample(&input, pitch: 60, speed: 0.01, dt: dt) }
        #expect(sample(&input, pitch: 60, dt: dt).tilt == .zero)
        // A tap uses the new neutral; small tilt still needs to leave the dead zone.
        #expect(sample(&input, pitch: 60, touch: true, dt: dt).tilt == .zero)
        #expect(sample(&input, pitch: 63, speed: 0.6, dt: dt).tilt == .zero)
        let response = sample(&input, pitch: 70, speed: 0.6, dt: dt)
        let expected = CardDeviceTilt.response(to: CGPoint(x: 0, y: 10 * CGFloat.pi / 180), angularSpeed: 0.6, sensitivity: 1.5)
        #expect(abs(response.tilt.y - expected.tilt.y) < 1e-12)
    }

    @Test func heldTouchOrFadingShinePreventsRecalibration() {
        var input = CardDeviceTilt()
        _ = sample(&input, pitch: 0)
        for _ in 0..<360 {
            #expect(sample(&input, pitch: 20, touch: true).tilt.y > 0)
        }
        for _ in 0..<240 {
            #expect(sample(&input, pitch: 20, settled: false).tilt.y > 0)
        }
        #expect(sample(&input, pitch: 20).tilt == .zero)
    }

    @Test func rawMotionBelowLightActivityThresholdStillPreventsRecalibration() {
        var input = CardDeviceTilt()
        _ = sample(&input, pitch: 0)
        for frame in 0..<300 {
            _ = sample(&input, pitch: Double(frame) / 100, speed: 0.06)
        }
        let response = sample(&input, pitch: 10, speed: 0.06)
        let expected = CardDeviceTilt.response(to: CGPoint(x: 0, y: 10 * CGFloat.pi / 180), angularSpeed: 0.06, sensitivity: 1.5)
        #expect(abs(response.tilt.y - expected.tilt.y) < 1e-12)
    }

    @Test func movementRestartsTheEntireIdleInterval() {
        var input = CardDeviceTilt()
        _ = sample(&input, pitch: 0)
        for _ in 0..<150 { _ = sample(&input, pitch: 20) }
        _ = sample(&input, pitch: 21, speed: 0.6)
        for _ in 0..<150 { #expect(sample(&input, pitch: 21).tilt.y > 0) }
        for _ in 0..<60 { _ = sample(&input, pitch: 21) }
        #expect(sample(&input, pitch: 21).tilt == .zero)
    }

    @Test func resetAndOrientationChangesDiscardTheOldReference() {
        var input = CardDeviceTilt()
        _ = sample(&input, pitch: 0)
        #expect(sample(&input, pitch: 20, speed: 0.6).tilt.y > 0)
        input.reset()
        #expect(sample(&input, pitch: 20).tilt == .zero)
        #expect(sample(&input, pitch: 30, orientation: .landscapeLeft).tilt == .zero)
        let landscape = sample(&input, pitch: 40, speed: 0.6, orientation: .landscapeLeft)
        #expect(landscape.tilt.x > 0 && landscape.tilt.y == 0)
    }

    @Test func activePitchSpeedRemainsAvailableInsideTheInitialDeadZone() {
        var input = CardDeviceTilt()
        _ = sample(&input, pitch: 0)
        let response = sample(&input, pitch: 2, speed: -0.3)
        #expect(response.tilt == .zero && response.angularSpeed == 0)
        #expect(input.pitchAngularSpeed == 0.3)
        #expect(abs(input.pitch - 2 * CGFloat.pi / 180) < 1e-12)
        input.reset()
        #expect(input.pitchAngularSpeed == 0 && input.pitch == 0)
    }

    @Test func rollUsesTheScreenAxisAndResetsAlongWithPitch() {
        for orientation: UIInterfaceOrientation in [.portrait, .landscapeLeft, .landscapeRight, .portraitUpsideDown] {
            var input = CardDeviceTilt()
            _ = sample(&input, pitch: 0, orientation: orientation)
            let halfAngle = 12 * Double.pi / 360
            _ = input.update(attitude: CMQuaternion(x: 0, y: sin(halfAngle), z: 0, w: cos(halfAngle)),
                rotationRate: CMRotationRate(x: 0, y: 0.3, z: 0), orientation: orientation,
                touchActive: false, lightIsSettled: false, sensitivity: 1.5, by: 1.0 / 60)
            if orientation.isLandscape {
                #expect(input.roll == 0 && input.rollAngularSpeed == 0)
                #expect(abs(abs(input.pitch) - 12 * CGFloat.pi / 180) < 1e-12)
                #expect(input.pitchAngularSpeed == 0.3)
            } else {
                #expect(input.pitch == 0 && input.pitchAngularSpeed == 0)
                #expect(abs(abs(input.roll) - 12 * CGFloat.pi / 180) < 1e-12)
                #expect(input.rollAngularSpeed == 0.3)
            }
            input.reset()
            #expect(input.roll == 0 && input.rollAngularSpeed == 0)
        }
    }
}
