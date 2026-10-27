import XCTest
import Metal
import SwiftUI
import UIKit
import GRDB
import Dependencies
@testable import WalletCore
import WalletContext
import WalletResources
@testable import UIComponents

@MainActor
final class HeroParticleTests: XCTestCase {
    @MainActor
    func testShortAmountCloudExpandsContinuouslyWithoutReseedingOrFinalJump() throws {
        let dust = CardSpoilerDustView(frame: CGRect(x: 0, y: 0, width: 380, height: 120))
        dust.fieldRect = CGRect(x: 78, y: 40, width: 224, height: 40)
        dust.setConcealed(true, animated: false)
        let full = dust.transitionSamples()
        XCTAssertFalse(full.isEmpty)
        let source = CGRect(x: 170, y: 40, width: 40, height: 40)
        var widths: [CGFloat] = []
        for frame in 0...60 {
            dust.setTransitionFootprint(source, progress: CGFloat(frame) / 60)
            let samples = dust.transitionSamples()
            XCTAssertEqual(samples.count, full.count)
            XCTAssertEqual(samples.map(\.opacity), full.map(\.opacity))
            XCTAssertEqual(samples.map(\.diameter), full.map(\.diameter))
            widths.append((samples.map { $0.position.x }.max() ?? 0) - (samples.map { $0.position.x }.min() ?? 0))
        }
        for (a,b) in zip(widths, widths.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b, a)
            XCTAssertLessThan(b - a, 8, "A short amount must not suddenly become a full-width cloud")
        }
        let before = dust.transitionSamples().map(\.position)
        dust.setTransitionFootprint(nil)
        XCTAssertEqual(dust.transitionSamples().map(\.position), before)
        XCTAssertEqual(before, full.map(\.position), "Final hidden geometry and particle identities remain exact")
        dust.setTransitionFootprint(source, progress: 0.5)
        let middle = dust.transitionSamples().map(\.position)
        dust.setTransitionFootprint(source, progress: 0.6)
        dust.setTransitionFootprint(source, progress: 0.5)
        XCTAssertEqual(dust.transitionSamples().map(\.position), middle, "Interrupted reveal retraces the same geometry")
        dust.reset()
    }

    override func setUp() async throws {
        try await super.setUp()
        let db = try DatabaseQueue()
        try makeMigrator().migrate(db)
        SettingsStore.liveValue.use(db: db)
    }

    override func tearDown() async throws {
        SettingsStore.liveValue.clean()
        try await super.tearDown()
    }

    // Snapshot tests need the app-hosted runner in run_hero_particle_tests.py.
    // A command-line XCTest agent has no scene and cannot draw UIKit content.
    private func show(_ view: UIView, size: CGSize = CGSize(width: 380, height: 90)) throws -> UIWindow {
        _ = WalletResourcesBundle.bundle.load()
        AppStorageHelper.animations = true
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            throw XCTSkip("Requires the app-hosted hero particle test runner")
        }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIViewController()
        window.rootViewController!.view.backgroundColor = .systemBackground
        window.rootViewController!.view.addSubview(view)
        view.frame = CGRect(origin: CGPoint(x: 10, y: 180), size: size)
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        view.layoutIfNeeded()
        return window
    }

    func testSelectedPresetRoundTripsEveryExportedParameter() throws {
        let json = #"{"size":2.2,"frequency":0.75,"spread":24,"effect":1,"disintegration":{"blendDuration":0.65,"blendStart":0.1,"destinationMix":0.2,"easing":1,"finalSize":0.7,"fragmentSize":1.6,"hideDuration":0.7,"lift":0,"originInfluence":1,"revealDuration":0.6,"rotation":40,"stagger":0.2,"timingRandomness":0,"travel":10,"turbulence":1}}"#
        let imported = try JSONDecoder().decode(CardParticleSettings.self, from: Data(json.utf8))
        XCTAssertEqual(CardParticleSettings.hero, imported)
        XCTAssertEqual(imported.clamped, imported)
    }

    func testConcealedFieldsMatchProductionMasksRegardlessOfAmount() throws {
        let host = UIView()
        let window = try show(host, size: CGSize(width: 380, height: 180))
        defer { window.isHidden = true }
        let balance = MtwCardBalanceLabelView(), change = MtwCardChangeView()
        host.addSubview(balance); host.addSubview(change)
        balance.frame = CGRect(x: 0, y: 0, width: 380, height: 90)
        change.frame = CGRect(x: 0, y: 110, width: 380, height: 32)
        for (style, expectedWidth) in [(MtwCardBalanceView.Style.homeCard, 224.0), (.homeCollaped, 196), (.homeNavigationBarCollapsed, 210)] {
            var firstField: CGRect?
            var firstCount: Int?
            for amount in [0.0, 1.23, 13235.35, 987654321.99] {
                for hidden in [false, true] {
                    balance.configure(balance: .fromDouble(amount, .USD), style: style, nft: nil,
                        usesCardGradient: true, isHidden: hidden, isScrolling: false, animates: false)
                    change.configure(balance: .fromDouble(amount, .USD), previous: .fromDouble(amount / 2, .USD),
                        percent: 12.34, nft: nil, isHidden: hidden, animates: false)
                    balance.layoutIfNeeded(); change.layoutIfNeeded()
                    let dust = try XCTUnwrap(balance.subviews.compactMap { $0 as? CardSpoilerDustView }.first)
                    let portfolio = try XCTUnwrap(change.subviews.compactMap { $0 as? CardSpoilerDustView }.first)
                    XCTAssertEqual(dust.fieldRect.width, expectedWidth)
                    XCTAssertEqual(portfolio.fieldRect.size, CGSize(width: 130, height: 26))
                    XCTAssertEqual(dust.convert(dust.fieldRect, to: balance).midX, balance.bounds.midX)
                    if let firstField { XCTAssertEqual(dust.fieldRect, firstField) } else { firstField = dust.fieldRect }
                    if hidden {
                        if let firstCount { XCTAssertEqual(dust.particleCount, firstCount) } else { firstCount = dust.particleCount }
                    }
                }
            }
        }
        balance.prepareForReuse(); change.prepareForReuse()
    }

    func testExpandedAndCollapsedBalancesUseParticlesAndRevealLatestAmount() async throws {
        for (style, cardGradient) in [(MtwCardBalanceView.Style.homeCard, true), (.homeCollaped, false), (.homeNavigationBarCollapsed, false)] {
            let balance = MtwCardBalanceLabelView()
            let window = try show(balance)
            defer { window.isHidden = true; balance.prepareForReuse() }
            func configure(_ amount: Double, hidden: Bool) {
                balance.configure(balance: .fromDouble(amount, .USD), style: style, nft: nil,
                    usesCardGradient: cardGradient, isHidden: hidden, isScrolling: false, animates: true)
                balance.layoutIfNeeded()
            }
            configure(13235.35, hidden: false)
            try await Task.sleep(for: .milliseconds(80))
            configure(13235.35, hidden: true)
            XCTAssertNotNil(balance.elementTransition.overlay)
            XCTAssertEqual(balance.accessibilityLabel, lang("Tap to reveal"))
            balance.elementTransition.advance(by: 2)
            let dust = try XCTUnwrap(balance.subviews.compactMap { $0 as? CardSpoilerDustView }.first)
            XCTAssertFalse(dust.isHidden)
            XCTAssertEqual(dust.settings, .hero)
            let before = dust.transitionSamples().map(\.position)
            configure(14089.27, hidden: true)
            XCTAssertNil(balance.elementTransition.overlay)
            let after = dust.transitionSamples().map(\.position)
            XCTAssertGreaterThanOrEqual(after.count, before.count)
            XCTAssertTrue(dust.transitionSamples().dropFirst(before.count).allSatisfy { $0.opacity == 0 },
                "New density enters invisibly while existing dots retain their positions")
            let movement = zip(before, after).map { hypot($0.x - $1.x, $0.y - $1.y) }.max() ?? 0
            XCTAssertLessThan(movement, 0.001, "Hidden balance updates must not regenerate particles")
            configure(14089.27, hidden: false)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertNotNil(balance.elementTransition.overlay)
            XCTAssertEqual(balance.displayedBalance, .fromDouble(14089.27, .USD))
            balance.elementTransition.advance(by: 2)
            XCTAssertTrue(dust.isHidden)
        }
    }

    func testHeroHostingKeepsLayoutPrivacyAndLocalRevealForTokenAndTransactionSizes() async throws {
        for size in [17.0, 34.0, 40.0] {
            let view = HeroParticleHostingView(frame: .zero)
            let window = try show(view)
            defer { window.isHidden = true; view.effect.reset() }
            func content(_ value: String) -> some View {
                Text(value).font(.system(size: size, weight: .bold)).foregroundStyle(Color.primary).lineLimit(1)
            }
            view.update(content: content("123.45 TON"), hidden: false, color: .label)
            let dimensions = view.fittingSize(CGSize(width: 360, height: 100))
            XCTAssertGreaterThan(dimensions.width, 50)
            XCTAssertLessThanOrEqual(dimensions.width, 360)
            XCTAssertGreaterThan(dimensions.height, 10)
            view.bounds.size = dimensions
            view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(60))
            view.update(content: content("123.45 TON"), hidden: true, color: .label)
            XCTAssertNotNil(view.effect.transition.overlay)
            XCTAssertTrue(view.hosting?.accessibilityElementsHidden == true)
            view.effect.transition.advance(by: 2)
            XCTAssertEqual(view.fittingSize(CGSize(width: 360, height: 100)), dimensions)
            XCTAssertFalse(view.effect.dust.isHidden)
            XCTAssertNil(view.effect.dust.interactionPoint, "Ordinary heroes never receive a play finger")
            var reveals = 0
            view.onReveal = { reveals += 1 }
            try XCTUnwrap(view.subviews.compactMap { $0 as? UIButton }.first).sendActions(for: .touchUpInside)
            XCTAssertEqual(reveals, 1)
            view.update(content: content("789.12 TON"), hidden: false, color: .label)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertNotNil(view.effect.transition.overlay)
            view.effect.transition.advance(by: 2)
            XCTAssertFalse(view.hosting?.isHidden ?? true)
            XCTAssertFalse(view.hosting?.accessibilityElementsHidden ?? true)
            view.update(content: content("789.12 TON"), hidden: true, color: .label)
            view.removeFromSuperview()
            XCTAssertNil(view.effect.transition.overlay)
            XCTAssertFalse(view.effect.dust.isAnimating)
        }
    }

    func testLongHeroAmountRespectsNarrowScreenProposal() throws {
        let view = HeroParticleHostingView(frame: .zero)
        let window = try show(view)
        defer { window.isHidden = true; view.effect.reset() }
        view.update(content: Text("123456789.123456 TON").font(.system(size: 40, weight: .bold))
            .lineLimit(1).minimumScaleFactor(0.2), hidden: false, color: .label)
        let size = view.fittingSize(CGSize(width: 220, height: 80))
        XCTAssertLessThanOrEqual(size.width, 220)
        XCTAssertGreaterThan(size.height, 10)
        XCTAssertLessThan(size.height, 80)
    }

    func testHeroPrivacyPreservesAmountBaselineAndTokenIconAlignment() async throws {
        let originalPrivacy = AppStorageHelper.isSensitiveDataHidden
        defer { AppStorageHelper.isSensitiveDataHidden = originalPrivacy }
        for hidden in [false, true] {
            AppStorageHelper.isSensitiveDataHidden = hidden
            for (value, fontSize, width) in [("0 TON", 34.0, 360.0), ("123.45 TON", 34.0, 360.0), ("∞ TON", 34, 360),
                                           ("+123.45 TON", 17, 360), ("123456789.12 TON", 34, 180)] {
                let text = Text(value).font(.system(size: fontSize, weight: .bold))
                    .lineLimit(1).minimumScaleFactor(0.2)
                var reference: (CGSize, CGFloat)?
                var particles: (CGSize, CGFloat)?
                let plain = HostingView {
                    HeroBaselineProbe(record: { reference = ($0, $1) }) { text }
                }
                let privateText = withDependencies {
                    $0.sensitiveData = SensitiveData.liveValue
                } operation: {
                    text.heroSensitiveData()
                }
                let modified = HostingView {
                    HeroBaselineProbe(record: { particles = ($0, $1) }) { privateText }
                }
                let container = UIView()
                container.addSubview(plain); container.addSubview(modified)
                let window = try show(container, size: CGSize(width: width, height: 140))
                defer { window.isHidden = true }
                plain.frame = CGRect(x: 0, y: 0, width: width, height: 60)
                modified.frame = CGRect(x: 0, y: 70, width: width, height: 60)
                plain.layoutIfNeeded(); modified.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(60))
                let expected = try XCTUnwrap(reference), actual = try XCTUnwrap(particles)
                XCTAssertEqual(actual.0.width, hidden ? 132 : expected.0.width, accuracy: 0.5)
                XCTAssertEqual(actual.0.height, expected.0.height, accuracy: 0.5)
                XCTAssertEqual(actual.1, expected.1, accuracy: 0.5,
                    "Privacy must keep the text baseline used by AmountIconRow, including when hidden")
                if hidden {
                    func findHero(in view: UIView) -> HeroParticleHostingView? {
                        if let hero = view as? HeroParticleHostingView { return hero }
                        return view.subviews.lazy.compactMap { findHero(in: $0) }.first
                    }
                    let hero = try XCTUnwrap(findHero(in: modified))
                    XCTAssertEqual(hero.effect.dust.fieldRect.size, CGSize(width: 132, height: 33))
                    let button = try XCTUnwrap(hero.subviews.compactMap { $0 as? UIButton }.first)
                    let center = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: window)
                    XCTAssertTrue(window.hitTest(center, with: nil) === button,
                        "The invisible layout carrier must not disable the overlay's reveal button")
                    for x in [hero.effect.dust.fieldRect.minX + 4, hero.effect.dust.fieldRect.maxX - 4] {
                        let edge = hero.effect.dust.convert(CGPoint(x: x, y: hero.effect.dust.fieldRect.midY), to: window)
                        XCTAssertTrue(window.hitTest(edge, with: nil) === button, "The entire fixed mask must reveal a short balance")
                    }
                    XCTAssertTrue(hero.hosting?.accessibilityElementsHidden == true)
                }
            }
        }
    }

    func testPlayGestureAlonePublishesParticleTouchAndClearsOnEveryExit() throws {
        let container = UIView(), surface = UIView()
        container.addSubview(surface)
        let window = try show(container, size: CGSize(width: 380, height: 232))
        defer { window.isHidden = true }
        surface.frame = container.bounds
        let interaction = CardSurfaceInteraction(container: container, surface: surface, onLight: { _ in })
        var configuration = CardSurfaceConfiguration.myWallet
        configuration.motion = .myDefault
        interaction.configure(surface: configuration)
        interaction.setActive(true)
        var touches: [CGPoint?] = []
        interaction.onPlayTouch = { touches.append($0) }
        let observer = try XCTUnwrap(container.gestureRecognizers?.compactMap { $0 as? CardTouchObserver }.first)
        observer.onPress?(CGPoint(x: 0.5, y: -0.5), true)
        XCTAssertTrue(touches.isEmpty, "A tap or a swipe must not repel particles")
        let hold = TestHold()
        hold.testLocation = CGPoint(x: 285, y: 58)
        hold.testState = .began
        interaction.perform(NSSelectorFromString("holdChanged:"), with: hold)
        XCTAssertEqual(touches.last!, CGPoint(x: 285, y: 58))
        hold.testState = .changed
        hold.testLocation = CGPoint(x: 190, y: 116)
        interaction.perform(NSSelectorFromString("holdChanged:"), with: hold)
        XCTAssertEqual(touches.last!, CGPoint(x: 190, y: 116), "Hold updates must reach particles even without an observer callback")
        observer.onRelease?(false)
        XCTAssertNil(touches.last!)
        observer.onPress?(.zero, true)
        hold.testState = .began
        interaction.perform(NSSelectorFromString("holdChanged:"), with: hold)
        interaction.setActive(false)
        XCTAssertNil(touches.last!)
    }

    func testAnimationDisableAndBackgroundSettleWithoutExposingHiddenText() async throws {
        let view = HeroParticleHostingView(frame: .zero)
        let window = try show(view)
        defer { window.isHidden = true; AppStorageHelper.animations = true }
        let text = Text("987.65").font(.system(size: 40))
        view.update(content: text, hidden: false, color: .label)
        try await Task.sleep(for: .milliseconds(60))
        view.update(content: text, hidden: true, color: .label)
        XCTAssertNotNil(view.effect.transition.overlay)
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        XCTAssertNil(view.effect.transition.overlay)
        XCTAssertTrue(view.hosting?.isHidden == true)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        AppStorageHelper.animations = false
        try await Task.sleep(for: .milliseconds(60))
        view.update(content: text, hidden: false, color: .label)
        XCTAssertNil(view.effect.transition.overlay)
        view.update(content: text, hidden: true, color: .label)
        XCTAssertNil(view.effect.transition.overlay)
        XCTAssertTrue(view.hosting?.isHidden == true)
        XCTAssertFalse(view.effect.dust.isHidden)
        XCTAssertFalse(view.effect.dust.isAnimating)
    }
}

