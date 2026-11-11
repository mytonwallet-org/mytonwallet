import CoreText
import Dependencies
import Foundation
import Testing
@testable import UIComponents
import UIKit
import WalletContext
import WalletCore
import WalletResources
@testable import UIAssets

@MainActor @Suite(.serialized)
struct PerpsOnboardingTests {
    init() { _ = WalletResourcesBundle.bundle.load() }

    @Test func onlyConfirmedEmptyAccountShowsOnboarding() async throws {
        let store = store(client: client())
        #expect(!PerpsHomeAdapter.home(store: store, accountId: "wallet").showsOnboarding)
        await store.refresh(accountId: "wallet")
        #expect(PerpsHomeAdapter.home(store: store, accountId: "wallet").showsOnboarding)
        #expect(!PerpsHomeAdapter.home(store: store, accountId: "other").showsOnboarding)
    }

    @Test(arguments: ["snapshot-failure", "history-failure", "partial-snapshot"])
    func incompleteInitialReadsDoNotClaimTheAccountIsNew(_ mode: String) async throws {
        var client = client()
        if mode == "snapshot-failure" { client.positions = { _ in throw PerpsError.invalidResponse } }
        if mode == "history-failure" { client.history = { _ in throw PerpsError.invalidResponse } }
        if mode == "partial-snapshot" {
            var snapshot = try emptySnapshot()
            snapshot.unavailableDexs = ["xyz"]
            client.positions = { _ in snapshot }
        }
        let store = store(client: client)
        await store.refresh(accountId: "wallet")
        #expect(!PerpsHomeAdapter.home(store: store, accountId: "wallet").showsOnboarding)
    }

    @Test(arguments: ["unknown-fill", "unlisted-trade", "cursor"])
    func historyThatIsNotRenderedStillHidesOnboarding(_ kind: String) async throws {
        var client = client()
        let history: ApiPerpsActivityHistory
        switch kind {
        case "unknown-fill":
            let fill = try JSONDecoder().decode(ApiPerpsFill.self, from: Data("""
            {"coin":"UNKNOWN","time":1000,"feeToken":"USDC","eventKind":"opened","positionSide":"long"}
            """.utf8))
            history = .init(fills: [fill])
        case "unlisted-trade": history = .init(fills: [], hasActivity: true)
        default: history = .init(fills: [], nextCursor: "older")
        }
        client.history = { _ in history }
        let store = store(client: client)
        await store.refresh(accountId: "wallet")
        let data = PerpsHomeAdapter.home(store: store, accountId: "wallet")
        #expect(data.activities.isEmpty)
        #expect(!data.showsOnboarding)
    }

    @Test func pendingOperationSuppressesBannerForItsAccount() async {
        let operation = ApiPerpsOperation(id: "pending", accountId: "wallet", assetId: "btc", kind: "open", createdAt: 0)
        let store = store(client: client(), operations: [operation])
        await store.refresh(accountId: "wallet")
        await store.refresh(accountId: "other")
        #expect(!PerpsHomeAdapter.home(store: store, accountId: "wallet").showsOnboarding)
        #expect(PerpsHomeAdapter.home(store: store, accountId: "other").showsOnboarding)
    }

    @Test(arguments: ["completed", "partial"])
    func submittedOperationHidesBannerBeforeBackendHistoryCatchesUp(_ state: String) async {
        var operation = ApiPerpsOperation(id: "submitted", accountId: "wallet", assetId: "btc", kind: "open", createdAt: 0)
        operation.state = state
        let store = store(client: client(), operations: [operation])
        await store.refresh(accountId: "wallet")
        await store.refresh(accountId: "other")
        #expect(store.hasActivityHistory["wallet"] == false)
        #expect(!PerpsHomeAdapter.home(store: store, accountId: "wallet").showsOnboarding)
        #expect(PerpsHomeAdapter.home(store: store, accountId: "other").showsOnboarding)
    }

