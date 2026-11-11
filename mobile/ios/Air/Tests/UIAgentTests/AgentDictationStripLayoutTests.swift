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

    @MainActor
    func testHoldingShowsDotAndSlidingHint() async throws {
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
            let dot = try XCTUnwrap(strip.subviews.first {
                !($0 is UILabel) && !($0 is UIButton)
                    && $0.layer.cornerRadius == AgentVoiceRecordingMetrics.recordingDotDiameter / 2
            })
            let hint = try XCTUnwrap(strip.subviews.compactMap { $0 as? UILabel }.first)
            let cancel = try XCTUnwrap(strip.cancelAccessibilityElement as? UIButton)
            XCTAssertEqual(strip.effectiveUserInterfaceLayoutDirection, direction)
            XCTAssertEqual(dot.bounds.width, AgentVoiceRecordingMetrics.recordingDotDiameter)

            scheduler.advance(by: 51)
            window.layoutIfNeeded()
            XCTAssertFalse(strip.isHidden)
            XCTAssertFalse(dot.isHidden)
            XCTAssertFalse(hint.isHidden)
            XCTAssertTrue(cancel.isHidden)
            XCTAssertEqual(strip.subviews.compactMap { $0 as? UILabel }.count, 1, "No timer beside the hint")
            if direction == .leftToRight {
                XCTAssertLessThanOrEqual(dot.frame.maxX, hint.frame.minX)
            } else {
                XCTAssertLessThanOrEqual(hint.frame.maxX, dot.frame.minX)
            }

            let initialHintX = hint.frame.midX
            let dotFrame = dot.frame
            let dragX = direction == .rightToLeft ? 22.0 : -22.0
            controller.touchMoved(x: dragX, y: 0)
            window.layoutIfNeeded()
            XCTAssertEqual(hint.frame.midX, initialHintX + dragX, accuracy: 0.01)
            XCTAssertEqual(hint.alpha, 0.8, accuracy: 0.01)
            XCTAssertEqual(dot.frame, dotFrame)
        }
    }

    /// The recording dot comes in with "Slide to cancel" once the touch is a hold, not before, the two as one from
    /// behind the recording circle at the trailing end, on the pause hint's spring and quick fade, and they leave the
    /// way they came as the recording ends
    @MainActor
    func testRecordingDotComesInWithTheCancelHintOnceHeldAndLeavesWithIt() throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "Reduce Motion fades them")
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
        let dot = try XCTUnwrap(strip.subviews.first {
            !($0 is UILabel) && !($0 is UIButton)
                && $0.layer.cornerRadius == AgentVoiceRecordingMetrics.recordingDotDiameter / 2
        })
        let hint = try XCTUnwrap(strip.subviews.compactMap { $0 as? UILabel }.first)
        XCTAssertTrue(dot.isHidden, "Not before the touch is a hold")
        XCTAssertTrue(hint.isHidden, "Not before the touch is a hold")

        var held = AgentDictationState(phase: .holding)
        held.isHeld = true
        strip.update(held)
        XCTAssertFalse(dot.isHidden)
        XCTAssertFalse(hint.isHidden)
        let dotSlide = try XCTUnwrap(dot.layer.animation(forKey: "slideIn") as? CASpringAnimation)
        let hintSlide = try XCTUnwrap(hint.layer.animation(forKey: "slideIn") as? CASpringAnimation)
        let dotDistance = try XCTUnwrap((dotSlide.fromValue as? NSNumber)?.doubleValue)
        let hintDistance = try XCTUnwrap((hintSlide.fromValue as? NSNumber)?.doubleValue)
        XCTAssertEqual(dotDistance, hintDistance, accuracy: 0.001, "The two move as one")
        XCTAssertEqual(hintDistance, AgentVoiceRecordingMetrics.hintEntranceTravel, accuracy: 0.001, "From the trailing end")
        XCTAssertEqual(dotSlide.duration, hintSlide.duration)
        XCTAssertTrue(dotSlide.isAdditive && hintSlide.isAdditive)
        let dampingRatio = hintSlide.damping / (2 * (hintSlide.stiffness * hintSlide.mass).squareRoot())
        XCTAssertEqual(dampingRatio, 0.55, accuracy: 0.01, "The pause hint's spring")
        let fade = try XCTUnwrap(hint.layer.animation(forKey: "fadeIn"))
        XCTAssertEqual(fade.duration, AgentDictationStripView.hintEntranceFadeDuration, accuracy: 0.001)

        strip.update(AgentDictationState(phase: .recognizing))
        XCTAssertTrue(dot.isHidden)
        let panel = try XCTUnwrap(strip.leavingPanel)
        XCTAssertTrue(panel.superview === container)
        XCTAssertTrue(panel.clipsToBounds, "Clipped to the strip, inside the field")
        XCTAssertEqual(panel.frame, strip.frame)
        XCTAssertEqual(panel.subviews.count, 2, "The dot and the hint leave")
        let travel = panel.subviews.map(\.transform.tx)
        XCTAssertTrue(travel.allSatisfy { $0 > 0 }, "Past the trailing end, the way they came")
        XCTAssertEqual(Set(travel).count, 1, "As one")
        XCTAssertTrue(panel.subviews.allSatisfy { $0.alpha == 0 }, "Fading as they go")
    }

    /// A touch that turns out a tap records hands-free: no hint ever shows, and the dot slides in alone from past the
    /// field's leading end, where it stands
    @MainActor
    func testATapBringsTheDotInFromTheLeadingEndAlone() throws {
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
        let dot = try XCTUnwrap(strip.subviews.first { $0.backgroundColor == AgentVoiceRecordingMetrics.recordingDotColor })
        let hint = try XCTUnwrap(strip.subviews.compactMap { $0 as? UILabel }.first)
        XCTAssertTrue(dot.isHidden)

        strip.update(AgentDictationState(phase: .handsFree))
        XCTAssertTrue(hint.isHidden, "No hint")
        XCTAssertFalse(dot.isHidden)
        XCTAssertNil(strip.leavingPanel, "Nothing leaves")
        let slide = try XCTUnwrap(dot.layer.animation(forKey: "slideIn") as? CABasicAnimation)
        let start = dot.layer.position.x + CGFloat((slide.fromValue as? NSNumber)?.doubleValue ?? 0)
        XCTAssertLessThan(start, 0, "From past the leading end")
        XCTAssertEqual(dot.frame.minX, 0, "Standing at the leading end")
    }

    /// After a slide to cancel, the dot leaves with "Slide to cancel", toward the leading end, as far and as fast and
    /// fading alike. Clipped to the strip, it never draws outside the field, and it is gone once the hint is.
    @MainActor
    func testRecordingDotLeavesWithTheHintAfterASlideToCancelInsideTheField() async throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "Reduce Motion fades them")
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.isHidden = false
        defer { window.isHidden = true }
        let container = UIView(frame: window.bounds)
        window.addSubview(container)
        let strip = AgentDictationStripView()
        strip.frame = CGRect(x: 20, y: 400, width: 300, height: AgentComposerMetrics.minInputHeight)
        container.addSubview(strip)
        var held = AgentDictationState(phase: .holding)
        held.isHeld = true
        strip.update(held)
        strip.layoutIfNeeded()
        held.dragX = -40
        strip.update(held)
        strip.layoutIfNeeded()

        strip.update(AgentDictationState(phase: .idle))
        let panel = try XCTUnwrap(strip.leavingPanel)
        XCTAssertTrue(panel.clipsToBounds)
        XCTAssertEqual(panel.frame, strip.frame, "Within the field the strip spans")
        XCTAssertEqual(panel.subviews.count, 2, "The dot and the hint leave")
        let travel = panel.subviews.map(\.transform.tx)
        XCTAssertTrue(travel.allSatisfy { $0 < 0 }, "Toward the leading end, the way the hint went")
        XCTAssertEqual(Set(travel).count, 1, "As one")
        for _ in 0..<60 where panel.superview != nil {
            for view in panel.subviews {
                // What shows of it is inside the strip
                let shown = (view.layer.presentation()?.frame ?? view.frame).intersection(panel.bounds)
                XCTAssertTrue(shown.isNull || panel.bounds.contains(shown))
            }
            try await Task.sleep(for: .milliseconds(16))
        }
        XCTAssertNil(panel.superview, "Gone once the transition ends")
    }

    /// A hands-free recording's cross floats above the field rather than in the panel, whose dot stands at its leading
    /// end; recognition shows Telegram's Cancel
    @MainActor
    func testHandsFreeRecordingHasNoCrossInThePanelAndRecognitionShowsTelegramsCancel() throws {
        let strip = AgentDictationStripView()
        strip.frame = CGRect(x: 0, y: 0, width: 250, height: AgentComposerMetrics.minInputHeight)
        strip.update(AgentDictationState(phase: .handsFree))
        strip.layoutIfNeeded()
        let cancel = try XCTUnwrap(strip.cancelAccessibilityElement as? UIButton)
        XCTAssertTrue(cancel.isHidden)
        let dot = try XCTUnwrap(strip.subviews.first { $0.backgroundColor == AgentVoiceRecordingMetrics.recordingDotColor })
        XCTAssertEqual(dot.frame.minX, 0, "The dot at the leading end")

        strip.update(AgentDictationState(phase: .recognizing))
        strip.layoutIfNeeded()
        XCTAssertFalse(cancel.isHidden)
        XCTAssertEqual(cancel.accessibilityLabel, lang("Cancel"))
        XCTAssertEqual(cancel.title(for: .normal), lang("Cancel"))
        XCTAssertEqual(cancel.titleLabel?.font.pointSize, AgentVoiceRecordingMetrics.cancelFontSize)
        XCTAssertEqual(cancel.frame.maxX, strip.bounds.maxX, accuracy: 0.5)
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
}