private final class TestHold: UILongPressGestureRecognizer {
    var testLocation = CGPoint.zero
    override func location(in view: UIView?) -> CGPoint { testLocation }
    var testState = UIGestureRecognizer.State.possible
    override var state: UIGestureRecognizer.State { get { testState } set { testState = newValue } }
}

private struct HeroBaselineProbe: Layout {
    var record: (CGSize, CGFloat) -> Void
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let dimensions = subviews[0].dimensions(in: proposal)
        let size = CGSize(width: dimensions.width, height: dimensions.height)
        record(size, dimensions[.firstTextBaseline])
        return size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews[0].place(at: bounds.origin, proposal: proposal)
    }
}

extension HeroParticleTests {
    func testCaptureDoesNotMutateLiveViewOrRequestScreenUpdates() async throws {
        let visibility = UIView()
        let window = try show(visibility)
        defer { window.isHidden = true }
        let source = CaptureTrackingView(frame: visibility.bounds)
        visibility.addSubview(source)
        let label = UILabel(frame: source.bounds); label.text = "123.45"; source.addSubview(label)
        let mask = CAShapeLayer(); mask.path = UIBezierPath(rect: source.bounds).cgPath
        source.layer.mask = mask; source.alpha = 0.8
        visibility.isHidden = true
        try await Task.sleep(for: .milliseconds(60))
        source.hiddenWrites = 0
        let originalAlpha = source.alpha
        _ = CardElementTransition.capture(source)
        XCTAssertEqual(source.screenUpdateRequests, [false])
        XCTAssertEqual(source.hiddenWrites, 0)
        XCTAssertTrue(visibility.isHidden); XCTAssertFalse(source.isHidden)
        XCTAssertTrue(source.layer.mask === mask); XCTAssertEqual(source.alpha, originalAlpha)
    }

