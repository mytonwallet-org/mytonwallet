import Testing
import UIKit
import WalletResources
@testable import UIComponents

@MainActor @Suite(.serialized)
struct StoriesAdaptiveLayoutTests {
    init() { _ = WalletResourcesBundle.bundle.load() }

    @Test func fitPortraitCardsInsideTabletAndDuoSafeAreas() {
        for (size, insets) in [
            (CGSize(width: 1024, height: 1366), UIEdgeInsets(top: 24, left: 0, bottom: 20, right: 0)),
            (CGSize(width: 1366, height: 1024), UIEdgeInsets(top: 24, left: 0, bottom: 20, right: 0)),
            (CGSize(width: 669, height: 951), UIEdgeInsets(top: 82, left: 0, bottom: 20, right: 0)),
            (CGSize(width: 951, height: 669), UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 84)),
            (CGSize(width: 951, height: 669), UIEdgeInsets(top: 0, left: 84, bottom: 0, right: 0)),
            (CGSize(width: 320, height: 700), UIEdgeInsets(top: 24, left: 0, bottom: 20, right: 0)),
        ] {
            let bounds = CGRect(origin: .zero, size: size)
            let frame = StoriesPresentationController.calculateFrame(in: bounds, safeAreaInsets: insets,
                contentSize: CGSize(width: 402, height: 874), isCardLayout: true)
            let safeFrame = bounds.inset(by: insets)
            #expect(safeFrame.insetBy(dx: 23, dy: 23).contains(frame))
            #expect(abs(frame.width / frame.height - 402 / 874.0) < 0.001)
            #expect(frame.midX == safeFrame.midX)
            #expect(frame.midY == safeFrame.midY)
            #expect(frame.height <= 1080)
        }
    }

    @Test func keepPhonesPortraitAndAllowRotationForTabletsAndUnfoldedDuo() {
        guard #available(iOS 17, *) else { return }
        let controller = StoriesViewController(pages: [])
        controller.loadViewIfNeeded()
        controller.traitOverrides.userInterfaceIdiom = .phone
        for size in [CGSize(width: 440, height: 956), CGSize(width: 956, height: 440)] {
            controller.view.frame.size = size
            #expect(controller.supportedInterfaceOrientations == .portrait)
            #expect(controller.preferredInterfaceOrientationForPresentation == .portrait)
            #expect(StoriesPresentationController.calculateFrame(in: controller.view.bounds, safeAreaInsets: .zero,
                contentSize: .zero, isCardLayout: controller.isCardLayout) == controller.view.bounds)
        }
        controller.view.frame.size = CGSize(width: 951, height: 669)
        #expect(controller.supportedInterfaceOrientations == .all)
        controller.traitOverrides.userInterfaceIdiom = .pad
        controller.view.frame.size = CGSize(width: 320, height: 700)
        #expect(controller.supportedInterfaceOrientations == .all)
    }

    @Test func keepControlsInsideTheCardAndPreserveThePageOnResize() throws {
        guard #available(iOS 17, *) else { return }
        let controller = StoriesViewController(pages: [
            .init(id: "first", title: "First story", body: "Portrait artwork"),
            .init(id: "second", title: "Second story", body: "The next page", buttonTitle: "Done"),
        ])
        controller.loadViewIfNeeded()
        controller.traitOverrides.userInterfaceIdiom = .pad
        _ = controller.perform(NSSelectorFromString("accessibilityNext"))
        for size in [CGSize(width: 430, height: 934), CGSize(width: 286, height: 621), CGSize(width: 272, height: 591)] {
            controller.view.frame.size = size
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            controller.view.layoutIfNeeded()
            let close = try #require(controller.view.subviews.first { $0.accessibilityIdentifier == "Stories.Close" })
            let content = try #require(controller.view.subviews.first { $0.accessibilityIdentifier == "Stories.Content" })
            let progress = try #require(controller.view.subviews.first { $0.accessibilityIdentifier == "Stories.Progress" })
            #expect(controller.view.bounds.contains(close.frame))
            #expect(controller.view.bounds.contains(content.frame))
            #expect(progress.frame.minY == 24)
            #expect(close.frame.maxY <= content.frame.minY)
            #expect(controller.view.clipsToBounds)
            #expect(controller.playback.index == 1)
            controller.resetDismissalGeometry()
            #expect(controller.view.clipsToBounds)
        }
    }

    @Test func useHiddenActionSpaceForLongCopyInNarrowCards() throws {
        guard #available(iOS 17, *) else { return }
        let controller = StoriesViewController(pages: [
            .init(id: "liquidation", title: "Your position can close automatically",
                  body: "This is liquidation: if losses leave too little margin, your position may be closed. Watch the liquidation price."),
        ])
        controller.traitOverrides.userInterfaceIdiom = .pad
        controller.traitOverrides.preferredContentSizeCategory = .large
        controller.loadViewIfNeeded()
        controller.view.frame.size = CGSize(width: 272, height: 591)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        controller.view.layoutIfNeeded()
        let content = try #require(controller.view.subviews.first { $0.accessibilityIdentifier == "Stories.Content" })
        let copy = try #require(content.subviews.first { $0 is UIScrollView })
        #expect(content.frame.height == 233)
        #expect(copy.frame.maxY == content.bounds.maxY)
        #expect(content.frame.minY >= controller.view.bounds.height * 0.55)
    }

    @Test func alignClosedDuoArtworkWithCopyAndControlsBesideTheStatusArea() throws {
        guard #available(iOS 17, *) else { return }
        let background = UIView()
        let controller = StoriesViewController(pages: [
            .init(id: "intro", title: "Meet perpetual futures", body: "Open positions on both rising and falling asset prices."),
            .init(id: "finale", title: "Ready to try futures?", body: "Choose a market.", buttonTitle: "View Markets"),
        ], backgroundView: background)
        controller.traitOverrides.userInterfaceIdiom = .phone
        controller.loadViewIfNeeded()
        for insets in [UIEdgeInsets(top: 0, left: 0, bottom: 20, right: 86),
                       UIEdgeInsets(top: 0, left: 86, bottom: 20, right: 0),
                       UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0)] {
            controller.view.frame.size = CGSize(width: 466, height: 678)
            controller.additionalSafeAreaInsets = insets
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            controller.view.layoutIfNeeded()
            let media = try #require(controller.view.subviews.flatMap(\.subviews).first { $0 is StoryMediaView })
            let mediaFrame = media.convert(media.bounds, to: controller.view)
            let content = try #require(controller.view.subviews.first { $0.accessibilityIdentifier == "Stories.Content" })
            let progress = try #require(controller.view.subviews.first { $0.accessibilityIdentifier == "Stories.Progress" })
            let close = try #require(controller.view.subviews.first { $0.accessibilityIdentifier == "Stories.Close" })
            let safeFrame = controller.view.safeAreaLayoutGuide.layoutFrame
            #expect(mediaFrame.minX == safeFrame.minX)
            #expect(mediaFrame.maxX == safeFrame.maxX)
            #expect(mediaFrame.height == controller.view.bounds.height)
            #expect(background.frame == mediaFrame)
            #expect(content.frame.midX == mediaFrame.midX)
            #expect(progress.frame.minX == mediaFrame.minX + 24)
            #expect(progress.frame.maxX == mediaFrame.maxX - 24)
            #expect(close.frame.maxX == mediaFrame.maxX - 24)
            if controller.playback.index == 0 { _ = controller.perform(NSSelectorFromString("accessibilityNext")) }
        }
    }

    @Test func keepLeverageCopyBelowItsArtworkOnShortPhones() throws {
        guard #available(iOS 17, *) else { return }
        let controller = StoriesViewController(pages: [
            .init(id: "leverage", title: "Leverage amplifies the result",
                  body: "Margin is your money in the position. With 5× leverage, $10 controls a $50 position — gains and losses are also amplified 5×."),
        ])
        controller.preferredContentSize = CGSize(width: 402, height: 874)
        controller.traitOverrides.userInterfaceIdiom = .phone
        controller.traitOverrides.preferredContentSizeCategory = .large
        controller.loadViewIfNeeded()
        for (size, insets) in [
            (CGSize(width: 466, height: 678), UIEdgeInsets(top: 0, left: 0, bottom: 20, right: 86)),
            (CGSize(width: 466, height: 678), UIEdgeInsets(top: 0, left: 86, bottom: 20, right: 0)),
            (CGSize(width: 440, height: 956), UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0)),
        ] {
            controller.view.frame.size = size
            controller.additionalSafeAreaInsets = insets
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            controller.view.layoutIfNeeded()
            let content = try #require(controller.view.subviews.first { $0.accessibilityIdentifier == "Stories.Content" })
            let copy = try #require(content.subviews.first { $0 is UIScrollView } as? UIScrollView)
            let media = try #require(controller.view.subviews.flatMap(\.subviews).first { $0 is StoryMediaView })
            let scale = max(media.bounds.width / 402, media.bounds.height / 874)
            // The leverage scale ends at 550 points in the bundled 402 × 874 artwork
            let artworkBottom = 550 * scale + (media.bounds.height - 874 * scale) / 2
            #expect(content.frame.minY >= artworkBottom + 16)
            #expect(copy.contentSize.height <= copy.bounds.height + 1)
            #expect(controller.view.safeAreaLayoutGuide.layoutFrame.contains(content.frame))
        }
    }
}
