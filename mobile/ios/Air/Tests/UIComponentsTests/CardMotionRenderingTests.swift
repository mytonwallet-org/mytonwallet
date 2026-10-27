import XCTest
import UIKit
@testable import UIComponents

@MainActor
final class CardMotionRenderingTests: XCTestCase {
    func testSwipeReturnsTiltContinuouslyWithoutPublishingLightingFrames() {
        for fps in [30.0, 60.0, 120.0] {
            let view = UIView(frame: CGRect(x: 0, y: 0, width: 358, height: 208))
            var publications = 0
            let driver = CardSurfaceMotionDriver(cardView: view) { _ in publications += 1 }
            driver.externallyDriven = true
            driver.input = .drag
            driver.setActive(true)
            driver.press(at: CGPoint(x: 0.9, y: -0.6), began: true)
            for _ in 0..<Int(fps * 0.1) { driver.advanceFrame(by: 1 / fps) }
            let touched = view.layer.transform
            XCTAssertFalse(CATransform3DIsIdentity(touched))
            driver.setActive(false, animated: true)
            XCTAssertTrue(CATransform3DEqualToTransform(view.layer.transform, touched), "Swipe recognition must preserve the exact visible pose")
            let frozenPublications = publications
            for _ in 0..<Int(fps * 0.1) { driver.advanceFrame(by: 1 / fps) }
            XCTAssertFalse(CATransform3DIsIdentity(view.layer.transform), "Return must remain visible after 100 ms")
            XCTAssertLessThan(abs(view.layer.transform.m31), abs(touched.m31))
            for _ in 0..<Int(fps) { driver.advanceFrame(by: 1 / fps) }
            XCTAssertTrue(CATransform3DIsIdentity(view.layer.transform))
            XCTAssertEqual(publications, frozenPublications, "Settling geometry must not wake the paused shader or publish light updates")
        }
    }