    func testRevealFragmentsContainTheLatestHiddenAmount() async throws {
        let view = HeroParticleHostingView(frame: .zero)
        let window = try show(view)
        defer { window.isHidden = true; view.effect.reset() }
        func text(_ value: String) -> some View { Text(value).font(.system(size: 40)).foregroundStyle(Color.white) }
        view.update(content: text("111.11 TON"), hidden: true, color: .white)
        try await Task.sleep(for: .milliseconds(80))
        let source = try XCTUnwrap(view.hosting?.contentView)
        let previous = CardElementTransition.capture(source)
        view.update(content: text("888.88 TON"), hidden: false, color: .white)
        XCTAssertTrue(view.hosting?.isHidden == true)
        for _ in 0..<30 {
            if view.effect.transition.overlay != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let overlay = try XCTUnwrap(view.effect.transition.overlay)
        let progress = overlay.progress
        overlay.progress = 0
        let frame = try XCTUnwrap(overlay.snapshotForValidation()?.cgImage)
        let rect = source.convert(source.bounds, to: overlay).applying(CGAffineTransform(scaleX: 2, y: 2))
        let cropped = try XCTUnwrap(frame.cropping(to: rect))
        let assembled = UIImage(cgImage: cropped, scale: 2, orientation: .up)
        overlay.progress = progress
        let latest = CardElementTransition.capture(source)
        XCTAssertNotEqual(previous.pngData(), latest.pngData())
        XCTAssertLessThan(try pixelError(assembled, latest), 2,
            "The actual Metal fragments must assemble the new value, not the last visible balance")
    }

    func testPendingRevealCanBeCancelledWithoutExposingBalance() async throws {
        let view = HeroParticleHostingView(frame: .zero)
        let window = try show(view)
        defer { window.isHidden = true; view.effect.reset() }
        let content = Text("987.65 TON").font(.system(size: 40))
        view.update(content: content, hidden: true, color: .label)
        try await Task.sleep(for: .milliseconds(80))
        view.update(content: content, hidden: false, color: .label)
        XCTAssertTrue(view.effect.transition.isAnimating)
        XCTAssertTrue(view.hosting?.isHidden == true)
        view.update(content: content, hidden: true, color: .label)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertFalse(view.effect.transition.isAnimating)
        XCTAssertTrue(view.hosting?.isHidden == true)
        XCTAssertNil(view.effect.transition.overlay)
        view.update(content: content, hidden: false, color: .label)
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertFalse(view.effect.transition.isAnimating)
        XCTAssertNil(view.effect.transition.overlay)
    }

    private func pixelError(_ lhs: UIImage, _ rhs: UIImage) throws -> Double {
        func pixels(_ image: UIImage) throws -> [UInt8] {
            let cg = try XCTUnwrap(image.cgImage)
            var bytes = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
            bytes.withUnsafeMutableBytes { data in
                let context = CGContext(data: data.baseAddress, width: cg.width, height: cg.height,
                    bitsPerComponent: 8, bytesPerRow: cg.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            }
            return bytes
        }
        let a = try pixels(lhs), b = try pixels(rhs)
        XCTAssertEqual(a.count, b.count)
        return zip(a, b).reduce(0) { $0 + abs(Double($1.0) - Double($1.1)) } / Double(max(1, a.count))
    }

    func testConcealedSnapshotKeepsLatestPixelsAfterNormalRenderCommit() async throws {
        let host = UIView()
        let window = try show(host)
        defer { window.isHidden = true }
        let target = HostingView { Text("123.45 TON").font(.system(size: 40)).foregroundStyle(Color.white) }
        host.addSubview(target); target.frame = host.bounds; target.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(80))
        var images: [UIImage] = []
        for phase in 0...3 {
            if phase == 1 { target.isHidden = true; try await Task.sleep(for: .milliseconds(80)) }
            if phase == 2 {
                target.contentView.configuration = UIHostingConfiguration {
                    Text("987.65 TON").font(.system(size: 40)).foregroundStyle(Color.white)
                }.margins(.all, 0)
                target.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(80))
            }
            if phase == 3 { target.isHidden = false; try await Task.sleep(for: .milliseconds(80)) }
            let start = CACurrentMediaTime()
            let image = CardElementTransition.capture(target.contentView)
            images.append(image)
            print("Non-flushing snapshot phase=\(phase) ms=\((CACurrentMediaTime()-start)*1000) bytes=\(image.pngData()!.count)")
        }
        let grid = UIGraphicsImageRenderer(size: CGSize(width: 380*2, height: 90*2)).image { c in
            UIColor.systemBlue.setFill(); c.fill(CGRect(x: 0, y: 0, width: 380*2, height: 90*2))
            for (i, image) in images.enumerated() { image.draw(at: CGPoint(x: i%2*380, y: i/2*90)) }
        }
        let attachment = XCTAttachment(image: grid); attachment.name = "Visible, concealed, updated while concealed, revealed"; attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertEqual(images[0].pngData(), images[1].pngData(), "Hidden snapshot preserves visible content")
        XCTAssertEqual(images[2].pngData(), images[3].pngData(), "Hidden update captures latest content")
        XCTAssertNotEqual(images[0].pngData(), images[2].pngData())
    }

