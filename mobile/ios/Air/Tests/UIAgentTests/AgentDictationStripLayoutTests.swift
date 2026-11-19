import XCTest
import UIKit
@testable import UIAgent
import WalletContext
import WalletResources

final class AgentDictationStripLayoutTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        _ = WalletResourcesBundle.bundle.load()
    }

    /// A held microphone shows what letting go does where the finger is, at the field's leading end, without a timer:
    /// stop near where it started, cancel toward the field's cross, send toward Send
    @MainActor
    func testHoldingShowsWhatLettingGoDoes() async throws {
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
            let hint = try XCTUnwrap(strip.subviews.compactMap { $0 as? UILabel }.first)
            XCTAssertEqual(strip.effectiveUserInterfaceLayoutDirection, direction)

            scheduler.advance(by: 51)
            window.layoutIfNeeded()
            XCTAssertFalse(strip.isHidden)
            XCTAssertFalse(hint.isHidden)
            XCTAssertFalse(strip.subviews.contains { $0 is UIButton })
            XCTAssertEqual(strip.subviews.compactMap { $0 as? UILabel }.count, 1, "No timer beside the hint")
            XCTAssertEqual(hint.textAlignment, direction == .rightToLeft ? .right : .left, "At the leading end")
            XCTAssertEqual(hint.text, lang("$agent_dictation_release_to_stop"))

            // Toward the leading end, where the cross stands, and toward the trailing end, where Send does
            let towardLeadingEnd: Double = direction == .rightToLeft ? 300 : -300
            controller.touchMoved(x: towardLeadingEnd)
            XCTAssertEqual(hint.text, lang("$agent_dictation_release_to_cancel"))
            controller.touchMoved(x: -towardLeadingEnd)
            XCTAssertEqual(hint.text, lang("$agent_dictation_release_to_send"))
            controller.touchMoved(x: 0)
            XCTAssertEqual(hint.text, lang("$agent_dictation_release_to_stop"))
        }
    }

    /// The hint comes in once the touch is a hold, not before, from behind the recording circle at the trailing end, on
    /// a spring and a quick fade; a tap's hands-free recording shows none
    @MainActor
    func testTheHintComesInOnceHeld() throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "Reduce Motion fades it")
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.isHidden = false
        defer { window.isHidden = true }
        let container = UIView(frame: window.bounds)
        window.addSubview(container)
        let strip = AgentDictationStripView()
        strip.frame = CGRect(x: 20, y: 400, width: 300, height: AgentComposerMetrics.minInputHeight)
        container.addSubview(strip)
        strip.update(AgentDictationState(phase: .holding))
        strip.layoutIfNeeded()
        let hint = try XCTUnwrap(strip.subviews.compactMap { $0 as? UILabel }.first)
        XCTAssertTrue(hint.isHidden, "Not before the touch is a hold")

        var held = AgentDictationState(phase: .holding)
        held.isHeld = true
        strip.update(held)
        XCTAssertFalse(hint.isHidden)
        let slide = try XCTUnwrap(hint.layer.animation(forKey: "slideIn") as? CASpringAnimation)
        let distance = try XCTUnwrap((slide.fromValue as? NSNumber)?.doubleValue)
        XCTAssertEqual(distance, AgentVoiceRecordingMetrics.hintEntranceTravel, accuracy: 0.001, "From the trailing end")
        XCTAssertTrue(slide.isAdditive)
        let dampingRatio = slide.damping / (2 * (slide.stiffness * slide.mass).squareRoot())
        XCTAssertEqual(dampingRatio, 0.55, accuracy: 0.01)
        let fade = try XCTUnwrap(hint.layer.animation(forKey: "fadeIn"))
        XCTAssertEqual(fade.duration, AgentDictationStripView.hintEntranceFadeDuration, accuracy: 0.001)

        let tapped = AgentDictationStripView()
        tapped.frame = strip.frame
        container.addSubview(tapped)
        tapped.update(AgentDictationState(phase: .holding))
        tapped.update(AgentDictationState(phase: .handsFree))
        let tappedHint = try XCTUnwrap(tapped.subviews.compactMap { $0 as? UILabel }.first)
        XCTAssertTrue(tappedHint.isHidden, "A tap has no hint")
    }

    /// A hands-free recording's cross stands in the field rather than in the panel, and nothing cancels the
    /// recognition: the panel only tells it goes on
    @MainActor
    func testNeitherHandsFreeRecordingNorRecognitionHasACancelInThePanel() throws {
        let strip = AgentDictationStripView()
        strip.frame = CGRect(x: 0, y: 0, width: 250, height: AgentComposerMetrics.minInputHeight)
        strip.update(AgentDictationState(phase: .handsFree))
        strip.layoutIfNeeded()
        XCTAssertFalse(strip.subviews.contains { $0 is UIButton })

        strip.update(AgentDictationState(phase: .recognizing))
        strip.layoutIfNeeded()
        XCTAssertFalse(strip.subviews.contains { $0 is UIButton })
        let status = try XCTUnwrap(strip.statusAccessibilityElement as? UILabel)
        XCTAssertFalse(status.isHidden)
        XCTAssertEqual(status.text, lang("$agent_dictation_recognizing"))
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
}
