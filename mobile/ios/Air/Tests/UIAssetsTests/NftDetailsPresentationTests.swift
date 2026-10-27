import Testing
import UIKit
import Kingfisher
import UIComponents
@testable import UIAssets

@MainActor
@Suite(.serialized)
struct NftDetailsPresentationTests {
    private final class NavigationFixtureVC: NftDetailsBaseVC {
        override func ntfDetailsOnConfigureAction(forModel model: NftDetailsItemModel,
                                                action: NftDetailsItemModel.Action) -> NftDetailsActionConfig? {
            nil
        }
    }

    @Test
    func overlayAndStatusBarFollowNftBackgroundInsteadOfAppTheme() {
        let nft = NftDetailsItem(id: UUID().uuidString, name: "Appearance", description: nil,
                                 thumbnailUrl: nil, imageUrl: nil, lottieUrl: nil,
                                 attributes: nil, collection: nil, tonDomain: nil)
        let controller = NavigationFixtureVC(nfts: [nft], selectedIndex: 0, initiallyExpanded: false)
        controller.overrideUserInterfaceStyle = .light
        controller.loadViewIfNeeded()
        let model = controller.manager.models[0]
        var updates = 0
        controller.onContentOverlayAppearanceChange = { _ in updates += 1 }

        let cases: [(UIColor, UIColor, UIUserInterfaceStyle, UIStatusBarStyle)] = [
            (.black, .white, .dark, .lightContent), (.white, .black, .light, .darkContent),
        ]
        for (background, foreground, style, status) in cases {
            model.processedImageState = .loaded(.init(baseColor: background))
            model.notify(.processedImageUpdated)
            let appearance = controller.contentOverlayAppearance(in: .zero)
            #expect(appearance.usesClearGlass)
            #expect(appearance.foregroundColor == foreground)
            #expect(appearance.userInterfaceStyle == style)
            #expect(controller.preferredStatusBarStyle == status)
        }
        #expect(updates >= 2)
        #expect(controller.overrideUserInterfaceStyle == .light)
    }