    func testLiveCloudHandoffTracksActualParticlesAndRevealHasNoIdleTail() async throws {
        let tuning = CardParticleSettings.hero
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            throw XCTSkip("Requires the app-hosted hero particle test runner")
        }
        let window = UIWindow(windowScene: scene), root = UIViewController()
        window.rootViewController = root; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        let host = UIView(frame: CGRect(x: 0, y: 120, width: 370, height: 140)); root.view.addSubview(host)
        let label = UILabel(frame: CGRect(x: 22, y: 40, width: 326, height: 60))
        label.text = "$13 235.35"; label.font = .systemFont(ofSize: 49, weight: .bold); label.textColor = .white
        let visibility = UIView(frame: label.frame)
        host.addSubview(visibility); label.frame = visibility.bounds; visibility.addSubview(label)
        let dust = CardSpoilerDustView(frame: host.bounds)
        dust.fieldRect = CGRect(x: 25, y: 52, width: 305, height: 38)
        dust.settings = tuning; host.addSubview(dust); dust.animationActive = true
        let transition = CardElementTransition(); transition.settings = tuning; transition.active = true
        defer { transition.reset(); dust.animationActive = false }
        transition.setConcealed(false, in: visibility, snapshotSource: label, dust: dust, animated: false)
        var frames: [UIImage] = []
        func capture() throws {
            let cloud = UIGraphicsImageRenderer(bounds: dust.bounds).image { _ in dust.draw(dust.bounds) }
            let fragments = transition.overlay?.snapshotForValidation()
            let image = UIGraphicsImageRenderer(bounds: host.bounds).image { ctx in
                UIColor.systemBlue.setFill(); ctx.fill(host.bounds)
                if !visibility.isHidden {
                    ctx.cgContext.saveGState(); ctx.cgContext.translateBy(x: visibility.frame.minX, y: visibility.frame.minY)
                    label.layer.render(in: ctx.cgContext); ctx.cgContext.restoreGState()
                }
                if !dust.isHidden { cloud.draw(in: dust.frame, blendMode: .normal, alpha: dust.alpha) }
                if let fragments, let overlay = transition.overlay { fragments.draw(in: overlay.frame) }
            }
            frames.append(image)
        }
        try await Task.sleep(for: .milliseconds(80))
        try capture()
        transition.setConcealed(true, in: visibility, snapshotSource: label, dust: dust, animated: true)
        let overlay = try XCTUnwrap(transition.overlay)
        let firstFrame = try XCTUnwrap(overlay.snapshotForValidation()?.cgImage)
        var bytes = [UInt8](repeating: 0, count: firstFrame.width * firstFrame.height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: firstFrame.width, height: firstFrame.height,
                bitsPerComponent: 8, bytesPerRow: firstFrame.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(firstFrame, in: CGRect(x: 0, y: 0, width: firstFrame.width, height: firstFrame.height))
        }
        let colored = stride(from: 0, to: bytes.count, by: 4).filter { i in
            bytes[i+3] > 32 && Int(max(bytes[i], bytes[i+1], bytes[i+2])) - Int(min(bytes[i], bytes[i+1], bytes[i+2])) > 3
        }.count
        XCTAssertEqual(colored, 0, "White UIKit glyphs must not acquire colored fringes in the captured texture")
        for index in 0..<43 {
            dust.advance(by: 1 / 60); transition.advance(by: 1 / 60)
            if [4, 10, 17, 24, 31, 42].contains(index) { try capture() }
            if index == 17 {
                let old = overlay.cloudDestinationsForValidation
                let before = try XCTUnwrap(overlay.snapshotForValidation()).pngData()
                dust.advance(by: 1 / 60); transition.advance(by: 1e-10)
                let destinations = overlay.cloudDestinationsForValidation
                XCTAssertNotEqual(old, destinations, "Fragment endpoints must follow the moving cloud, not a separate static field")
                let movement = zip(old, destinations).map { hypot($0.x - $1.x, $0.y - $1.y) }.max() ?? 0
                XCTAssertLessThan(movement, 2, "An invisible dot restarting its life must not teleport a visible fragment")
                XCTAssertNotEqual(overlay.snapshotForValidation()?.pngData(), before, "Live cloud changes must reach the actual GPU frame")
            }
        }
        XCTAssertNil(transition.overlay); XCTAssertTrue(visibility.isHidden); XCTAssertEqual(dust.alpha, 1)
        let cloudBefore = UIGraphicsImageRenderer(bounds: dust.bounds).image { _ in dust.draw(dust.bounds) }
        transition.setConcealed(false, in: visibility, snapshotSource: label, dust: dust, animated: true)
        XCTAssertEqual(transition.progress, tuning.disintegration.blendEnd)
        XCTAssertEqual(dust.alpha, 1)
        let cloudAfter = UIGraphicsImageRenderer(bounds: dust.bounds).image { _ in dust.draw(dust.bounds) }
        XCTAssertEqual(cloudBefore.pngData(), cloudAfter.pngData(), "Reveal must begin with the exact existing live cloud")
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertNotNil(transition.overlay)
        transition.advance(by: 0.06)
        XCTAssertLessThan(dust.alpha, 0.995, "Reveal must begin changing before the old 150 ms idle tail")
        try capture()
        let middle = transition.progress
        let alpha = dust.alpha
        transition.setConcealed(true, in: visibility, snapshotSource: label, dust: dust, animated: true)
        XCTAssertEqual(transition.progress, middle); XCTAssertEqual(dust.alpha, alpha)
        transition.setConcealed(false, in: visibility, snapshotSource: label, dust: dust, animated: true)
        for index in 0..<36 {
            dust.advance(by: 1 / 60); transition.advance(by: 1 / 60)
            if [3, 9, 17, 25, 35].contains(index) { try capture() }
        }
        XCTAssertNil(transition.overlay); XCTAssertFalse(visibility.isHidden); XCTAssertTrue(dust.isHidden)
        let grid = UIGraphicsImageRenderer(size: CGSize(width: 740, height: 140 * ((frames.count + 1) / 2))).image { _ in
            for (index, image) in frames.enumerated() {
                image.draw(in: CGRect(x: (index % 2) * 370, y: (index / 2) * 140, width: 370, height: 140))
            }
        }
        let attachment = XCTAttachment(image: grid); attachment.name = "User JSON live cloud handoff hide and reveal"
        attachment.lifetime = .keepAlways; add(attachment)
    }

    func testFragmentBridgesInvisibleCloudCycleAndThenCatchesUp() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 2, y: 2, width: 16, height: 16))
        }
        let rect = CGRect(x: 0, y: 0, width: 120, height: 40)
        let initial = CardSpoilerDustView.TransitionSample(position: CGPoint(x: 100, y: 20), diameter: 2, opacity: 0.01)
        let wrapped = CardSpoilerDustView.TransitionSample(position: CGPoint(x: 52, y: 20), diameter: 2, opacity: 0)
        for fps in [30, 60, 120] {
            let view = try XCTUnwrap(CardElementParticlesView(image: image, sourceRect: rect, field: rect,
                origin: .zero, settings: .init(effect: .disintegrate), cloudSamples: [initial]))
            view.frame = rect
            view.updateCloudSamples([wrapped], elapsed: 0)
            XCTAssertEqual(view.cloudDestinationsForValidation.first?.x, 100, "Preserve the endpoint at the wrap itself")
            var previous: CGFloat = 100
            for _ in 0..<fps {
                view.updateCloudSamples([wrapped], elapsed: 1 / Double(fps))
                let x = try XCTUnwrap(view.cloudDestinationsForValidation.first?.x)
                XCTAssertLessThanOrEqual(x, previous); XCTAssertGreaterThanOrEqual(x, 52)
                previous = x
            }
            XCTAssertEqual(previous, 52, accuracy: 0.001, "Reconnect to the actual cloud instead of accumulating drift")
        }
    }

    func testParticleRepulsionIsLocalBoundedAndReturnsAtEveryFrameRate() {
        var samples: [CGPoint] = []
        for fps in [30, 60, 120] {
            let dt = 1 / Double(fps)
            var near = CardParticleRepulsion(), rim = CardParticleRepulsion(), far = CardParticleRepulsion(), centered = CardParticleRepulsion()
            let point = CGPoint(x: 10, y: 0)
            for _ in 0..<(fps / 2) {
                near.advance(at: point, finger: .zero, fallbackDirection: .init(x: 1, y: 0), by: dt)
                rim.advance(at: .init(x: 45, y: 0), finger: .zero, fallbackDirection: .init(x: 1, y: 0), by: dt)
                far.advance(at: .init(x: 80, y: 0), finger: .zero, fallbackDirection: .init(x: 1, y: 0), by: dt)
                centered.advance(at: .zero, finger: .zero, fallbackDirection: .init(x: 0, y: 1), by: dt)
            }
            XCTAssertGreaterThan(near.offset.x, 20); XCTAssertEqual(near.offset.y, 0)
            XCTAssertGreaterThan(rim.offset.x, 8, "Repulsion must remain visible beyond the fingertip")
            XCTAssertLessThanOrEqual(near.offset.x, CardParticleRepulsion.travel)
            XCTAssertEqual(far.offset, .zero, "The rest of the balance must not move")
            XCTAssertEqual(centered.offset.x, 0); XCTAssertGreaterThan(centered.offset.y, 29)
            samples.append(near.offset)
            // Crossing the particle reverses the force without a teleport.
            let beforeCrossing = near.offset
            near.advance(at: point, finger: .init(x: 20, y: 0), fallbackDirection: .init(x: 1, y: 0), by: dt)
            XCTAssertLessThan(abs(near.offset.x - beforeCrossing.x), CardParticleRepulsion.travel * 0.4)
            for _ in 0..<fps {
                near.advance(at: point, finger: .init(x: 20, y: 0), fallbackDirection: .init(x: 1, y: 0), by: dt)
            }
            XCTAssertLessThan(near.offset.x, -20)
            // A finger moving away restores the field before the gesture ends.
            for _ in 0..<(fps * 2) {
                near.advance(at: point, finger: .init(x: 200, y: 0), fallbackDirection: .init(x: 1, y: 0), by: dt)
                centered.advance(at: .zero, finger: nil, fallbackDirection: .init(x: 0, y: 1), by: dt)
            }
            XCTAssertEqual(near.offset, .zero); XCTAssertEqual(centered.offset, .zero)
        }
        for sample in samples { XCTAssertEqual(sample.x, samples[0].x, accuracy: 0.000001) }
    }


}

