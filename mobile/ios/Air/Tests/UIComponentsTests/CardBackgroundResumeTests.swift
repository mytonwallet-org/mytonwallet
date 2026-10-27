import XCTest
import UIKit
@testable import UIComponents

@MainActor
final class CardBackgroundResumeTests: XCTestCase {
    func testCollapsedCardRetainsFrozenRendererWithoutRedrawingUnchangedLayout() async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 232))
        window.rootViewController = UIViewController(); window.isHidden = false
        defer { window.isHidden = true }
        let host = try XCTUnwrap(window.rootViewController?.view)
        let background = MtwCardBackgroundView(); background.frame = host.bounds
        host.addSubview(background)
        var surface = CardSurfaceConfiguration.gramWallet; surface.motion = .gramDefault
        background.configure(nft: nil, isAnimationEnabled: true, isShineEnabled: true,
                             surface: surface, retainPausedRenderer: true)
        background.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(80))
        let renderer = try XCTUnwrap(background.subviews.flatMap(\.subviews).compactMap { $0 as? CardBackgroundMetalView }.first)
        background.configure(nft: nil, isAnimationEnabled: false, isShineEnabled: false,
                             surface: surface, retainPausedRenderer: true)
        try await Task.sleep(for: .milliseconds(50))
        let frames = renderer.submittedFrameCount
        let time = renderer.clock.blobTime
        for step in 0...10 {
            background.transform = CGAffineTransform(scaleX: 1 - CGFloat(step) * 0.08, y: 1 - CGFloat(step) * 0.08)
            background.setNeedsLayout(); background.layoutIfNeeded()
        }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(renderer.isSuspended)
        XCTAssertNotNil(renderer.superview)
        XCTAssertEqual(renderer.submittedFrameCount, frames)
        XCTAssertEqual(renderer.clock.blobTime, time)
        background.configure(nft: nil, isAnimationEnabled: true, isShineEnabled: true,
                             surface: surface, retainPausedRenderer: true)
        let resumed = background.subviews.flatMap(\.subviews).compactMap { $0 as? CardBackgroundMetalView }.first
        XCTAssertTrue(resumed === renderer, "Expanding reuses the same GPU resources")
        background.cancelImageLoading()
        XCTAssertNil(renderer.superview, "Real lifecycle exits still release the renderer")
    }

    private func snapshot(_ view: CardBackgroundMetalView) async throws -> Data {
        let image = await withCheckedContinuation { continuation in
            view.snapshot { continuation.resume(returning: $0) }
        }
        let cgImage = try XCTUnwrap(image?.cgImage)
        return try XCTUnwrap(cgImage.dataProvider?.data) as Data
    }

    func testCarouselResumeKeepsFirstGramFrameThenBlendsToLiveLight() async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 232))
        window.rootViewController = UIViewController()
        window.isHidden = false
        defer { window.isHidden = true }
        let host = try XCTUnwrap(window.rootViewController?.view)
        var surface = CardSurfaceConfiguration.gramWallet
        surface.motion = .gramDefault
        let renderer = try XCTUnwrap(CardBackgroundMetalView(
            image: CardDefaultBackground.artwork(.gramWallet).image, seed: nil, defaultArtwork: .gramWallet))
        renderer.frame = host.bounds
        host.addSubview(renderer)
        var old = CardSurfaceLight(borderTilt: CGPoint(x: 0.7, y: -0.4))
        old.gramReflection = .init(rotation: 1.1)
        var next = CardSurfaceLight(borderTilt: CGPoint(x: -0.6, y: 0.3))
        next.gramReflection = .init(rotation: -0.8)
        renderer.configure(animateBackground: false, shine: true, light: old, surface: surface)
        let before = try await snapshot(renderer)
        renderer.setLight(CardSurfaceLight())
        let paused = try await snapshot(renderer)
        XCTAssertEqual(paused, before, "A reset input must not repaint a suspended reflection")
        renderer.configure(animateBackground: false, shine: true, light: next, surface: surface, animateResume: true)
        renderer.draw()
        let first = try await snapshot(renderer)
        XCTAssertEqual(first, before, "The first frame after snapping must be the frozen Gram reflection, including its stars")
        renderer.configure(animateBackground: false, shine: true, light: next, surface: surface, animateResume: true)
        renderer.draw()
        try await Task.sleep(for: .milliseconds(120))
        let middle = try await snapshot(renderer)
        XCTAssertNotEqual(middle, before, "The reflection must already be moving during the transition")
        // Another swipe can interrupt the handoff. Resume from that actual intermediate frame.
        renderer.configure(animateBackground: false, shine: true, light: next, surface: surface, animateResume: true)
        renderer.draw()
        let interrupted = try await snapshot(renderer)
        XCTAssertEqual(interrupted, middle)
        renderer.configure(animateBackground: false, shine: true, light: next, surface: surface, animateResume: true)
        renderer.draw()
        try await Task.sleep(for: .milliseconds(350))
        let settled = try await snapshot(renderer)
        renderer.configure(animateBackground: false, shine: true, light: next, surface: surface)
        let exact = try await snapshot(renderer)
        XCTAssertEqual(exact, settled, "After 280 ms the exact original shader/light settings are restored")
        XCTAssertNotEqual(settled, before)
    }

    func testSuspensionNotificationFreezesInputAndCapturesTheVisibleCard() async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 232))
        window.rootViewController = UIViewController()
        window.isHidden = false
        let host = try XCTUnwrap(window.rootViewController?.view)
        let background = MtwCardBackgroundView()
        background.frame = host.bounds
        host.addSubview(background)
        var light = CardSurfaceLight()
        let interaction = CardSurfaceInteraction(container: host, surface: background) {
            light = $0
            background.setLight($0)
        }
        defer {
            interaction.setActive(false)
            window.isHidden = true
            NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        }
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        interaction.input = .sweep
        interaction.setActive(true)
        background.configure(nft: nil, isAnimationEnabled: true, isShineEnabled: true, surface: .gramWallet)
        background.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(250))
        let metal = try XCTUnwrap(background.subviews.flatMap(\.subviews).compactMap { $0 as? CardBackgroundMetalView }.first)
        let clock = metal.clock
        let before = light
        XCTAssertGreaterThan(before.activity, 0)
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        XCTAssertTrue(metal.isSuspended, "Pause immediately, before deferred environment subscribers run")
        XCTAssertFalse(CardBackgroundAnimationEnvironment.shared.applicationActive)
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(light, before)
        XCTAssertEqual(metal.clock.blobTime, clock.blobTime)
        XCTAssertNil(metal.superview, "Replace the paused renderer only after the current still is ready")
        let still = try XCTUnwrap(background.subviews.flatMap(\.subviews).compactMap { $0 as? UIImageView }.first?.image?.cgImage)
        XCTAssertEqual(still.bitmapInfo.rawValue, CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        try await Task.sleep(for: .milliseconds(150))
        let resumed = try XCTUnwrap(background.subviews.flatMap(\.subviews).compactMap { $0 as? CardBackgroundMetalView }.first)
        XCTAssertFalse(resumed.isSuspended)
        XCTAssertGreaterThan(resumed.clock.blobTime, clock.blobTime)
        XCTAssertLessThan(resumed.clock.blobTime - clock.blobTime, 0.65)
        XCTAssertGreaterThan(light.activity, 0)
    }

    func testFrozenFrameAndPhaseSurvivePauseAndRendererRecreation() async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 232))
        window.rootViewController = UIViewController()
        window.isHidden = false
        defer { window.isHidden = true }
        let host = try XCTUnwrap(window.rootViewController?.view)
        var circular = CardSurfaceConfiguration.myWallet
        circular.touchSpotEnabled = true
        for surface in [CardSurfaceConfiguration.myWallet, .gramWallet, circular] {
            let image = CardDefaultBackground.artwork(surface.defaultArtwork).image
            var clock = CardBackgroundAnimationClock()
            clock.advance(by: 17, press: 0.8, activity: 1)
            let light = CardSurfaceLight(tilt: CGPoint(x: 0.3, y: -0.4), activity: 0.7, press: 0.6,
                touchSpot: surface.touchSpotEnabled ? .init(position: CGPoint(x: 0.5, y: -0.5), opacity: 0.8) : nil)
            let metal = try XCTUnwrap(CardBackgroundMetalView(image: image, seed: nil,
                defaultArtwork: surface.defaultArtwork, clock: clock))
            metal.frame = host.bounds
            host.addSubview(metal)
            metal.configure(animateBackground: true, shine: true, light: light, surface: surface)
            metal.isPaused = true
            metal.draw()
            let before = try await snapshot(metal)
            XCTAssertTrue(metal.isSuspended)
            XCTAssertEqual(metal.clock.blobTime, clock.blobTime)
            // Neither layout nor input updates may render or advance a suspended card.
            metal.setLight(CardSurfaceLight())
            metal.draw()
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertEqual(metal.clock.blobTime, clock.blobTime)
            let paused = try await snapshot(metal)
            XCTAssertEqual(paused, before)

            metal.configure(animateBackground: true, shine: true, light: light, surface: surface)
            metal.isPaused = true
            metal.draw()
            XCTAssertEqual(metal.clock.blobTime, clock.blobTime, "Resume must not count suspended time")
            let resumed = try await snapshot(metal)
            XCTAssertEqual(resumed, before)
            metal.removeFromSuperview()

            let replacement = try XCTUnwrap(CardBackgroundMetalView(image: image, seed: nil,
                defaultArtwork: surface.defaultArtwork, clock: metal.clock))
            replacement.frame = host.bounds
            host.addSubview(replacement)
            replacement.configure(animateBackground: true, shine: true, light: light, surface: surface)
            replacement.isPaused = true
            replacement.draw()
            let recreated = try await snapshot(replacement)
            XCTAssertEqual(recreated, before,
                           "The first resumed frame must match the still, including blobs, stars and shine")
            replacement.removeFromSuperview()
        }
    }
}