    @Test
    func backButtonIsPreparedBeforeTheFirstAppearance() throws {
        let nft = NftDetailsItem(id: "navigation", name: "Navigation", description: nil,
                                 thumbnailUrl: nil, imageUrl: nil, lottieUrl: nil,
                                 attributes: nil, collection: nil, tonDomain: nil)
        let controller = NavigationFixtureVC(nfts: [nft], selectedIndex: 0, initiallyExpanded: false)
        controller.loadViewIfNeeded()
        let item = try #require(controller.navigationItem.leftBarButtonItem)
        let container = try #require(item.customView)
        let contentView: UIView
        if #available(iOS 26, *) {
            let slot = try #require(container as? NftNavigationButtonSlot)
            let glassContainer = try #require(slot.material as? UIVisualEffectView)
            #expect((glassContainer.effect as? UIGlassEffect)?.isInteractive == true,
                    "The same live material must survive being lifted above the push transition")
            contentView = glassContainer.contentView
        } else {
            contentView = container
        }
        let button = try #require(contentView.subviews.first as? NftDetailsNavigationButton)
        #expect(controller.navigationItem.hidesBackButton)
        #expect(button.bounds.size == CGSize(width: 44, height: 44))
        #expect(button.configuration?.baseForegroundColor != nil)
        #expect(button.window == nil)

        controller.beginAppearanceTransition(true, animated: true)
        #expect(controller.navigationItem.leftBarButtonItem === item)
        controller.endAppearanceTransition()
        controller.beginAppearanceTransition(false, animated: false)
        controller.endAppearanceTransition()
    }

    @Test
    func navigationGlassKeepsItsGeometryAndIdentityWhenLiftedAndRestored() throws {
        guard #available(iOS 26, *) else { return }
        let button = NftDetailsNavigationButton(configuration: .plain())
        let item = button.makeNavigationItem()
        let slot = try #require(item.customView as? NftNavigationButtonSlot)
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let bar = UIView(frame: CGRect(x: 0, y: 64, width: 402, height: 44))
        root.addSubview(bar)
        bar.addSubview(slot)
        slot.frame = CGRect(x: 16, y: 0, width: 44, height: 44)
        root.layoutIfNeeded()
        let material = slot.material
        let originalFrame = material.convert(material.bounds, to: root)

        slot.lift(in: root)
        #expect(root.subviews.last === material)
        #expect(material.frame == originalFrame)
        #expect(material.frame.size == CGSize(width: 44, height: 44))
        #expect(item.customView === slot, "Lifting must not replace the item used by UIKit's layout and matching")
        #expect(!material.isUserInteractionEnabled)

        // Completion and cancellation both restore the original live view.
        slot.restore()
        slot.restore()
        #expect(material.superview === slot)
        #expect(material.convert(material.bounds, to: root) == originalFrame)
        #expect(material.isUserInteractionEnabled)
        #expect(button.isDescendant(of: material))
    }

    private func model(_ id: String) -> NftDetailsItemModel {
        .init(item: .init(id: id, name: id, description: nil, thumbnailUrl: nil, imageUrl: "https://example.invalid/fixture.png",
                         lottieUrl: nil, attributes: nil, collection: nil, tonDomain: nil), index: 0)
    }

    @Test
    func portraitPhoneHeroKeepsItsFullWidthAndTopAlignment() {
        for (size, top, bottom) in [
            (CGSize(width: 320, height: 568), 64.0, 0.0),
            (CGSize(width: 375, height: 667), 64.0, 0.0),
            (CGSize(width: 375, height: 667), 88.0, 83.0),
            (CGSize(width: 393, height: 852), 103.0, 34.0),
            (CGSize(width: 440, height: 956), 106.0, 34.0),
        ] {
            let frame = NftDetailsHeroLayout.frame(in: size,
                safeAreaInsets: UIEdgeInsets(top: top, left: 0, bottom: bottom, right: 0),
                userInterfaceIdiom: .phone, navigationBarHeight: 44)
            #expect(frame == CGRect(x: 0, y: 0, width: size.width, height: size.width))
        }
    }

    @Test
    func largeAndLandscapeHeroesAreCenteredDetachedAndLeaveRoomForDetails() {
        for size in [CGSize(width: 834, height: 1194), CGSize(width: 950, height: 834),
                     CGSize(width: 744, height: 600), CGSize(width: 750, height: 393),
                     CGSize(width: 500, height: 600), CGSize(width: 320, height: 400)] {
            let frame = NftDetailsHeroLayout.frame(in: size,
                safeAreaInsets: UIEdgeInsets(top: 88, left: 0, bottom: 21, right: 0),
                userInterfaceIdiom: .pad, navigationBarHeight: 64)
            #expect(frame.width <= 560)
            #expect(frame.width == frame.height)
            #expect(frame.midX == size.width / 2)
            #expect(frame.minY == 34)
            #expect(frame.maxY <= size.height - 21 - 160)
            let pager = NftDetailsPagerView.LayoutGeometry(topSafeAreaInset: 64, collapsedAreaHeight: 165,
                pageWidth: size.width, expandedImageFrame: frame)
            #expect(pager.toPageGeometry().expandedHeight == frame.maxY)
            #expect(pager.toPageGeometry().headerHeight(isExpanded: false) == 229)
        }
    }

    @Test
    func cappedHeroResizesItsVisiblePreviewWhenOnlyTheWindowHeightChanges() async throws {
        let item = model("resize")
        let resolver = NftDetailsColorResolver(colorCache: NftDetailsColorCache(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        let delegate = HeaderTestDelegate()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 744, height: 800))
        // Auto Layout aligns origins to physical pixels (half-point origins round on 3x screens).
        let pixelTolerance = 0.5 / window.traitCollection.displayScale + 0.000001
        func expectFrame(_ actual: CGRect, matches expected: CGRect) {
            #expect(abs(actual.minX - expected.minX) <= pixelTolerance)
            #expect(abs(actual.minY - expected.minY) <= pixelTolerance)
            #expect(abs(actual.width - expected.width) < 0.01)
            #expect(abs(actual.height - expected.height) < 0.01)
        }
        let insets = UIEdgeInsets(top: 64, left: 0, bottom: 21, right: 0)
        let initialFrame = NftDetailsHeroLayout.frame(in: window.bounds.size, safeAreaInsets: insets, userInterfaceIdiom: .pad)
        let header = NftDetailsMainHeaderView(frame: window.bounds, models: [item], selectedModel: item,
            delegate: delegate, layoutGeometry: .init(topSafeAreaInset: 64, leadingSafeAreaInset: 0,
                trailingSafeAreaInset: 0, collapsedAreaHeight: 165, pageWidth: 744, expandedImageFrame: initialFrame),
            coverFlowThumbnailDownloader: ImageDownloader(name: "resize-test"), colorResolver: resolver)
        window.addSubview(header)
        window.isHidden = false
        defer { window.isHidden = true }
        window.layoutIfNeeded()
        let scroll = UIScrollView()
        header.handleVerticalScroll(scroll, isExpanded: true)
        try? await Task.sleep(for: .milliseconds(450))
        let preview = try #require(header.subviews.compactMap { $0 as? NftDetailsItemPreview }.first)
        expectFrame(preview.frame, matches: initialFrame)

        let resizedFrame = NftDetailsHeroLayout.frame(in: CGSize(width: 744, height: 500), safeAreaInsets: insets, userInterfaceIdiom: .pad)
        header.layoutGeometry = .init(topSafeAreaInset: 64, leadingSafeAreaInset: 0, trailingSafeAreaInset: 0,
            collapsedAreaHeight: 165, pageWidth: 744, expandedImageFrame: resizedFrame)
        header.layoutIfNeeded()
        expectFrame(preview.frame, matches: resizedFrame)
        for offset: CGFloat in [16, -12, 0] {
            scroll.contentOffset.y = offset
            header.handleVerticalScroll(scroll, isExpanded: true)
            let renderedFrame = preview.convert(preview.bounds, to: header)
            let backgroundFrame = NftDetailsHeroLayout.scrolledFrame(resizedFrame, offsetY: offset)
            expectFrame(renderedFrame, matches: backgroundFrame)
        }
    }

    @Test
    func fullScreenViewerUsesPageWidthFromBothCappedHeroAndCarousel() async throws {
        let resolver = NftDetailsColorResolver(colorCache: NftDetailsColorCache(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        let delegate = HeaderTestDelegate()
        for isExpanded in [false, true] {
            let item = model("fullscreen-\(isExpanded)")
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 744, height: 800))
            let heroFrame = CGRect(x: 92, y: 34, width: 560, height: 560)
            let header = NftDetailsMainHeaderView(frame: window.bounds, models: [item], selectedModel: item,
                delegate: delegate, layoutGeometry: .init(topSafeAreaInset: 88, leadingSafeAreaInset: 0,
                    trailingSafeAreaInset: 0, collapsedAreaHeight: 165, pageWidth: 744, expandedImageFrame: heroFrame),
                coverFlowThumbnailDownloader: ImageDownloader(name: "fullscreen-test"), colorResolver: resolver)
            window.addSubview(header)
            window.isHidden = false
            defer { window.isHidden = true }
            window.layoutIfNeeded()
            header.handleVerticalScroll(UIScrollView(), isExpanded: isExpanded)
            try await Task.sleep(for: .milliseconds(450))
            header.openFullScreenPreview()
            try await Task.sleep(for: .milliseconds(450))
            let overlay = try #require(descendant(NftDetailsFullScreenOverlay.self, in: window))
            let preview = try #require(descendant(NftDetailsItemPreview.self, in: overlay))
            #expect(preview.bounds.width == 744)
            #expect(preview.transform == .identity)
            #expect(header.dismissFullScreen())
            try await Task.sleep(for: .milliseconds(450))
            header.layoutIfNeeded()
            #expect(preview.superview === header)
            #expect(preview.bounds.width == (isExpanded ? 560 : 144))
        }
    }

    @Test
    func resizingTheControllerReturnsFullScreenPreviewToTheLatestHeroFrame() async throws {
        let controller = NftDetailsTestController(nfts: [model("controller-resize").item], selectedIndex: 0, initiallyExpanded: true)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 744, height: 800))
        controller.view.frame = window.bounds
        window.addSubview(controller.view)
        window.isHidden = false
        defer { window.isHidden = true }
        controller.view.layoutIfNeeded()
        controller.viewDidLayoutSubviews()
        let header = try #require(descendant(NftDetailsMainHeaderView.self, in: controller.view))
        let scroll = try #require(descendant(NftDetailMainScrollView.self, in: controller.view))
        header.handleVerticalScroll(scroll, isExpanded: true)
        try await Task.sleep(for: .milliseconds(450))
        header.openFullScreenPreview()
        try await Task.sleep(for: .milliseconds(450))
        let overlay = try #require(descendant(NftDetailsFullScreenOverlay.self, in: controller.view))
        let preview = try #require(descendant(NftDetailsItemPreview.self, in: overlay))

        controller.view.frame.size.height = 500
        controller.view.layoutIfNeeded()
        controller.viewDidLayoutSubviews()
        #expect(preview.bounds.width == header.layoutGeometry.expandedImageFrame.width,
                "Dismissal must start with the resized hero width")
        controller.view.frame.size.height = 420
        controller.view.layoutIfNeeded()
        controller.viewDidLayoutSubviews()
        try await Task.sleep(for: .milliseconds(450))
        header.layoutIfNeeded()
        #expect(preview.superview === header)
        #expect(preview.frame == header.layoutGeometry.expandedImageFrame,
                "Another resize during dismissal must not leave the preview at the previous size")
    }

    @Test
    func expandedPreviewHitAreaFollowsParallaxAndOverscroll() {
        let resolver = NftDetailsColorResolver(colorCache: NftDetailsColorCache(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        let delegate = PageTestDelegate()
        let viewport = UIView(frame: CGRect(x: 0, y: 0, width: 744, height: 800))
        let scroll = NftDetailMainScrollView(frame: viewport.bounds)
        scroll.contentInsetAdjustmentBehavior = .never
        viewport.addSubview(scroll)
        let horizontalScroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 744, height: 1200))
        scroll.addSubview(horizontalScroll)
        let page = NftDetailsPageView(model: model("tap"), colorResolver: resolver,
            layoutGeometry: .init(expandedImageFrame: CGRect(x: 92, y: 34, width: 560, height: 560),
                collapsedHeight: 253, width: 744), isExpanded: true, delegate: delegate)
        horizontalScroll.addSubview(page)
        page.frame.size.height = page.getFullHeight()
        // Include a horizontal page offset to exercise the coordinate conversion.
        page.frame.origin.x = 744
        horizontalScroll.contentOffset.x = 744
        for (offset, visibleFrame) in [
            (CGFloat(0), CGRect(x: 92, y: 34, width: 560, height: 560)),
            (CGFloat(100), CGRect(x: 92, y: -16, width: 560, height: 560)),
            (CGFloat(-20), CGRect(x: 82, y: 34, width: 580, height: 580)),
        ] {
            scroll.contentOffset.y = offset
            for point in [CGPoint(x: visibleFrame.midX, y: visibleFrame.maxY - 1),
                          CGPoint(x: visibleFrame.minX + 1, y: visibleFrame.midY)] {
                #expect(page.containsExpandedPreview(at: page.convert(point, from: viewport)))
            }
            for point in [CGPoint(x: visibleFrame.midX, y: visibleFrame.maxY + 1),
                          CGPoint(x: visibleFrame.minX - 1, y: visibleFrame.midY)] {
                #expect(!page.containsExpandedPreview(at: page.convert(point, from: viewport)))
            }
        }
    }

    private func descendant<T: UIView>(_ type: T.Type, in root: UIView) -> T? {
        if let view = root as? T { return view }
        return root.subviews.lazy.compactMap { descendant(type, in: $0) }.first
    }

    @Test
    func loadingDoesNotBorrowAnotherNftsBackgroundAndThumbnailWinsBeforeFullPreview() {
        let cache = NftDetailsColorCache(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let resolver = NftDetailsColorResolver(colorCache: cache)
        let first = model("first")
        first.processedImageState = .loaded(.init(baseColor: .purple))
        let next = model("next")
        next.processedImageState = .loading
        #expect(resolver.effectiveBaseColor(for: first) == .purple)
        #expect(resolver.effectiveBaseColor(for: next) != .purple)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 32, height: 16))
            UIColor.blue.setFill()
            ctx.fill(CGRect(x: 0, y: 16, width: 32, height: 16))
        }
        resolver.rememberThumbnail(image, for: next)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        resolver.effectiveBaseColor(for: next).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let expected = NftDetailsImageProcessor.pageBackgroundColor(.blue)
        #expect(resolver.effectiveBaseColor(for: next) == expected)
        #expect(blue > 0.5 && red < 0.05 && green < 0.05)
        #expect(cache.color(forKey: next.id).0 == false, "Provisional colors must not validate an unfinished image cache")
    }

    @Test
    func coldThumbnailAndFinalPreviewAgreeDespiteBrightNameplate() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200), format: format).image { ctx in
            UIColor(red: 0.12, green: 0.18, blue: 0.22, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
            UIColor.systemPurple.setFill()
            ctx.fill(CGRect(x: 10, y: 151, width: 180, height: 35))
            UIColor.cyan.setFill()
            ctx.fill(CGRect(x: 85, y: 0, width: 30, height: 200))
        }
        let cache = NftDetailsColorCache(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        // Drain pending I/O before this short-lived test cache releases its last owner.
        defer { cache.flush() }
        let resolver = NftDetailsColorResolver(colorCache: cache)
        let nft = model("nameplate")
        nft.processedImageState = .loading
        resolver.rememberThumbnail(image, for: nft)
        let provisional = resolver.effectiveBaseColor(for: nft)
        let processed = NftDetailsImageProcessor().loadImage(image, targetWidth: 200)
        nft.processedImageState = .loaded(processed)
        let final = resolver.effectiveBaseColor(for: nft)
        var r0: CGFloat = 0, g0: CGFloat = 0, b0: CGFloat = 0, a: CGFloat = 0
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0
        provisional.getRed(&r0, green: &g0, blue: &b0, alpha: &a)
        final.getRed(&r1, green: &g1, blue: &b1, alpha: &a)
        #expect(max(abs(r0 - r1), abs(g0 - g1), abs(b0 - b1)) <= 2 / 255)
        #expect(max(r0, g0, b0) < 0.25, "The nameplate must never tint the loading background")

        cache.setColor(final, forKey: nft.id)
        nft.processedImageState = .idle
        #expect(resolver.effectiveBaseColor(for: nft) == final, "Eviction must keep the final color while restoring the preview")
        let coldResolver = NftDetailsColorResolver(colorCache: cache)
        #expect(coldResolver.effectiveBaseColor(for: nft) == final)
    }

    @Test
    func bottomColorUsesTheVisibleSquareForPortraitAndLandscapeImages() throws {
        for size in [CGSize(width: 200, height: 300), CGSize(width: 300, height: 200)] {
            let side = min(size.width, size.height)
            let square = CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
            let image = UIGraphicsImageRenderer(size: size).image { ctx in
                UIColor.red.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
                UIColor.blue.setFill(); ctx.fill(square)
                UIColor.systemPurple.setFill()
                ctx.fill(CGRect(x: square.minX, y: square.minY + side * 0.75, width: side, height: side * 0.17))
            }
            let sampled = try #require(NftDetailsImageProcessor.bottomBackgroundColor(image))
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            sampled.getRed(&r, green: &g, blue: &b, alpha: &a)
            #expect(b > 0.95 && r < 0.05 && g < 0.05)
        }
    }

    @Test
    func missingArtworkKeepsThemeBackgroundAndGetsBlurredExtension() {
        let cache = NftDetailsColorCache(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let resolver = NftDetailsColorResolver(colorCache: cache)
        resolver.update(traitCollection: UITraitCollection(userInterfaceStyle: .light))
        let previous = model("previous")
        previous.processedImageState = .loaded(.init(baseColor: .purple))
        let missing = NftDetailsItemModel(item: .init(id: "missing", name: "Missing", description: nil, thumbnailUrl: nil, imageUrl: nil, lottieUrl: nil, attributes: nil, collection: nil, tonDomain: nil), index: 0)
        #expect(resolver.effectiveBaseColor(for: missing) == resolver.fallbackColor)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100)).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
            UIColor.black.setFill(); ctx.fill(CGRect(x: 20, y: 60, width: 60, height: 30))
        }
        let processed = NftDetailsImageProcessor().loadPlaceholder(image, targetWidth: 200, backgroundColor: resolver.fallbackColor)
        missing.processedImageState = .loaded(processed)
        #expect(processed.isPlaceholder)
        #expect((processed.previewImage?.size.height ?? 0) > (processed.originalImage?.size.height ?? 0))
        #expect(processed.previewCIImage != nil)
        #expect(resolver.effectiveBaseColor(for: missing) == resolver.fallbackColor)
    }

    @Test
    func transparentArtworkGetsAtmosphereWithoutChangingItsOriginal() {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100), format: format).image { _ in
            UIColor.orange.setFill()
            UIBezierPath(ovalIn: CGRect(x: 30, y: 20, width: 40, height: 40)).fill()
        }
        let background = UIColor(red: 0.2, green: 0.3, blue: 0.5, alpha: 1)
        let result = NftDetailsImageProcessor().loadImage(image, targetWidth: 200, backgroundColor: background)
        #expect((result.previewImage?.size.height ?? 0) > (result.originalImage?.size.height ?? 0))
        let corner = CGRect(x: 0.02, y: 0.02, width: 0.1, height: 0.1)
        let original = NftDetailsImageSample(image: result.originalImage!)
        var white: CGFloat = 0, alpha: CGFloat = 0
        original.color(in: corner, over: .white).getWhite(&white, alpha: &alpha)
        #expect(white > 0.98, "Transparency must be preserved in the media viewer's original image")
        let preview = NftDetailsImageSample(image: result.previewImage!)
        let bottom = preview.color(in: CGRect(x: 0.1, y: 0.95, width: 0.8, height: 0.04), over: .black)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        bottom.getRed(&r, green: &g, blue: &b, alpha: &alpha)
        var expectedR: CGFloat = 0, expectedG: CGFloat = 0, expectedB: CGFloat = 0
        result.baseColor!.getRed(&expectedR, green: &expectedG, blue: &expectedB, alpha: &alpha)
        #expect(abs(r - expectedR) < 0.025 && abs(g - expectedG) < 0.025 && abs(b - expectedB) < 0.025)
    }

    @Test
    func artworkStaysSharpAndAtmosphereUsesTheOriginalTintedPageColor() {
        let color = UIColor(red: 0.8, green: 0.6, blue: 0.4, alpha: 1)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100)).image { ctx in
            color.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        }
        let result = NftDetailsImageProcessor().loadImage(image, targetWidth: 200)
        let sharp = NftDetailsImageSample(image: result.artworkPreviewImage!)
        let atmosphere = NftDetailsImageSample(image: result.previewImage!)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        sharp.color(in: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8), over: .black)
            .getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(abs(r - 0.8) < 0.01 && abs(g - 0.6) < 0.01 && abs(b - 0.4) < 0.01)
        var expectedR: CGFloat = 0, expectedG: CGFloat = 0, expectedB: CGFloat = 0
        result.baseColor!.getRed(&expectedR, green: &expectedG, blue: &expectedB, alpha: &a)
        atmosphere.color(in: CGRect(x: 0.1, y: 0.95, width: 0.8, height: 0.04), over: .black)
            .getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(abs(r - expectedR) < 0.01 && abs(g - expectedG) < 0.01 && abs(b - expectedB) < 0.01)
        result.atmosphereColor!.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(abs(r - 0.8) < 0.01 && abs(g - 0.6) < 0.01 && abs(b - 0.4) < 0.01,
                "Regenerating the strip must use the untinted source color")
    }

    @Test
    func originalProgressiveMaskKeepsItsCurveWithALowerStartAndTheSameCompletionPoint() throws {
        let context = NftDetailsImageProcessor.atmosphereContext
        #expect(abs(NftDetailsImageProcessor.atmosphereOverlap - 54.0) < 0.001)
        // Production CGGradient from bb3f35769: preserve all six alpha stops.
        // Only its start moves; completion stays 11.5 pt below the image edge.
        let ramp = NftDetailsImageProcessor.atmosphereBlurRamp
        #expect(abs(ramp - NftDetailsImageProcessor.atmosphereOverlap - 11.5) < 0.001)
        for height: CGFloat in [190, 240] {
            for scale: CGFloat in [1, 3] {
                let extentHeight = (height + NftDetailsImageProcessor.atmosphereOverlap) * scale
                let mask = try #require(NftDetailsImageProcessor.getGradient1(
                    forSize: CGSize(width: 1, height: extentHeight), locationK: 2 * ramp * scale / extentHeight))
                var pixels = [UInt8](repeating: 0, count: Int(mask.extent.height) * 4)
                context.render(mask, toBitmap: &pixels, rowBytes: 4, bounds: mask.extent,
                               format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
                for (fraction, alpha) in [(0.0, 0.0), (0.2, 0.3), (0.4, 0.6), (0.6, 0.85), (0.8, 0.98), (1.0, 1.0), (1.4, 1.0)] {
                    let distance = fraction * ramp
                    // Bitmap rows are top-down, unlike Core Image coordinates.
                    let row = min(Int(mask.extent.height) - 1, max(0, Int(floor(distance * scale))))
                    // A raster stop may round by one pixel, plus 8-bit alpha quantization.
                    let tolerance = 0.3 / (Double(ramp) * 0.2 * Double(scale)) + 1.0 / 255
                    #expect(abs(Double(pixels[row * 4 + 3]) / 255 - alpha) < tolerance,
                            "Mask alpha at \(distance) points, scale \(scale)")
                }
            }
        }
    }

    @Test
    func bottomBackgroundIgnoresForegroundAccentsAndOtherPartsOfTheImage() {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200)).image { ctx in
            UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
            UIColor.blue.setFill(); ctx.fill(CGRect(x: 0, y: 182, width: 200, height: 18))
            UIColor.orange.setFill(); ctx.fill(CGRect(x: 80, y: 130, width: 40, height: 70))
        }
        let processed = NftDetailsImageProcessor().loadImage(image, targetWidth: 200)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        processed.atmosphereColor?.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(b > 0.95 && r < 0.05 && g < 0.05)
        let extensionColor = NftDetailsImageSample(image: processed.previewImage!).color(
            in: CGRect(x: 0.1, y: 0.98, width: 0.8, height: 0.015), over: .black)
        extensionColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        var expectedB: CGFloat = 0
        processed.baseColor?.getRed(&r, green: &g, blue: &expectedB, alpha: &a)
        #expect(abs(b - expectedB) < 0.01, "The reflection must end in the resolved page color")
    }

    @Test
    func reflectionIsSeparateFromTheSharpArtwork() {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200), format: format).image { ctx in
            UIColor.blue.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
            UIColor.orange.setFill(); ctx.fill(CGRect(x: 80, y: 130, width: 40, height: 70))
        }
        let result = NftDetailsImageProcessor().loadImage(image, targetWidth: 200)
        #expect(result.artworkPreviewImage?.size.width == result.artworkPreviewImage?.size.height)
        #expect(result.atmosphereImage != nil)
        #expect(result.artworkCIImage?.extent.width == result.artworkCIImage?.extent.height)
        let sharp = NftDetailsImageSample(image: result.artworkPreviewImage!)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        sharp.color(in: CGRect(x: 0.43, y: 0.9, width: 0.14, height: 0.08), over: .black)
            .getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(r > 0.95 && b < 0.05, "The original bottom edge must remain sharp and retain its orange foreground")
    }

    @Test
    func blurCrossesTheReflectionJoinWithoutSofteningTheRestOfTheArtwork() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200), format: format).image { ctx in
            UIColor.black.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
            UIColor.white.setFill()
            for x in stride(from: 0, to: 200, by: 4) {
                ctx.fill(CGRect(x: x, y: 0, width: 2, height: 200))
            }
        }
        let processor = NftDetailsImageProcessor()
        let result = processor.loadImage(image, targetWidth: 200)
        let processed = try #require(result.previewCIImage)
        func contrast(at y: CGFloat) -> Double {
            var pixels = [UInt8](repeating: 0, count: 160 * 4)
            processor.ciContext.render(processed, toBitmap: &pixels, rowBytes: 160 * 4,
                bounds: CGRect(x: 20, y: y, width: 160, height: 1), format: .RGBA8,
                colorSpace: CGColorSpaceCreateDeviceRGB())
            let values = stride(from: 0, to: pixels.count, by: 4).map { Double(pixels[$0]) / 255 }
            let mean = values.reduce(0, +) / Double(values.count)
            return sqrt(values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count))
        }
        let sharp = contrast(at: 260)
        #expect(sharp > 0.45, "Artwork above the narrow join must remain sharp")
        let feather = [252, 240, 228, 216, 204, 192, 180, 168, 154].map { contrast(at: CGFloat($0)) }
        for (above, below) in zip(feather, feather.dropFirst()) {
            #expect(below <= above + 0.02, "Blur must increase steadily toward the reflection")
            #expect(above - below < sharp * 0.45, "No narrow strip may contain most of the blur transition")
        }
        #expect(contrast(at: 200) < sharp * 0.05, "The original progression must soften the join")
        #expect(abs(contrast(at: 199) - contrast(at: 200)) < 0.08,
                "The reflected side must not introduce a sharp strip at the boundary")
    }

    @Test
    func reflectionKeepsFourTimesVerticalStretchAtDifferentPageHeights() {
        let source = CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: 0, y: 0), "inputPoint1": CIVector(x: 0, y: 80),
            "inputColor0": CIColor(red: 0, green: 0, blue: 0),
            "inputColor1": CIColor(red: 1, green: 0, blue: 0)
        ])!.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: 100, height: 80))
        let context = CIContext()
        for height: CGFloat in [120, 240] {
            let reflected = NftDetailsImageProcessor.reflectedBand(from: source, height: height)
            var rgba = [UInt8](repeating: 0, count: 4)
            context.render(reflected, toBitmap: &rgba, rowBytes: 4,
                bounds: CGRect(x: 50, y: height - 24, width: 1, height: 1), format: .RGBA8,
                colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!)
            // 24 points into a 4× reflection comes from 6 points into the original 80-point band.
            #expect(abs(Double(rgba[0]) / 255 - 6.0 / 80) < 0.025,
                    "Changing the title/action-row height must crop the reflection, never rescale it")
        }
    }

    @Test
    func nativeVideoWipeMatchesTheStaticBackgroundTransitionInBothDirections() throws {
        let width = 128
        let extent = CGRect(x: 0, y: 0, width: width, height: 1)
        let context = NftDetailsImageProcessor.atmosphereContext
        for rtl in [false, true] {
            for progress: CGFloat in [0, 0.05, 0.25, 0.5, 0.75, 0.95, 1] {
                let filter = try #require(CIFilter(name: "CISwipeTransition"))
                filter.setValue(CIImage(color: .white).cropped(to: extent), forKey: kCIInputImageKey)
                filter.setValue(CIImage(color: .black).cropped(to: extent), forKey: kCIInputTargetImageKey)
                filter.setValue(rtl ? 0.0 : -Double.pi, forKey: kCIInputAngleKey)
                filter.setValue(progress, forKey: kCIInputTimeKey)
                filter.setValue(CGFloat(width) * NftDetailsPageWipe.widthRatio, forKey: kCIInputWidthKey)
                filter.setValue(0, forKey: "inputOpacity")
                filter.setValue(CIVector(cgRect: extent), forKey: kCIInputExtentKey)
                var expected = [UInt8](repeating: 0, count: width * 4)
                context.render(try #require(filter.outputImage), toBitmap: &expected, rowBytes: width * 4,
                    bounds: extent, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
                for left in [true, false] {
                    let mask = CAGradientLayer()
                    mask.frame = extent
                    NftDetailsPageWipe.configure(mask, progress: progress, showingLeft: left, isRTL: rtl)
                    var actual = [UInt8](repeating: 0, count: width * 4)
                    let bitmap = try #require(CGContext(data: &actual, width: width, height: 1, bitsPerComponent: 8,
                        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                    mask.render(in: bitmap)
                    for x in stride(from: 0, to: width, by: 8) {
                        let expectedAlpha = left ? Int(expected[x * 4]) : 255 - Int(expected[x * 4])
                        #expect(abs(Int(actual[x * 4 + 3]) - expectedAlpha) <= 2,
                            "Live video and static artwork must use the same wipe at every position")
                    }
                }
            }
        }
    }

    @Test
    func backgroundGradientUsesTheProductionSolidBandAndBlurredFade() {
        let source = CIImage(color: CIColor.white).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 80))
        let height: CGFloat = 190
        let atmosphere = NftDetailsImageProcessor.atmosphere(from: source, height: height, scale: 1, color: .black, displayScale: 3)
        let context = NftDetailsImageProcessor.atmosphereContext
        func brightness(_ y: CGFloat) -> Double {
            var pixel = [UInt8](repeating: 0, count: 4)
            context.render(atmosphere, toBitmap: &pixel, rowBytes: 4,
                bounds: CGRect(x: 50, y: y, width: 1, height: 1), format: .RGBA8,
                colorSpace: CGColorSpaceCreateDeviceRGB())
            return Double(pixel[0]) / 255
        }
        let samples = stride(from: height, through: 0, by: -10).map(brightness)
        for (above, below) in zip(samples, samples.dropFirst()) {
            #expect(below <= above + 0.01, "The production fade must decrease continuously")
        }
        #expect(brightness(height * 0.5) > 0.1)
        #expect(brightness(30) < 0.015, "Production keeps a 60 point solid band below the gradient")
        #expect(brightness(0) < 0.015)
    }

    @Test
    func navigationContrastSamplesTheImageRegionUnderTheButton() {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100)).image { ctx in
            UIColor.black.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
            UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 50, height: 50))
        }
        let sample = NftDetailsImageSample(image: image)
        var white: CGFloat = 0, alpha: CGFloat = 0
        sample.color(in: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2), over: .black).getWhite(&white, alpha: &alpha)
        #expect(white > 0.95)
        sample.color(in: CGRect(x: 0.1, y: 0.6, width: 0.2, height: 0.2), over: .white).getWhite(&white, alpha: &alpha)
        #expect(white < 0.05)
        #expect(sample.color(in: CGRect(x: 0, y: -1, width: 0.2, height: 0.2), over: .black) == .black)
    }

    @Test
    func twoFingerSequenceOwnsInteractionBeforePinchThresholdUntilFinalTouchUp() {
        let view = UIView()
        let guardGesture = NftDetailsPinchTouchGuard()
        let pan = UIPanGestureRecognizer()
        let pinch = UIPinchGestureRecognizer()
        view.addGestureRecognizer(guardGesture)
        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(pinch)
        var claims: [Bool] = []
        guardGesture.canClaim = { true }
        guardGesture.onClaimChanged = { claimed in
            claims.append(claimed)
            pan.isEnabled = !claimed
        }
        guardGesture.updateTouchCount(1)
        #expect(pan.isEnabled && claims.isEmpty, "One-finger scrolling must remain immediate")
        guardGesture.updateTouchCount(2)
        #expect(guardGesture.isClaimed && !pan.isEnabled)
        #expect(pinch.state == .possible && pinch.isEnabled, "Capture before any zoom threshold is crossed")
        #expect(!guardGesture.canBePrevented(by: pan) && !guardGesture.canPrevent(pinch))
        guardGesture.updateTouchCount(1)
        #expect(guardGesture.isClaimed && !pan.isEnabled, "The remaining finger must not become a swipe")
        guardGesture.updateTouchCount(2)
        #expect(claims == [true], "Adding a finger again stays within the same interaction")
        guardGesture.updateTouchCount(0)
        #expect(guardGesture.isClaimed && !pan.isEnabled, "Final touch-up must not turn into a tap")
        guardGesture.reset()
        #expect(!guardGesture.isClaimed && pan.isEnabled && claims == [true, false])
        guardGesture.canClaim = { false }
        guardGesture.updateTouchCount(2)
        #expect(!guardGesture.isClaimed && pan.isEnabled, "Do not capture unrelated content")
    }

    @Test
    func pinchKeepsAnchorAndDoesNotJumpWhenOneFingerLifts() async {
        let parent = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let source = UIView(frame: parent.bounds)
        parent.addSubview(source)
        let content = ZoomContent()
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([content.widthAnchor.constraint(equalToConstant: 100), content.heightAnchor.constraint(equalToConstant: 100)])
        content.addToParent(source, bindToTop: true, yConstant: 150, xConstant: -50)
        source.layoutIfNeeded()
        let gesture = PinchGesture()
        gesture.point = CGPoint(x: 110, y: 110)
        var finished = false
        let zoom = NftDetailsInlineZoom(content: content, source: source, parent: parent, gesture: gesture) { finished = true }
        gesture.scale = 2
        zoom.update(gesture)
        let anchor = content.convert(CGPoint(x: 10, y: 10), to: parent)
        #expect(abs(anchor.x - 110) < 0.01 && abs(anchor.y - 110) < 0.01)
        gesture.point = CGPoint(x: 130, y: 140)
        zoom.update(gesture)
        let moved = content.convert(CGPoint(x: 10, y: 10), to: parent)
        #expect(abs(moved.x - 130) < 0.01 && abs(moved.y - 140) < 0.01)
        gesture.touches = 1
        gesture.point = CGPoint(x: 240, y: 260)
        zoom.update(gesture)
        #expect(content.convert(CGPoint(x: 10, y: 10), to: parent) == moved)
        zoom.finish(animated: false)
        try? await Task.sleep(for: .milliseconds(30))
        #expect(finished && content.superview === source)
        #expect(content.frame == CGRect(x: 100, y: 100, width: 100, height: 100))
    }

    @Test
    func coverFlowLayoutPreservesThePositionWhileAUserScrollIsInFlight() async {
        let models = (0..<8).map { index in
            NftDetailsItemModel(item: .init(id: "flow-\(index)", name: "\(index)", description: nil,
                thumbnailUrl: nil, imageUrl: nil, lottieUrl: nil, attributes: nil, collection: nil, tonDomain: nil), index: index)
        }
        let resolver = NftDetailsColorResolver(colorCache: NftDetailsColorCache(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        let delegate = CoverFlowTestDelegate()
        let flow = _CoverFlowView(models: models, itemSize: 144, thumbnailDownloader: .default,
                                 colorResolver: resolver, tileCornerRadius: 12)
        flow.delegate = delegate
        flow.frame = CGRect(x: 0, y: 0, width: 400, height: 144)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        window.addSubview(flow)
        window.isHidden = false
        flow.layoutIfNeeded()
        try? await Task.sleep(for: .milliseconds(50))
        flow.layoutIfNeeded()
        let collection = flow.subviews.compactMap { $0 as? UICollectionView }.first!
        let scroll = collection.subviews.compactMap { $0 as? UIScrollView }.first!
        flow.scrollViewWillBeginDragging(scroll)
        let target = CGFloat(models.count - 1) * 84 - scroll.adjustedContentInset.left
        scroll.setContentOffset(CGPoint(x: target, y: 0), animated: false)
        flow.scrollViewDidEndDragging(scroll, willDecelerate: true)
        // A vertical gesture relayouts the header before horizontal deceleration ends.
        for _ in 0..<3 { flow.setNeedsLayout(); flow.layoutIfNeeded() }
        #expect(abs(scroll.contentOffset.x - target) < 1)
        flow.scrollViewDidEndDecelerating(scroll)
        #expect(delegate.selectedIndex == models.count - 1)
        window.isHidden = true
    }

    @Test
    func shortPageReturnsUpWithoutClampingOrCommittingAnOldSelection() async {
        let models = (0..<3).map { index in
            NftDetailsItemModel(item: .init(id: "height-\(index)", name: "Page \(index)",
                description: index == 0 ? String(repeating: "Long description line.\n", count: 80) : "Short description",
                thumbnailUrl: nil, imageUrl: nil, lottieUrl: nil, attributes: nil, collection: nil, tonDomain: nil), index: index)
        }
        let resolver = NftDetailsColorResolver(colorCache: NftDetailsColorCache(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        let delegate = PagerTestDelegate()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let scroll = UIScrollView(frame: window.bounds)
        scroll.contentInsetAdjustmentBehavior = .never
        window.addSubview(scroll)
        let pager = NftDetailsPagerView(models: models, colorResolver: resolver, currentIndex: 0,
            layoutGeometry: .init(topSafeAreaInset: 60, collapsedAreaHeight: 165, pageWidth: 400, expandedImageFrame: CGRect(x: 0, y: 0, width: 400, height: 400)),
            delegate: delegate, initiallyExpanded: false)
        scroll.addSubview(pager)
        NSLayoutConstraint.activate([
            pager.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            pager.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            pager.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            pager.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            pager.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
        ])
        window.isHidden = false
        window.layoutIfNeeded()
        scroll.setContentOffset(CGPoint(x: 0, y: 180), animated: false)
        pager.syncPagerWithCoverFlow(0, currentModel: models[1])
        pager.animateToIndex(1)
        #expect(pager.currentIndex == 1, "Selection must commit before the vertical return")
        #expect(abs(scroll.contentOffset.y - 180) < 1, "Height change must not instantly clamp the scroll offset")
        try? await Task.sleep(for: .milliseconds(70))
        #expect(scroll.contentOffset.y > 0 && scroll.contentOffset.y < 180)
        pager.syncPagerWithCoverFlow(0, currentModel: models[2])
        pager.animateToIndex(2)
        try? await Task.sleep(for: .milliseconds(400))
        #expect(abs(scroll.contentOffset.y) < 1)
        #expect(pager.currentIndex == 2 && delegate.selectedIndex == 2, "An old return animation must not select page 1 again")
        window.isHidden = true
    }

    @Test
    func coverFlowScalesWithArtworkThroughInterruptedExpansion() async throws {
        let models = (0..<3).map { model("scale-\($0)") }
        let resolver = NftDetailsColorResolver(colorCache: NftDetailsColorCache(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        let delegate = HeaderTestDelegate()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let header = NftDetailsMainHeaderView(frame: window.bounds, models: models, selectedModel: models[1],
            delegate: delegate, layoutGeometry: .init(topSafeAreaInset: 60, leadingSafeAreaInset: 0,
                trailingSafeAreaInset: 0, collapsedAreaHeight: 165, pageWidth: 400, expandedImageFrame: CGRect(x: 0, y: 0, width: 400, height: 400)),
            coverFlowThumbnailDownloader: ImageDownloader(name: "scale-test"), colorResolver: resolver)
        window.addSubview(header)
        window.isHidden = false
        defer { window.isHidden = true }
        window.layoutIfNeeded()
        func find<T: UIView>(_ root: UIView, _ type: T.Type) -> T? {
            if let value = root as? T { return value }
            return root.subviews.compactMap { find($0, type) }.first
        }
        let flow = try #require(find(header, _CoverFlowView.self))
        let preview = try #require(find(header, NftDetailsItemPreview.self))
        let scroll = UIScrollView()
        header.handleVerticalScroll(scroll, isExpanded: true)
        try? await Task.sleep(for: .milliseconds(100))
        let scale = CGFloat(flow.layer.presentation()?.transform.m11 ?? 1)
        let imageWidth = preview.layer.presentation()?.bounds.width ?? 144
        #expect(scale > 1.1)
        #expect(abs(scale - imageWidth / 144) < 0.08, "Side cards must follow the central artwork's scale")
        let atmosphere = try #require(preview.subviews.first { $0.accessibilityIdentifier == "NFTAtmosphere" })
        let band = try #require(atmosphere.layer.presentation())
        #expect(abs(band.bounds.width - imageWidth) < 1, "Artwork and reflection must share the same animation")
        #expect(band.opacity == 1, "Expansion must reveal the reflection geometrically, without an independent fade")
        header.handleVerticalScroll(scroll, isExpanded: false)
        try? await Task.sleep(for: .milliseconds(50))
        let collapsingBand = try #require(atmosphere.layer.presentation())
        #expect(collapsingBand.opacity == 1 && collapsingBand.bounds.height > 0,
                "The lower section must crop with the artwork instead of fading away early")
        header.handleVerticalScroll(scroll, isExpanded: true)
        try? await Task.sleep(for: .milliseconds(450))
        #expect(abs(flow.transform.a - 400 / 144) < 0.01)
        #expect(abs(preview.bounds.width - 400) < 1)
        for offset: CGFloat in [0, 16, 2, -12, 0] {
            scroll.contentOffset.y = offset
            header.handleVerticalScroll(scroll, isExpanded: true)
            let artwork = preview.convert(preview.bounds, to: header)
            let band = atmosphere.convert(atmosphere.bounds, to: header)
            let overlap = NftDetailsImageProcessor.atmosphereOverlap * preview.transform.a
            #expect(abs(band.minY + overlap - artwork.maxY) < 1, "The reflection must follow the finger in this frame")
        }
        header.handleVerticalScroll(scroll, isExpanded: false)
        try? await Task.sleep(for: .milliseconds(400))
        #expect(flow.transform == .identity)
        #expect(abs(flow.superview!.frame.midY - 132) < 1)
    }

    @Test
    func sideCardsAreReadyBeforeTheMediaViewerFadesOut() async throws {
        let models = (0..<3).map { model("return-\($0)") }
        let resolver = NftDetailsColorResolver(colorCache: NftDetailsColorCache(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        let delegate = HeaderTestDelegate()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let header = NftDetailsMainHeaderView(frame: window.bounds, models: models, selectedModel: models[1],
            delegate: delegate, layoutGeometry: .init(topSafeAreaInset: 60, leadingSafeAreaInset: 0,
                trailingSafeAreaInset: 0, collapsedAreaHeight: 165, pageWidth: 400, expandedImageFrame: CGRect(x: 0, y: 0, width: 400, height: 400)),
            coverFlowThumbnailDownloader: ImageDownloader(name: "return-test"), colorResolver: resolver)
        window.addSubview(header)
        window.isHidden = false
        defer { window.isHidden = true }
        window.layoutIfNeeded()
        let scroll = UIScrollView()
        header.handleVerticalScroll(scroll, isExpanded: true)
        try? await Task.sleep(for: .milliseconds(400))
        header.openFullScreenPreview()
        // Pulling expanded artwork into the viewer collapses the page below it.
        header.handleVerticalScroll(scroll, isExpanded: false)
        try? await Task.sleep(for: .milliseconds(400))
        func find(_ root: UIView) -> _CoverFlowView? {
            if let flow = root as? _CoverFlowView { return flow }
            return root.subviews.compactMap { find($0) }.first
        }
        let flow = try #require(find(header))
        #expect(flow.alpha == 1 && flow.transform == .identity)
        #expect(abs(flow.superview!.frame.midY - 132) < 1)
        #expect(header.dismissFullScreen())
        try? await Task.sleep(for: .milliseconds(100))
        #expect((flow.layer.presentation()?.opacity ?? 0) > 0.99, "Side cards must already be visible while the media backdrop fades")
        try? await Task.sleep(for: .milliseconds(400))
        #expect(flow.alpha == 1)
    }

    @Test
    func atmosphereEndsBelowTheActionRowForBothSingleAndMultilineTitles() throws {
        let resolver = NftDetailsColorResolver(colorCache: NftDetailsColorCache(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        let delegate = PageTestDelegate()
        for name in ["NFT", "A deliberately long NFT title that wraps onto multiple lines"] {
            let item = model(name)
            let page = NftDetailsPageView(model: item, colorResolver: resolver,
                layoutGeometry: .init(expandedImageFrame: CGRect(x: 0, y: 0, width: 400, height: 400), collapsedHeight: 225, width: 400),
                isExpanded: true, delegate: delegate)
            page.frame.size.height = page.getFullHeight()
            page.layoutIfNeeded()
            let stack = try #require(page.subviews.compactMap { $0 as? UIStackView }.first)
            let toolbar = try #require(stack.arrangedSubviews.first { $0 is UIVisualEffectView })
            let descriptionTop = toolbar.convert(toolbar.bounds, to: page).maxY + stack.customSpacing(after: toolbar)
            #expect(abs(400 + page.atmosphereHeight - descriptionTop) < 1,
                "The reflection must span the buttons and end where the information blocks begin")
        }
    }

    @Test
    func cachedColorIsAvailableToAllConcurrentFirstReaders() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let writer = NftDetailsColorCache(fileURL: url)
            writer.setColor(.red, forKey: "cached")
            writer.flush()
        }
        let reader = NftDetailsColorCache(fileURL: url)
        DispatchQueue.concurrentPerform(iterations: 32) { _ in
            let result = reader.color(forKey: "cached")
            #expect(result.0 && result.1 != nil)
        }
    }
}

@MainActor
private final class NftDetailsTestController: NftDetailsBaseVC {
    override func ntfDetailsOnConfigureAction(forModel model: NftDetailsItemModel, action: NftDetailsItemModel.Action) -> NftDetailsActionConfig? {
        action == .share ? .init(onTap: {}) : nil
    }
}

@MainActor
private final class ZoomContent: UIView, NftDetailsFullScreenOverlayContent {
    var centerYConstraint: NSLayoutConstraint?
    var centerXConstraint: NSLayoutConstraint?
}

@MainActor
private final class PinchGesture: UIPinchGestureRecognizer {
    var point = CGPoint.zero
    var touches = 2
    override var numberOfTouches: Int { touches }
    override func location(in view: UIView?) -> CGPoint { point }
}

@MainActor
private final class CoverFlowTestDelegate: CoverFlowDelegate {
    var selectedIndex: Int?
    func coverFlowDidSelectModel(_ model: NftDetailsItemModel) { selectedIndex = model.index }
    func coverFlowDidTapModel(_ model: NftDetailsItemModel, view: UIView, longTap: Bool) {}
    func onCoverFlowScrollProgress(_ progress: CGFloat, currentModel: NftDetailsItemModel) {}
}

@MainActor
private final class PagerTestDelegate: NftDetailsPagerDelegate {
    var selectedIndex: Int?
    func pagerDidSelectModel(_ pager: NftDetailsPagerView, model: NftDetailsItemModel) { selectedIndex = model.index }
    func pagerDidScroll(_ pager: NftDetailsPagerView, withProgress progress: CGFloat, fromModel: NftDetailsItemModel, toModel: NftDetailsItemModel?) {}
    func pagerDidRequestFullScreenPreview() {}
    func ntfDetailsOnConfigureAction(forModel model: NftDetailsItemModel, action: NftDetailsItemModel.Action) -> NftDetailsActionConfig? {
        action == .share ? .init(onTap: {}) : nil
    }
}

@MainActor
private final class HeaderTestDelegate: NftDetailsMainHeaderViewDelegate {
    func headerCoverFlowDidSelectModel(_ model: NftDetailsItemModel) {}
    func headerCoverFlowDidScroll(withProgress progress: CGFloat, currentModel: NftDetailsItemModel) {}
    func headerCoverFlowDidTapSelectedModel() {}
    func headerDidChangePreviewVisibilityInternaly(_ headerView: NftDetailsMainHeaderView) {}
}

@MainActor
private final class PageTestDelegate: NftDetailsPageViewDelegate {
    func pageDidRequestFullScreenPreview() {}
    func ntfDetailsOnConfigureAction(forModel model: NftDetailsItemModel, action: NftDetailsItemModel.Action) -> NftDetailsActionConfig? {
        action == .share ? .init(onTap: {}) : nil
    }
}