extension HeroParticleTests {
    func testNativeHeroGalleryPremiumColorsAndReversal() async throws {
        let host = UIView()
        let window = try show(host, size: CGSize(width: 380, height: 170))
        defer { window.isHidden = true }
        host.backgroundColor = UIColor(red: 0.08, green: 0.38, blue: 0.72, alpha: 1)
        let balance = MtwCardBalanceLabelView(), change = MtwCardChangeView()
        host.addSubview(balance); host.addSubview(change)
        balance.frame = CGRect(x: 10, y: 16, width: 360, height: 84)
        change.frame = CGRect(x: 10, y: 114, width: 360, height: 32)
        var frames: [UIImage] = []
        var nfts: [ApiNft?] = [nil]
        for type in [ApiMtwCardType.standard, .silver, .gold, .platinum, .black] {
            var nft = ApiNft.sampleMtwCard
            nft.metadata?.mtwCardType = type
            nfts.append(nft)
        }
        func capture() throws {
            let layers = [balance.elementTransition.overlay, change.elementTransition.overlay].compactMap { $0 }
            let snapshots = try layers.map { (try XCTUnwrap($0.snapshotForValidation()), $0.convert($0.bounds, to: host)) }
            layers.forEach { $0.isHidden = true }
            let image = UIGraphicsImageRenderer(bounds: host.bounds).image { _ in
                host.drawHierarchy(in: host.bounds, afterScreenUpdates: true)
                for (image, frame) in snapshots { image.draw(in: frame) }
            }
            layers.forEach { $0.isHidden = false }
            frames.append(image)
        }
        for nft in nfts {
            balance.prepareForReuse(); change.prepareForReuse()
            balance.setPrivacyAnimationActive(true); change.setPrivacyAnimationActive(true)
            func configure(_ hidden: Bool) {
                balance.configure(balance: .fromDouble(13235.35, .USD), style: .homeCard, nft: nft,
                    usesCardGradient: true, isHidden: hidden, isScrolling: false, animates: true)
                change.configure(balance: .fromDouble(13235.35, .USD), previous: .fromDouble(12192.23, .USD),
                    percent: 8.56, nft: nft, isHidden: hidden, animates: true)
                balance.layoutIfNeeded(); change.layoutIfNeeded()
            }
            configure(false)
            try await Task.sleep(for: .milliseconds(80))
            try capture()
            for visibility in [balance.subviews[0], change.subviews[0]] {
                let source = try XCTUnwrap(visibility.subviews.first)
                let format = UIGraphicsImageRendererFormat(); format.scale = 2; format.opaque = false
                let oldStart = CACurrentMediaTime()
                let reference = UIGraphicsImageRenderer(bounds: visibility.bounds, format: format).image { _ in
                    visibility.drawHierarchy(in: visibility.bounds, afterScreenUpdates: true)
                }
                let oldDuration = CACurrentMediaTime() - oldStart
                let newStart = CACurrentMediaTime()
                let actual = CardElementTransition.capture(source)
                print("Hero capture ms: screen flush=\(oldDuration * 1000), local snapshot=\((CACurrentMediaTime() - newStart) * 1000)")
                XCTAssertLessThan(try pixelError(reference, actual), 0.5,
                    "Keep the same native premium gradient, pill tint, blur and lighting")
            }
            configure(true)
            let overlay = try XCTUnwrap(balance.elementTransition.overlay)
            XCTAssertGreaterThan(overlay.fragmentCount, 30)
            balance.elementTransition.advance(by: 0.23); change.elementTransition.advance(by: 0.23)
            try capture()
            let progress = balance.elementTransition.progress
            configure(false)
            XCTAssertTrue(balance.elementTransition.overlay === overlay)
            XCTAssertEqual(balance.elementTransition.progress, progress)
            configure(true)
            balance.elementTransition.advance(by: 2); change.elementTransition.advance(by: 2)
            let dust = try XCTUnwrap(balance.subviews.compactMap { $0 as? CardSpoilerDustView }.first)
            if nft?.metadata?.mtwCardType?.isPremium == true {
                XCTAssertEqual(dust.particleGradient, MtwCardForegroundView.colors(for: nft))
            }
            let pillDust = try XCTUnwrap(change.subviews.compactMap { $0 as? CardSpoilerDustView }.first)
            if nft == nil { XCTAssertEqual(pillDust.particleColor, UIColor.air.positiveBalance) }
            try capture()
            configure(false)
            try await Task.sleep(for: .milliseconds(60))
            balance.elementTransition.advance(by: 0.35); change.elementTransition.advance(by: 0.35)
            try capture()
            balance.elementTransition.advance(by: 2); change.elementTransition.advance(by: 2)
            try capture()
        }
        let grid = UIGraphicsImageRenderer(size: CGSize(width: 1900, height: 1020)).image { _ in
            for (index, image) in frames.enumerated() {
                image.draw(in: CGRect(x: index % 5 * 380, y: index / 5 * 170, width: 380, height: 170))
            }
        }
        let attachment = XCTAttachment(image: grid)
        attachment.name = "Native hero particles – visible, hide, cloud, reveal, restored"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

extension HeroParticleTests {
    func testElementParticleShaderPreservesSourcePixelsAndDisperses() throws {
        let size = CGSize(width: 120, height: 60)
        let format = UIGraphicsImageRendererFormat(); format.scale = 2
        let source = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 5, y: 5, width: 25, height: 15))
            UIColor.green.setFill(); context.fill(CGRect(x: 70, y: 35, width: 35, height: 20))
        }
        let field = CGRect(x: 20, y: 10, width: 80, height: 40)
        let view = try XCTUnwrap(CardElementParticlesView(image: source, sourceRect: CGRect(origin: .zero, size: size),
            field: field, origin: CGPoint(x: 5, y: 10), settings: .init(effect: .disintegrate)))
        view.frame = CGRect(origin: .zero, size: size)
        XCTAssertGreaterThan(view.fragmentCount, 100)
        let original = try XCTUnwrap(view.snapshotForValidation())
        func pixels(_ image: UIImage) throws -> [UInt8] {
            let cg = try XCTUnwrap(image.cgImage)
            var bytes = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
            try bytes.withUnsafeMutableBytes { data in
                let context = try XCTUnwrap(CGContext(data: data.baseAddress, width: cg.width, height: cg.height, bitsPerComponent: 8,
                    bytesPerRow: cg.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            }
            return bytes
        }
        let expected = try pixels(source), actual = try pixels(original)
        XCTAssertEqual(expected.count, actual.count)
        let error = zip(expected, actual).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) } / Double(expected.count)
        XCTAssertLessThan(error, 2, "The first Metal frame must reproduce original color, alpha, scale and orientation")
        view.progress = 0.45; let scattered = try XCTUnwrap(view.snapshotForValidation())
        XCTAssertNotEqual(scattered.pngData(), original.pngData())
        let fadedCG = try XCTUnwrap(scattered.cgImage)
        let fadedData = try XCTUnwrap(fadedCG.dataProvider?.data)
        let rgba = try XCTUnwrap(CFDataGetBytePtr(fadedData))
        var invalidPremultiplication = 0
        for y in 0..<fadedCG.height { for x in 0..<fadedCG.width {
            let i = y * fadedCG.bytesPerRow + x * 4
            if Int(max(rgba[i], rgba[i+1], rgba[i+2])) > Int(rgba[i+3]) + 1 { invalidPremultiplication += 1 }
        } }
        XCTAssertEqual(invalidPremultiplication, 0, "Fading must preserve premultiplied RGB <= alpha, without colored fringes")
        view.progress = 1
        XCTAssertEqual(try pixels(XCTUnwrap(view.snapshotForValidation())).max(), 0, "No readable fragment remains in the hidden state")
        view.progress = 0
        XCTAssertEqual(view.snapshotForValidation()?.pngData(), original.pngData(), "Reverse timeline reassembles exact source pixels")
    }

}