    @Test func restoredConfirmedEmptyAccountShowsBannerBeforeRefreshingAndAfterOfflineFailure() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = store(client: client(), directory: directory)
        await original.refresh(accountId: "wallet")
        var offline = client()
        offline.positions = { _ in throw PerpsError.invalidResponse }
        offline.history = { _ in throw PerpsError.invalidResponse }
        let restored = store(client: offline, directory: directory)
        await restored.loadFromCache(accountIds: ["wallet"])
        #expect(PerpsHomeAdapter.home(store: restored, accountId: "wallet").showsOnboarding)
        await restored.refresh(accountId: "wallet")
        #expect(PerpsHomeAdapter.home(store: restored, accountId: "wallet").showsOnboarding)
    }

    @Test func bannerMatchesDesignGeometryAndReleasesItsActionOnReuse() throws {
        let cell = PerpsOnboardingBannerCell(frame: CGRect(x: 0, y: 0, width: 370, height: 270))
        cell.layoutIfNeeded()
        let title = try #require(descendants(cell).first { $0.accessibilityIdentifier == "perps.onboarding.title" })
        let description = try #require(descendants(cell).first { $0.accessibilityIdentifier == "perps.onboarding.description" })
        let image = try #require(descendants(cell).first { $0.accessibilityIdentifier == "perps.onboarding.illustration" } as? UIImageView)
        let button = try #require(descendants(cell).first { $0.accessibilityIdentifier == "perps.onboarding.open" } as? UIControl)
        #expect(cell.contentView.layer.cornerRadius == 26)
        #expect(title.frame.minX == 24 && title.frame.width == 180)
        #expect(description.frame.minY - title.frame.maxY == 8)
        #expect(button.frame == CGRect(x: 24, y: 194, width: 322, height: 52))
        #expect(image.frame == CGRect(x: 162, y: 46, width: 196, height: 114))
        #expect(image.image?.scale == 3)
        let dismiss = try #require(descendants(cell).first { $0.accessibilityIdentifier == "perps.onboarding.dismiss" } as? UIControl)
        #expect(!cell.acceptsBannerTouch(on: dismiss))
        cell.frame.size = CGSize(width: 603, height: 140)
        cell.setNeedsLayout()
        cell.layoutIfNeeded()
        #expect(image.frame == CGRect(x: 330, y: 3, width: 230, height: 134))
        #expect(image.image?.scale == 3)
        #expect(button.frame.minX == 24 && button.frame.height == 40)
        #expect(description.frame.maxX <= image.frame.minX)
        let wideAttributes = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: 0, section: 0))
        wideAttributes.size = CGSize(width: 603, height: 140)
        #expect(cell.preferredLayoutAttributesFitting(wideAttributes).size.height == 140)
        var count = 0
        cell.onOpen = { count += 1 }
        cell.onDismiss = { count += 10 }
        button.sendActions(for: .touchUpInside)
        #expect(count == 1)
        dismiss.sendActions(for: .touchUpInside)
        #expect(count == 11)
        cell.prepareForReuse()
        button.sendActions(for: .touchUpInside)
        dismiss.sendActions(for: .touchUpInside)
        #expect(count == 11)
    }

    @Test(arguments: ["ru", "uk"])
    func keepLocalizedTitleWordsWholeWhenResizing(_ language: String) throws {
        try withMessageLanguage(language) {
            let cell = PerpsOnboardingBannerCell(frame: .zero)
            for width: CGFloat in [370, 343, 603, 370] {
                let attributes = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: 0, section: 0))
                attributes.size = CGSize(width: width, height: 270)
                cell.frame = CGRect(origin: .zero, size: cell.preferredLayoutAttributesFitting(attributes).size)
                cell.setNeedsLayout()
                cell.layoutIfNeeded()
                let title = try #require(descendants(cell).first { $0.accessibilityIdentifier == "perps.onboarding.title" } as? UILabel)
                let description = try #require(descendants(cell).first { $0.accessibilityIdentifier == "perps.onboarding.description" })
                let button = try #require(descendants(cell).first { $0.accessibilityIdentifier == "perps.onboarding.open" })
                let text = try #require(title.attributedText)
                let path = CGPath(rect: title.bounds, transform: nil)
                let frame = CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(text), CFRange(), path, nil)
                let lines = CTFrameGetLines(frame) as! [CTLine]
                let renderedLines = lines.map { line in
                    let range = CTLineGetStringRange(line)
                    return (text.string as NSString).substring(with: NSRange(location: range.location, length: range.length))
                }
                for word in text.string.split(whereSeparator: \.isWhitespace) {
                    #expect(renderedLines.contains { $0.contains(word) }, "Width \(width): \(renderedLines), word: \(word)")
                }
                #expect(description.frame.maxY + 12 <= button.frame.minY)
                if language == "ru" {
                    Attachment.record(try #require(cell.contentView.makeLayerImage().pngData()), named: "onboarding-ru-\(Int(width)).png")
                }
            }
        }
    }

    @Test func onboardingReplacesHeroAndKeepsMarketDividerSpacing() throws {
        try withDependencies { $0.context = .live } operation: {
            var data = homeData(account: "wallet", showsOnboarding: true)
            data.marketSections = [.init(id: "market", title: "Market", layout: .grid,
                tokens: [.init(id: "btc", token: .TONCOIN, change: "1%", isPositive: true)])]
            let controller = PerpsHomeVC(data: data) { _ in }
            controller.loadViewIfNeeded()
            controller.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
            controller.view.layoutIfNeeded()
            let collection = try #require(descendants(controller.view).compactMap { $0 as? UICollectionView }.first)
            let banner = try #require(collection.cellForItem(at: IndexPath(item: 0, section: 0)) as? PerpsOnboardingBannerCell)
            let divider = try #require(collection.layoutAttributesForItem(at: IndexPath(item: 0, section: 1)))
            #expect(banner.frame.minX == 16 && banner.frame.width == 370)
            #expect(banner.frame.height == 270)
            #expect(divider.frame.minY == banner.frame.maxY)
            #expect(divider.frame.height == 70)
            #expect(descendants(controller.view).allSatisfy { !($0 is PerpsPositionsSummaryCell) })
        }
    }

    @Test func bannerAndGlassButtonActivateOnceWithoutCompetingForTheSameTouch() throws {
        let cell = PerpsOnboardingBannerCell(frame: CGRect(x: 0, y: 0, width: 370, height: 270))
        cell.layoutIfNeeded()
        let button = try #require(descendants(cell).first { $0.accessibilityIdentifier == "perps.onboarding.open" } as? WInteractiveGlassButton)
        let title = try #require(button.titleLabel)
        let tap = try #require(cell.gestureRecognizers?.compactMap { $0 as? PerpsOnboardingPressGestureRecognizer }.first)
        var count = 0
        cell.onOpen = { count += 1 }
        #expect(cell.acceptsBannerTouch(on: cell.contentView))
        #expect(!cell.acceptsBannerTouch(on: button))
        #expect(!cell.acceptsBannerTouch(on: title))
        tap.beginTracking(at: CGPoint(x: 40, y: 40))
        tap.endTracking()
        tap.endTracking()
        #expect(count == 1)
        button.sendActions(for: .touchUpInside)
        #expect(count == 2)
    }

    @Test(arguments: ["scroll", "cancel", "reuse"])
    func cancelledBannerPressDoesNotOpenStories(_ reason: String) throws {
        let cell = PerpsOnboardingBannerCell(frame: CGRect(x: 0, y: 0, width: 370, height: 270))
        cell.layoutIfNeeded()
        let tap = try #require(cell.gestureRecognizers?.compactMap { $0 as? PerpsOnboardingPressGestureRecognizer }.first)
        var count = 0
        cell.onOpen = { count += 1 }
        tap.beginTracking(at: CGPoint(x: 40, y: 40))
        switch reason {
        case "scroll": tap.moveTracking(to: CGPoint(x: 40, y: 70))
        case "cancel": tap.cancelTracking()
        default: cell.prepareForReuse()
        }
        tap.endTracking()
        #expect(count == 0)
        #expect(cell.contentView.transform == .identity)
        #expect(CATransform3DIsIdentity(cell.layer.sublayerTransform))
    }

    @Test func bannerPressKeepsLayoutAndTouchCoordinatesStable() throws {
        let cell = PerpsOnboardingBannerCell(frame: CGRect(x: 0, y: 0, width: 370, height: 270))
        cell.layoutIfNeeded()
        let tap = try #require(cell.gestureRecognizers?.compactMap { $0 as? PerpsOnboardingPressGestureRecognizer }.first)
        let contentFrame = cell.contentView.frame
        let frames = cell.contentView.subviews.map(\.frame)
        tap.onPress?(true)
        cell.setNeedsLayout()
        cell.layoutIfNeeded()
        #expect(tap.view === cell)
        #expect(cell.contentView.transform == .identity)
        #expect(cell.contentView.frame == contentFrame)
        #expect(cell.contentView.subviews.map(\.frame) == frames)
        if TradeMotion.enabled {
            #expect(abs(cell.layer.sublayerTransform.m11 - 355 / 370) < 0.0001)
        }
        cell.prepareForReuse()
        #expect(CATransform3DIsIdentity(cell.layer.sublayerTransform))
        #expect(cell.layer.animationKeys()?.isEmpty != false)
    }

    @Test func pressedCollectionCardKeepsItsIllustrationGeometryThroughSnapshotAndReturn() async throws {
        try await withDependencies { $0.context = .live } operation: {
            let controller = PerpsHomeVC(data: homeData(account: "wallet", showsOnboarding: true)) { _ in }
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            window.rootViewController = controller
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            controller.view.layoutIfNeeded()
            let container = controller.view!
            let collection = try #require(descendants(container).compactMap { $0 as? UICollectionView }.first)
            let cell = try #require(collection.cellForItem(at: IndexPath(item: 0, section: 0)) as? PerpsOnboardingBannerCell)
            let illustration = try #require(descendants(cell).first { $0.accessibilityIdentifier == "perps.onboarding.illustration" })
            let originalBounds = cell.contentView.bounds
            let illustrationFrame = illustration.frame
            let illustrationInContainer = illustration.convert(illustration.bounds, to: container)
            let pressedWidth = originalBounds.width - 15
            let pressedScale = pressedWidth / originalBounds.width
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            cell.layer.sublayerTransform = CATransform3DMakeScale(pressedScale, pressedScale, 1)
            CATransaction.commit()
            try await Task.sleep(for: .milliseconds(50))

            let source = cell.presentationSource()
            let anchor = try #require(source.resolve(in: container))
            #expect(abs(anchor.frame.width - pressedWidth) < 0.0001)
            #expect(cell.contentView.transform == .identity)
            collection.collectionViewLayout.invalidateLayout()
            collection.setNeedsLayout()
            collection.layoutIfNeeded()
            let snapshot = try #require(source.makeSnapshot(anchor))
            #expect(cell.contentView.bounds == originalBounds)
            #expect(illustration.frame == illustrationFrame)
            #expect(snapshot.bounds.size == originalBounds.size)

            source.hide(anchor)
            #expect(cell.contentView.isHidden)
            #expect(CATransform3DIsIdentity(cell.layer.sublayerTransform))
            let returnAnchor = try #require(source.resolve(in: container))
            StoriesTransition.setSnapshotSize(container.bounds.size, on: snapshot)
            StoriesTransition.setSnapshotSize(returnAnchor.frame.size, on: snapshot)
            #expect(snapshot.bounds.size == originalBounds.size)
            #expect(snapshot.transform == .identity)
            source.restore()
            #expect(!cell.contentView.isHidden)
            #expect(illustration.convert(illustration.bounds, to: container) == illustrationInContainer)
        }
    }

    @Test func storiesHaveSevenLocalizedPagesAndOfflineArtwork() {
        let pages = PerpsOnboarding.pages()
        #expect(pages.map(\.id) == ["intro", "long", "short", "leverage", "liquidation", "funding", "finale"])
        #expect(pages.allSatisfy { $0.image != nil && $0.reducedMotionImage != nil && $0.videoURL == nil && $0.duration == 7 })
        #expect(pages.allSatisfy { !$0.title.isEmpty && !$0.body.isEmpty && !$0.title.hasPrefix("PerpsStory") })
        #expect(pages.dropLast().allSatisfy { $0.buttonTitle == nil })
        #expect(pages.last?.buttonTitle == lang("PerpsStoryViewMarkets"))
        #expect(pages.last?.body.contains("%app_name%") == false)
    }

    @Test func storiesMatchMediaByIdentityAndPreferCachedFiles() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { context in
            UIColor.magenta.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        }
        let imageData = try #require(image.pngData())
        let cache = PerpsStoryMediaCache(directory: directory, download: { _, _ in imageData })
        let intro = ApiPerpsOnboardingStory(id: "intro", url: URL(string: "https://example.com/intro.mp4")!,
            preview: URL(string: "https://example.com/intro.webp")!, duration: 8, bytes: 1)
        let unknown = ApiPerpsOnboardingStory(id: "unknown", url: URL(string: "https://example.com/unknown.mp4")!,
            preview: URL(string: "https://example.com/unknown.webp")!, duration: 1, bytes: 1)
        let onboarding = ApiPerpsOnboarding(stories: [unknown, intro])
        let uncached = PerpsOnboarding.pages(onboarding: onboarding, cache: cache)
        #expect(uncached.count == 7)
        #expect(uncached[0].videoURL == intro.url)
        #expect(uncached[0].duration == 8)
        #expect(uncached[1].videoURL == nil)
        #expect(uncached[1].image != nil)
        await cache.prefetch(onboarding.stories)
        let cached = PerpsOnboarding.pages(onboarding: onboarding, cache: cache)
        #expect(cached[0].videoURL == cache.cachedFile(for: intro.url))
        #expect(cached[0].image?.cgImage?.width == image.cgImage?.width)
        #expect(cached[0].reducedMotionImage != nil)
        try FileManager.default.removeItem(at: #require(cache.cachedFile(for: intro.url)))
        #expect(PerpsOnboarding.pages(onboarding: onboarding, cache: cache)[0].videoURL == intro.url)
    }

    private func emptySnapshot() throws -> ApiPerpsAccountSnapshot {
        try JSONDecoder().decode(ApiPerpsAccountSnapshot.self, from: Data("""
        {"positions":[],"totalEquity":"0","totalPnl":"0","timestamp":0,"unavailableDexs":[]}
        """.utf8))
    }

    private func client() -> PerpsClient {
        var client = PerpsClient()
        client.marketSnapshot = { .init(assets: [], assetsFetchedAt: 0) }
        client.positions = { _ in try emptySnapshot() }
        client.history = { _ in .init(fills: []) }
        return client
    }

    private func store(client: PerpsClient, directory: URL? = nil, operations: [ApiPerpsOperation] = []) -> PerpsStore {
        PerpsStore(client: client, cacheDirectory: directory, load: { operations }, save: { _ in },
            loadDismissedStatuses: { [] }, saveDismissedStatuses: { _ in })
    }

    private func homeData(account: String, showsOnboarding: Bool) -> PerpsHomeDisplayData {
        .init(positions: .init(accountID: account, totalValue: .fromDouble(0, .USD), profitLoss: .init("—"), positions: []),
            showsOnboarding: showsOnboarding)
    }

    private func descendants(_ view: UIView) -> [UIView] { view.subviews.flatMap { [$0] + descendants($0) } }
}
