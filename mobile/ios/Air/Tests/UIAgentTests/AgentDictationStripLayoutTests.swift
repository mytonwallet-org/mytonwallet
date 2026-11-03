import XCTest
import UIKit
@testable import UIAgent
import WalletResources

final class AgentDictationStripLayoutTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        _ = WalletResourcesBundle.bundle.load()
    }

    @MainActor
    func testHoldingShowsDotTimerAndSlidingHintIncludingCountdown() async throws {
        for direction in [UIUserInterfaceLayoutDirection.leftToRight, .rightToLeft] {
            let scheduler = AgentDictationTestScheduler()
            let recorder = AgentDictationTestRecorder()
            var isRecordingReady = false
            let controller = AgentDictationController(
                scheduler: scheduler,
                requestPermission: { true },
                makeRecorder: { recorder },
                transcribe: { _ in .init(outcome: .noSpeech) },
                haptic: { isRecordingReady = true },
                gestureFeedback: {},
                observeLifecycle: false
            )
            defer { controller.cancel() }
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 812))
            let root = UIViewController()
            root.view.frame = window.bounds
            let host = UIViewController()
            root.addChild(host)
            root.view.addSubview(host.view)
            host.view.frame = window.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            host.didMove(toParent: root)
            let traitDirection: UITraitEnvironmentLayoutDirection = direction == .rightToLeft ? .rightToLeft : .leftToRight
            if #available(iOS 17, *) {
                root.traitOverrides.layoutDirection = traitDirection
            } else {
                root.setOverrideTraitCollection(UITraitCollection(layoutDirection: traitDirection), forChild: host)
            }
            window.rootViewController = root
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            let composer = AgentComposerView()
            composer.dictationController = controller
            host.view.addSubview(composer)
            NSLayoutConstraint.activate([
                composer.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
                composer.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
                composer.bottomAnchor.constraint(equalTo: host.view.bottomAnchor)
            ])

            controller.touchBegan(isRightToLeft: direction == .rightToLeft)
            scheduler.advance(by: 0.22)
            for _ in 0..<100 where !isRecordingReady { await Task.yield() }
            XCTAssertTrue(isRecordingReady)
            XCTAssertEqual(controller.state.phase, .holding)
            window.layoutIfNeeded()
            let strip = try XCTUnwrap(findDescendants(of: composer).compactMap { $0 as? AgentDictationStripView }.first)
            let timer = try XCTUnwrap(strip.subviews.compactMap { $0 as? UILabel }.first {
                $0.text == AgentVoiceRecordingMetrics.formatTimer(0)
            })
            let dot = try XCTUnwrap(strip.subviews.first {
                !($0 is UILabel) && !($0 is UIButton)
                    && $0.layer.cornerRadius == AgentVoiceRecordingMetrics.recordingDotDiameter / 2
            })
            let hint = try XCTUnwrap(strip.subviews.compactMap { $0 as? UILabel }.first { $0 !== timer })
            let cancel = try XCTUnwrap(strip.cancelAccessibilityElement as? UIButton)
            XCTAssertEqual(strip.effectiveUserInterfaceLayoutDirection, direction)
            XCTAssertEqual(dot.bounds.width, AgentVoiceRecordingMetrics.recordingDotDiameter)

            for elapsed in [0.0, 51.0] {
                scheduler.advance(by: elapsed)
                window.layoutIfNeeded()

                XCTAssertFalse(strip.isHidden)
                XCTAssertFalse(dot.isHidden)
                XCTAssertFalse(hint.isHidden)
                XCTAssertTrue(cancel.isHidden)
                if direction == .leftToRight {
                    XCTAssertLessThanOrEqual(dot.frame.maxX, timer.frame.minX)
                    XCTAssertLessThanOrEqual(timer.frame.maxX, hint.frame.minX)
                } else {
                    XCTAssertLessThanOrEqual(timer.frame.maxX, dot.frame.minX)
                    XCTAssertLessThanOrEqual(hint.frame.maxX, timer.frame.minX)
                }
            }

            let initialHintX = hint.frame.midX
            let timerFrame = timer.frame
            let dragX = direction == .rightToLeft ? 22.0 : -22.0
            controller.touchMoved(x: dragX, y: 0)
            window.layoutIfNeeded()
            XCTAssertEqual(hint.frame.midX, initialHintX + dragX, accuracy: 0.01)
            XCTAssertEqual(hint.alpha, 0.8, accuracy: 0.01)
            XCTAssertEqual(timer.frame, timerFrame)
        }
    }

    @MainActor
    func testLockedRecordingShowsTelegramSizedCancel() throws {
        let strip = AgentDictationStripView()
        strip.update(AgentDictationState(phase: .locked))
        let cancel = try XCTUnwrap(strip.cancelAccessibilityElement as? UIButton)
        XCTAssertFalse(cancel.isHidden)
        XCTAssertEqual(cancel.titleLabel?.font.pointSize, AgentVoiceRecordingMetrics.cancelFontSize)
        strip.frame = CGRect(x: 0, y: 0, width: 250, height: AgentComposerMetrics.minInputHeight)
        strip.layoutIfNeeded()
        XCTAssertEqual(cancel.frame.height, AgentComposerMetrics.minInputHeight)
        XCTAssertGreaterThan(cancel.frame.width, cancel.titleLabel?.intrinsicContentSize.width ?? 0)
    }

    @MainActor
    func testVoiceWavesGrowInAndSwellAsTelegramsRipple() throws {
        let side = AgentVoiceRecordingMetrics.blobDiameter
        let blob = AgentVoiceBlobView(frame: CGRect(x: 0, y: 0, width: side, height: side))
        blob.layoutIfNeeded()
        let centre = AgentVoiceRecordingMetrics.centreDiameter
        let outerWave = AgentVoiceBlobView.outerWave

        // Before recording the waves rest at three quarters of their size, and grow to it as recording starts
        XCTAssertEqual(blob.outerWaveDiameter, outerWave.min * 0.75, accuracy: 0.5)
        blob.startAnimating(at: 0)
        blob.updatePresentationLevel(at: 1)
        XCTAssertEqual(blob.outerWaveDiameter, outerWave.min, accuracy: 0.5)
        XCTAssertEqual(blob.innerWaveDiameter, (centre * outerWave.min).squareRoot(), accuracy: 0.5)

        // A loud voice swells the outer wave to Telegram's largest, the inner one keeping to the geometric mean
        blob.updateLevel(1)
        for frame in 1...240 {
            blob.updatePresentationLevel(at: 1 + Double(frame) / 60)
        }
        XCTAssertEqual(blob.outerWaveDiameter, outerWave.max, accuracy: 1)
        XCTAssertEqual(blob.innerWaveDiameter, (centre * blob.outerWaveDiameter).squareRoot(), accuracy: 0.5)
        blob.stopAnimating()
    }

    @MainActor
    func testVoiceWaveOutlineIsASmoothBlobWithinItsSize() {
        var motion = AgentVoiceBlobMotion()
        for _ in 0..<20 {
            motion.advance(by: 0.13)
            let outline = motion.makeOutline(diameter: 200, isStill: false)
            XCTAssertEqual(outline.segments.count, 8)
            let radii = outline.getRadii(count: AgentVoiceDisplacementMap.sampleCount)
            // Eight points between 1/1.1 of the radius and the radius, joined smoothly: no lobes, no dents. Mid-morph
            // the points of two shapes turned up to about 70° apart meet on chords, which draws the outline in to
            // about three quarters of the radius at most
            XCTAssertLessThanOrEqual(radii.max() ?? 0, 100 * Float(AgentVoiceBlobOutline.overshoot))
            XCTAssertGreaterThanOrEqual(radii.min() ?? 0, 70)
            for index in radii.indices {
                XCTAssertLessThan(abs(radii[index] - radii[(index + 1) % radii.count]), 1.5)
            }
        }
        let circle = AgentVoiceBlobMotion().makeOutline(diameter: 200, isStill: true).getRadii(count: 64)
        for radius in circle {
            XCTAssertEqual(radius, 100, accuracy: 0.1)
        }
    }

    @MainActor
    func testGlassMapPullsContentInAtEachWaveEdgeAsTelegramsShader() {
        var map = AgentVoiceDisplacementMap(reach: 80)
        let circle = AgentVoiceBlobMotion().makeOutline(diameter: 100, isStill: true)
        XCTAssertNotNil(map.makeImage(radii: [circle.getRadii(count: AgentVoiceDisplacementMap.sampleCount)]))
        let centre = CGPoint(x: 80, y: 80)
        func offset(_ dx: CGFloat, _ dy: CGFloat) -> (red: Double, green: Double) {
            let value = map.encodeOffset(at: CGPoint(x: centre.x + dx, y: centre.y + dy))
            return (Double(value.red), Double(value.green))
        }
        // Just inside the edge the glass shows content from further in, so the map moves content outward: red above
        // the neutral 128 on the right, below it on the left; green likewise at the bottom and top
        XCTAssertGreaterThan(offset(48, 0).red, 150)
        XCTAssertEqual(offset(48, 0).green, 128, accuracy: 2)
        XCTAssertLessThan(offset(-48, 0).red, 106)
        XCTAssertGreaterThan(offset(0, 48).green, 150)
        XCTAssertLessThan(offset(0, -48).green, 106)
        // Deeper than the band, and outside the wave, nothing moves
        XCTAssertEqual(offset(0, 20).red, 128, accuracy: 1)
        XCTAssertEqual(offset(0, 20).green, 128, accuracy: 1)
        XCTAssertEqual(offset(0, 70).green, 128, accuracy: 1)
        XCTAssertEqual(offset(70, 0).red, 128, accuracy: 1)
    }

    func testTimerShowsMinutesSecondsAndCentiseconds() {
        XCTAssertEqual(AgentVoiceRecordingMetrics.formatTimer(0), "0:00,00")
        XCTAssertEqual(AgentVoiceRecordingMetrics.formatTimer(7.25), "0:07,25")
        XCTAssertEqual(AgentVoiceRecordingMetrics.formatTimer(61.999), "1:01,99")
        XCTAssertEqual(AgentVoiceRecordingMetrics.formatTimer(-3), "0:00,00")
    }
}