extension HeroParticleTests {
    func testUIKitHeroUsesParticlesWhileListMasksKeepTheirOriginalBehavior() throws {
        let originalPrivacy = AppStorageHelper.isSensitiveDataHidden
        defer { AppStorageHelper.isSensitiveDataHidden = originalPrivacy }
        AppStorageHelper.isSensitiveDataHidden = false
        for hero in [false, true] {
            let view = WSensitiveData<UILabel>(cols: 12, rows: 3, cellSize: 10,
                cornerRadius: 10, theme: .adaptive, alignment: .center, usesHeroParticles: hero)
            let label = UILabel()
            label.translatesAutoresizingMaskIntoConstraints = false
            label.text = "123.45"; label.textColor = .systemPurple
            label.font = .systemFont(ofSize: 34, weight: .bold)
            view.addContent(label)
            view.translatesAutoresizingMaskIntoConstraints = true
            let window = try show(view, size: CGSize(width: 180, height: 48))
            defer { window.isHidden = true }
            AppStorageHelper.isSensitiveDataHidden = true
            view.resetReveal()
            view.layoutIfNeeded()
            if hero {
                XCTAssertNil(view.shyMask)
                let dust = try XCTUnwrap(view.subviews.compactMap { $0 as? CardSpoilerDustView }.first)
                XCTAssertEqual(dust.particleColor, UIColor.systemPurple)
                for amount in ["0", "123.45", "987654321.99"] {
                    label.text = amount
                    view.setNeedsLayout(); view.layoutIfNeeded()
                    XCTAssertEqual(dust.fieldRect.size, CGSize(width: 120, height: 30))
                    XCTAssertEqual(view.contentSizeThatFits(CGSize(width: 360, height: 100)).width, 120)
                }
                XCTAssertTrue(view.isAccessibilityElement)
                XCTAssertEqual(view.accessibilityLabel, lang("Tap to reveal"))
                XCTAssertTrue(view.accessibilityActivate())
                XCTAssertFalse(view.isAccessibilityElement)
            } else {
                XCTAssertNotNil(view.shyMask)
                XCTAssertFalse(view.subviews.contains { $0 is CardSpoilerDustView })
            }
            AppStorageHelper.isSensitiveDataHidden = false
            view.resetReveal()
        }
    }
}