    func testSwipeReturnCanBeInterruptedOrCancelledForReuse() {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 358, height: 208))
        let driver = CardSurfaceMotionDriver(cardView: view) { _ in }
        driver.externallyDriven = true
        driver.input = .drag
        driver.setActive(true)
        driver.press(at: CGPoint(x: 0.8, y: 0.6), began: true)
        for _ in 0..<8 { driver.advanceFrame(by: 1 / 60) }
        driver.setActive(false, animated: true)
        for _ in 0..<4 { driver.advanceFrame(by: 1 / 60) }
        let returning = view.layer.transform
        driver.setActive(true, animated: true)
        driver.press(at: CGPoint(x: -0.8, y: -0.6), began: true)
        XCTAssertTrue(CATransform3DEqualToTransform(view.layer.transform, returning), "A second gesture starts from the current pose")
        driver.advanceFrame(by: 1 / 60)
        driver.setActive(false, animated: true)
        XCTAssertFalse(CATransform3DIsIdentity(view.layer.transform))
        driver.setActive(false)
        XCTAssertTrue(CATransform3DIsIdentity(view.layer.transform), "Reuse and disabled animations must cancel even an already inactive return")
        driver.advanceFrame(by: 1 / 60)
        XCTAssertTrue(CATransform3DIsIdentity(view.layer.transform))
    }

    func testStillArtworkUsesOnDemandFramesWhileGramKeepsAnimating() async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 232))
        window.rootViewController = UIViewController()
        window.isHidden = false
        defer { window.isHidden = true }
        let host = try XCTUnwrap(window.rootViewController?.view)
        for artwork in [CardSurfaceConfiguration.DefaultArtwork.myWallet, .gramWallet] {
            var surface: CardSurfaceConfiguration = artwork == .myWallet ? .myWallet : .gramWallet
            surface.motion = artwork == .myWallet ? .myDefault : .gramDefault
            let renderer = try XCTUnwrap(CardBackgroundMetalView(image: CardDefaultBackground.artwork(artwork).image,
                seed: nil, defaultArtwork: artwork))
            renderer.frame = host.bounds
            host.addSubview(renderer)
            renderer.configure(animateBackground: true, shine: true, light: .init(), surface: surface)
            XCTAssertEqual(renderer.isPaused, artwork == .myWallet)
            if artwork == .myWallet {
                try await Task.sleep(for: .milliseconds(150))
                let count = renderer.submittedFrameCount
                try await Task.sleep(for: .milliseconds(150))
                XCTAssertEqual(renderer.submittedFrameCount, count)
                renderer.setLight(.init(borderTilt: CGPoint(x: 0.5, y: -0.5)))
                try await Task.sleep(for: .milliseconds(100))
                XCTAssertGreaterThan(renderer.submittedFrameCount, count)
                renderer.pause()
                renderer.configure(animateBackground: true, shine: true, light: .init(), surface: surface, animateResume: true)
                XCTAssertFalse(renderer.isPaused)
                try await Task.sleep(for: .milliseconds(450))
                XCTAssertTrue(renderer.isPaused)
            }
            renderer.pause()
            renderer.removeFromSuperview()
        }
    }

    func testHomeProfilesRenderMaterialsTouchAndGramSoftLight() async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 232))
        window.rootViewController = UIViewController()
        window.isHidden = false
        defer { window.isHidden = true }
        let host = try XCTUnwrap(window.rootViewController?.view)
        let profiles: [CardMotionPreset] = [.myDefault, .standard, .silver, .gold, .platinum, .black, .gramDefault]
        var outputs = Set<Data>()
        for preset in profiles {
            var surface: CardSurfaceConfiguration = preset == .gramDefault ? .gramWallet : .myWallet
            surface.motion = preset
            surface.touchSpotEnabled = true
            let renderer = try XCTUnwrap(CardBackgroundMetalView(
                image: CardDefaultBackground.artwork(surface.defaultArtwork).image, seed: nil,
                defaultArtwork: surface.defaultArtwork, clock: CardBackgroundAnimationClock()))
            renderer.frame = host.bounds
            host.addSubview(renderer)
            renderer.layoutIfNeeded()
            var light = CardSurfaceLight(tilt: CGPoint(x: 0.4, y: -0.3), activity: 0.8,
                                         borderTilt: CGPoint(x: 0.4, y: -0.3))
            light.gramReflection = CardGramReflectionPose()
            renderer.configure(animateBackground: false, shine: true, light: light, surface: surface)
            renderer.showFrame(time: 3, strength: 0)
            let resting = try await pixels(renderer)
            outputs.insert(resting)
            light.touchSpot = .init(position: CGPoint(x: 0.5, y: 0.2), opacity: 1)
            renderer.configure(animateBackground: false, shine: true, light: light, surface: surface)
            renderer.showFrame(time: 3, strength: 0)
            let touched = try await pixels(renderer)
            XCTAssertNotEqual(resting, touched, "Touch glow remains independent of the surface-shine master switch")
            renderer.removeFromSuperview()
        }
        XCTAssertEqual(outputs.count, profiles.count, "Chosen materials and Gram reflection must produce distinct GPU frames")
    }

    func testGramReusesSurfaceWhileStarsAnimateAndInvalidatesForLightAndSize() async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 232))
        window.rootViewController = UIViewController(); window.isHidden = false
        defer { window.isHidden = true }
        let host = try XCTUnwrap(window.rootViewController?.view)
        var surface = CardSurfaceConfiguration.gramWallet; surface.motion = .gramDefault
        let image = CardDefaultBackground.artwork(.gramWallet).image
        let renderer = try XCTUnwrap(CardBackgroundMetalView(image: image, seed: nil, defaultArtwork: .gramWallet))
        renderer.frame = host.bounds; host.addSubview(renderer)
        var light = CardSurfaceLight(); light.gramReflection = .init(rotation: 0.5)
        renderer.configure(animateBackground: false, shine: true, light: light, surface: surface)
        let original = try await pixels(renderer), count = renderer.backgroundPassCount
        light.activity = 0.8
        renderer.configure(animateBackground: false, shine: true, light: light, surface: surface)
        let animated = try await pixels(renderer)
        XCTAssertNotEqual(animated, original, "Star appearance remains live while its underlying reflection is cached")
        XCTAssertEqual(renderer.backgroundPassCount, count)
        let reference = try XCTUnwrap(CardBackgroundMetalView(image: image, seed: nil, defaultArtwork: .gramWallet))
        reference.frame = host.bounds; host.addSubview(reference)
        reference.configure(animateBackground: false, shine: true, light: light, surface: surface)
        let uncached = try await pixels(reference)
        XCTAssertEqual(animated, uncached, "Reusing the base must be pixel-identical to recomputing it")
        light.gramReflection = .init(rotation: -0.6)
        renderer.configure(animateBackground: false, shine: true, light: light, surface: surface)
        let moved = try await pixels(renderer)
        XCTAssertNotEqual(moved, animated); XCTAssertEqual(renderer.backgroundPassCount, count + 1)
        renderer.frame.size.width = 360
        renderer.configure(animateBackground: false, shine: true, light: light, surface: surface)
        _ = try await pixels(renderer)
        XCTAssertEqual(renderer.backgroundPassCount, count + 2)
    }

    private func pixels(_ renderer: CardBackgroundMetalView) async throws -> Data {
        // Flush the coalesced input before freezing a frame for pixel comparison.
        renderer.draw()
        let image = await withCheckedContinuation { continuation in
            renderer.snapshot { continuation.resume(returning: $0) }
        }
        let pixels = try XCTUnwrap(image?.cgImage)
        XCTAssertGreaterThan(pixels.width, 400)
        return try XCTUnwrap(pixels.dataProvider?.data) as Data
    }
}