extension HeroParticleTests {
    func testPowerSavingFreezesCloudButCrossfadesPrivacyAndAnimationsOffIsInstant() async throws {
        XCTAssertEqual(HeroParticleAnimationPolicy.transitionMode(animations: true, lowPower: true, reduceMotion: false, applicationActive: true), .crossfade)
        XCTAssertEqual(HeroParticleAnimationPolicy.transitionMode(animations: false, lowPower: true, reduceMotion: false, applicationActive: true), .instant)
        XCTAssertEqual(HeroParticleAnimationPolicy.transitionMode(animations: true, lowPower: false, reduceMotion: false, applicationActive: true), .particles)
        let host = UIView()
        let window = try show(host)
        defer { window.isHidden = true }
        let label = UILabel(frame: host.bounds)
        label.text = "123.45"; label.font = .systemFont(ofSize: 42, weight: .bold)
        let visibility = UIView(frame: label.frame)
        host.addSubview(visibility); label.frame = visibility.bounds; visibility.addSubview(label)
        let dust = CardSpoilerDustView(frame: host.bounds)
        host.addSubview(dust); dust.settings = .hero; dust.fieldRect = host.bounds.insetBy(dx: 30, dy: 20)
        dust.animationActive = false
        var mode = HeroParticleAnimationPolicy.TransitionMode.crossfade
        let transition = CardElementTransition(transitionMode: { mode })
        transition.active = true
        transition.setConcealed(false, in: visibility, snapshotSource: label, dust: dust, animated: false)
        try await Task.sleep(for: .milliseconds(80))
        transition.setConcealed(true, in: visibility, snapshotSource: label, dust: dust, animated: true)
        XCTAssertNil(transition.overlay, "Low power must not create Metal fragments")
        XCTAssertTrue(transition.isAnimating, "Privacy retains a lightweight fade")
        let positions = dust.transitionSamples().map(\.position)
        try await Task.sleep(for: .milliseconds(80))
        let opacity = try XCTUnwrap(visibility.layer.presentation()?.opacity)
        XCTAssertGreaterThan(opacity, 0); XCTAssertLessThan(opacity, 1)
        XCTAssertEqual(positions, dust.transitionSamples().map(\.position))
        XCTAssertFalse(dust.isAnimating)
        transition.setConcealed(false, in: visibility, snapshotSource: label, dust: dust, animated: true)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(transition.isAnimating); XCTAssertFalse(visibility.isHidden); XCTAssertTrue(dust.isHidden)
        XCTAssertEqual(visibility.alpha, 1)
        mode = .instant
        transition.setConcealed(true, in: visibility, snapshotSource: label, dust: dust, animated: true)
        XCTAssertFalse(transition.isAnimating); XCTAssertTrue(visibility.isHidden); XCTAssertFalse(dust.isHidden)
        transition.setConcealed(false, in: visibility, snapshotSource: label, dust: dust, animated: true)
        XCTAssertFalse(transition.isAnimating); XCTAssertFalse(visibility.isHidden); XCTAssertTrue(dust.isHidden)
    }
}

private final class CaptureTrackingView: UIView {
    var hiddenWrites = 0
    var screenUpdateRequests: [Bool] = []
    override var isHidden: Bool { didSet { hiddenWrites += 1 } }
    override func drawHierarchy(in rect: CGRect, afterScreenUpdates: Bool) -> Bool {
        screenUpdateRequests.append(afterScreenUpdates)
        return super.drawHierarchy(in: rect, afterScreenUpdates: afterScreenUpdates)
    }
}

extension HeroParticleTests {
    func testSwipePauseReusesBackgroundWithoutReadbackAndStillReleasesOnExit() async throws {
        let previous = AppStorageHelper.is3dCardDisabled
        AppStorageHelper.is3dCardDisabled = false
        defer { AppStorageHelper.is3dCardDisabled = previous }
        let background = MtwCardBackgroundView()
        let window = try show(background, size: CGSize(width: 360, height: 209))
        defer { window.isHidden = true }
        func renderer() -> CardBackgroundMetalView? {
            background.subviews.flatMap(\.subviews).compactMap { $0 as? CardBackgroundMetalView }.first
        }
        background.configure(nft: nil, isAnimationEnabled: true, isShineEnabled: true, retainPausedRenderer: true)
        background.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        let original = try XCTUnwrap(renderer())
        for _ in 0..<3 {
            background.configure(nft: nil, isAnimationEnabled: false, isShineEnabled: false, retainPausedRenderer: true)
            let phase = original.clock.lineTime
            XCTAssertTrue(original.isSuspended)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertTrue(renderer() === original, "Swiping must not snapshot, discard and recreate the renderer")
            XCTAssertEqual(original.clock.lineTime, phase)
            background.configure(nft: nil, isAnimationEnabled: true, isShineEnabled: true, retainPausedRenderer: true)
            XCTAssertTrue(renderer() === original)
            try await Task.sleep(for: .milliseconds(50))
            XCTAssertFalse(original.isSuspended)
        }
        background.removeFromSuperview()
        XCTAssertNil(renderer(), "Offscreen cells must release the paused renderer")
    }

    func testDustMetalPreservesOpacityUnionsColorsAndParticleShape() throws {
        let dust = CardSpoilerDustView(frame: CGRect(x: 0, y: 0, width: 340, height: 130))
        dust.settings = .hero
        dust.fieldRect = CGRect(x: 40, y: 45, width: 260, height: 40)
        dust.gradientFrame = dust.fieldRect
        dust.advance(by: 1.0 / 60)
        let format = UIGraphicsImageRendererFormat(); format.scale = 3
        func pixels(_ image: UIImage) throws -> [UInt8] {
            let cg = try XCTUnwrap(image.cgImage)
            var bytes = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
            try bytes.withUnsafeMutableBytes { data in
                let context = try XCTUnwrap(CGContext(data: data.baseAddress, width: cg.width, height: cg.height,
                    bitsPerComponent: 8, bytesPerRow: cg.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
                context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            }
            return bytes
        }
        var frames: [UIImage] = []
        for palette in [[UIColor.white, .white], [UIColor(hex: "CECECF"), UIColor(hex: "444546")],
                        [UIColor(hex: "4C3403"), UIColor(hex: "B07D1D")], [UIColor.systemGreen, .systemGreen]] {
            dust.setGradient(palette)
            let reference = UIGraphicsImageRenderer(bounds: dust.bounds, format: format).image { _ in dust.draw(dust.bounds) }
            let rendered = try XCTUnwrap(dust.metalSnapshotForValidation())
            let expected = try pixels(reference), actual = try pixels(rendered)
            let meanError = zip(expected, actual).reduce(0.0) { $0 + Double(abs(Int($1.0) - Int($1.1))) } / Double(expected.count)
            let expectedAlpha = stride(from: 3, to: expected.count, by: 4).reduce(0.0) { $0 + Double(expected[$1]) }
            let actualAlpha = stride(from: 3, to: actual.count, by: 4).reduce(0.0) { $0 + Double(actual[$1]) }
            print("DUST_PARITY mean_byte_error=\(meanError) alpha_ratio=\(actualAlpha / expectedAlpha)")
            XCTAssertLessThan(meanError, 3, "GPU antialiasing must retain the same field, color and density")
            XCTAssertEqual(actualAlpha / expectedAlpha, 1, accuracy: 0.04)
            for index in stride(from: 0, to: actual.count, by: 4) {
                XCTAssertLessThanOrEqual(max(actual[index], actual[index + 1], actual[index + 2]), actual[index + 3], "Premultiplied color must never flash above alpha")
            }
            frames += [reference, rendered]
        }
        let gallery = UIGraphicsImageRenderer(size: CGSize(width: 680, height: 520)).image { _ in
            UIColor.black.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: 680, height: 520))
            for (index, frame) in frames.enumerated() { frame.draw(in: CGRect(x: index % 2 * 340, y: index / 2 * 130, width: 340, height: 130)) }
        }
        let attachment = XCTAttachment(image: gallery); attachment.name = "Dust-CoreGraphics-left-Metal-right"; attachment.lifetime = .keepAlways; add(attachment)
        let renderer = try XCTUnwrap(CardDustMetalView(particleCapacity: 6000))
        let sample = CardSpoilerDustView.TransitionSample(position: CGPoint(x: 10, y: 10), diameter: 6, opacity: 0.5)
        let one = try XCTUnwrap(renderer.snapshotForValidation(samples: [sample], size: CGSize(width: 20, height: 20), scale: 3))
        let overlapping = try XCTUnwrap(renderer.snapshotForValidation(samples: [sample, sample], size: CGSize(width: 20, height: 20), scale: 3))
        XCTAssertEqual(one.pngData(), overlapping.pngData(), "Same-opacity paths were a union, not additive particles")
    }

    func testParticleBufferPoolNeverOverwritesInFlightFrames() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let pool = try XCTUnwrap(CardParticleBufferPool(device: device, length: 16))
        let first = try XCTUnwrap(pool.acquire()), second = try XCTUnwrap(pool.acquire()), third = try XCTUnwrap(pool.acquire())
        first.buffer.contents().storeBytes(of: UInt32(12345), as: UInt32.self)
        XCTAssertNil(pool.acquire())
        pool.release(second.index)
        let recycled = try XCTUnwrap(pool.acquire())
        XCTAssertEqual(recycled.index, second.index)
        XCTAssertTrue(recycled.buffer === second.buffer)
        XCTAssertEqual(first.buffer.contents().load(as: UInt32.self), 12345)
        XCTAssertNil(pool.acquire())
        pool.release(first.index); pool.release(recycled.index); pool.release(third.index)
    }
}


extension HeroParticleTests {
    func testDustFramePreparationCostWithSelectedPreset() throws {
        let dust = CardSpoilerDustView(frame: CGRect(x: 0, y: 0, width: 420, height: 150))
        dust.settings = .hero
        dust.fieldRect = CGRect(x: 70, y: 55, width: 280, height: 40)
        let renderer = try XCTUnwrap(CardDustMetalView(particleCapacity: 6000))
        renderer.setPalette(color: .white, gradient: nil, frame: .zero, traits: dust.traitCollection)
        let format = UIGraphicsImageRendererFormat(); format.scale = 3
        let raster = UIGraphicsImageRenderer(bounds: dust.bounds, format: format)
        var cg: [Double] = [], metal: [Double] = []
        for iteration in 0..<24 {
            dust.advance(by: 1.0 / 60)
            let start = CACurrentMediaTime()
            autoreleasepool { _ = raster.image { _ in dust.draw(dust.bounds) } }
            let duration = (CACurrentMediaTime() - start) * 1000
            _ = try XCTUnwrap(renderer.snapshotForValidation(samples: dust.transitionSamples(), size: dust.bounds.size, scale: 3))
            if iteration >= 4 { cg.append(duration); metal.append(renderer.lastEncodeMilliseconds) }
        }
        func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }
        print("DUST_CPU_MS particles=\(dust.particleCount) core_graphics=\(median(cg)) metal_submission=\(median(metal))")
        // GPU completion is waited for only by this test's readback, and excluded
        // from submission timing. These are CPU costs, not whole-app frame rates.
    }
}


extension HeroParticleTests {
    func testLiveDustUsesMetalAndDoesNotRasterizeEveryFrame() async throws {
        let dust = CardSpoilerDustView(frame: .zero)
        let window = try show(dust, size: CGSize(width: 340, height: 130))
        defer { dust.reset(); window.isHidden = true }
        dust.settings = .hero
        dust.fieldRect = CGRect(x: 40, y: 45, width: 260, height: 40)
        dust.animationActive = true
        dust.setConcealed(true, animated: false)
        try await Task.sleep(for: .milliseconds(150))
        let renderer = try XCTUnwrap(dust.subviews.compactMap { $0 as? CardDustMetalView }.first)
        XCTAssertEqual(renderer.alpha, 1, "The actual GPU frame must have replaced the fallback")
        XCTAssertNil(dust.layer.contents, "Do not composite the old raster underneath live particles")
        let rasterCount = dust.rasterDrawCount
        let before = dust.transitionSamples().map(\.position)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertNotEqual(dust.transitionSamples().map(\.position), before)
        XCTAssertEqual(dust.rasterDrawCount, rasterCount, "Ambient animation must never build Core Graphics paths per frame")
        dust.setNeedsDisplay() // UIKit can invalidate backing content during layout/theme changes.
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(dust.rasterDrawCount, rasterCount, "A layout redraw must not put a duplicate cloud underneath Metal")
        dust.animationActive = false
        let frozen = dust.transitionSamples().map(\.position)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(dust.transitionSamples().map(\.position), frozen)
        XCTAssertFalse(dust.isAnimating)
        dust.setConcealed(false, animated: false)
        XCTAssertTrue(dust.isHidden)
        XCTAssertNil(renderer.superview)
    }
}
