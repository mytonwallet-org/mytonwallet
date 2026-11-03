import GRDB
import SwiftUI
import Testing
import UIKit
@testable import UIToken
@testable import WalletCore
import WalletResources

@MainActor
@Suite("Token Info Layout", .serialized, .settingsStoreIsolation)
struct TokenInfoLayoutTests {
    @Test(arguments: [1, 3, 4])
    func `description toggle only occupies space when more than three lines are needed`(lines: Int) async throws {
        try await withMarketDescription(Array(repeating: "A token description.", count: lines).joined(separator: "\n")) { cell, model, window in
            let expectedHeight = CGFloat(42 + min(lines, 3) * 22 + (lines > 3 ? 22 : 0))
            #expect(abs((cell.height ?? 0) - expectedHeight) < 1)
            if lines > 3 {
                model.requestToggle()
                try await Task.sleep(for: .milliseconds(650))
                window.layoutIfNeeded()
                #expect(abs((cell.height ?? 0) - CGFloat(42 + lines * 22 + 22)) < 1)
                model.requestToggle()
                try await Task.sleep(for: .milliseconds(650))
                #expect(abs((cell.height ?? 0) - expectedHeight) < 1)
            }
        }
    }

    @Test
    func `description toggle follows width and content changes`() async throws {
        try await withMarketDescription("A token description that fits in a few lines on a wide screen and wraps onto more lines on a narrow screen.") { cell, model, window in
            #expect((cell.height ?? 0) <= 109)
            cell.frame.size.width = 180
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
            #expect(abs((cell.height ?? 0) - 130) < 1)
            cell.frame.size.width = 500
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
            #expect((cell.height ?? 0) <= 109)
            model.configure(state: .details(ApiTokenDetails(
                description: "Short description.", links: nil, marketCap: nil, circulatingSupply: nil,
                totalSupply: nil, createdAt: nil, volume24h: nil
            )))
            cell.modelStateDidChange()
            try await Task.sleep(for: .milliseconds(650))
            #expect(abs((cell.height ?? 0) - 64) < 1)
        }
    }

    private func withMarketDescription(_ text: String, body: (TokenInfoCell, TokenInfoModel, UIWindow) async throws -> Void) async throws {
        _ = WalletResourcesBundle.bundle.load()
        let model = TokenInfoModel(state: .details(ApiTokenDetails(
            description: text, links: nil, marketCap: nil, circulatingSupply: nil,
            totalSupply: nil, createdAt: nil, volume24h: nil
        )), hasBalance: false)
        let cell = TokenInfoCell(frame: CGRect(x: 16, y: 100, width: 370, height: 64))
        let controller = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 550, height: 874))
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        controller.view.addSubview(cell)
        cell.configure(model: model, onHeightChange: { [weak cell] in
            guard let cell else { return }
            cell.frame.size.height = cell.height ?? 0
            cell.layoutIfNeeded()
        }, onUserToggleAnimationChange: { _ in })
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        try await body(cell, model, window)
    }

    @Test
    func `market info matches the Figma component dimensions`() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let db = try DatabaseQueue()
        try makeMigrator().migrate(db)
        SettingsStore.liveValue.use(db: db)
        defer { SettingsStore.liveValue.clean() }
        let links = try JSONDecoder().decode([ApiTokenDetails.Link].self, from: Data("""
        [
            {"kind":"website","title":"Website","url":"https://bitcoin.org"},
            {"kind":"x","title":"X","url":"https://x.com/bitcoin"},
            {"kind":"telegram","title":"Telegram","url":"https://t.me/bitcoin"},
            {"kind":"aggregator","title":"CoinMarketCap","url":"https://coinmarketcap.com/currencies/bitcoin/"}
        ]
        """.utf8))
        let volume = try JSONDecoder().decode(ApiTokenDetails.Volume.self, from: Data("""
        {"total":4030000,"buy":2440000,"sell":1580000,"change":0.8946,"currency":"USD"}
        """.utf8))
        let details = ApiTokenDetails(
            description: "Bitcoin is the first cryptocurrency, created\u{2028}in 2009 by the pseudonymous Satoshi Nakamoto. It runs on its own network, without banks or intermediaries. Its supply is capped at 21 million coins — no one can issue more. Bitcoin is the largest crypto asset by market value and is more often held as a store of value than used for payments.",
            links: links, marketCap: 7_580_000_000, circulatingSupply: 5_120_000_000,
            totalSupply: 5_120_000_000, createdAt: Date(timeIntervalSince1970: 1_573_776_000), volume24h: volume
        )
        let model = TokenInfoModel(state: .details(details), isExpanded: false, hasBalance: false)
        let cell = TokenInfoCell(frame: CGRect(x: 16, y: 100, width: 370, height: 413))
        let controller = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        controller.view.addSubview(cell)
        cell.configure(model: model, onHeightChange: { [weak cell] in
            guard let cell else { return }
            cell.frame.size.height = cell.height ?? 0
            cell.layoutIfNeeded()
        }, onUserToggleAnimationChange: { _ in })
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        #expect(abs((cell.height ?? 0) - 413) < 2)
        func record(_ name: String) {
            let image = UIGraphicsImageRenderer(bounds: cell.bounds).image { context in
                cell.layer.render(in: context.cgContext)
            }
            if let data = image.pngData() { Attachment.record(data, named: name) }
        }
        record("token-info-figma-comparison.png")
        model.requestToggle()
        try await Task.sleep(for: .milliseconds(650))
        #expect(abs((cell.height ?? 0) - 523) < 2)
        record("token-info-figma-full-comparison.png")
        model.configure(state: .details(details), hasBalance: true)
        cell.modelStateDidChange()
        try await Task.sleep(for: .milliseconds(650))
        #expect(cell.height == 64)
        model.requestToggle()
        try await Task.sleep(for: .milliseconds(650))
        #expect(abs((cell.height ?? 0) - 501) < 2)
        record("token-info-figma-owned-comparison.png")
    }

    @Test
    func `market description expands and ownership collapses the same info cell`() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let db = try DatabaseQueue()
        try makeMigrator().migrate(db)
        SettingsStore.liveValue.use(db: db)
        defer { SettingsStore.liveValue.clean() }
        let details = ApiTokenDetails(
            description: String(repeating: "Bitcoin is a cryptocurrency with a fixed supply. ", count: 12),
            links: nil, marketCap: 7_580_000_000, circulatingSupply: 19_000_000,
            totalSupply: 21_000_000, createdAt: nil, volume24h: nil
        )
        let model = TokenInfoModel(state: .details(details), isExpanded: false, hasBalance: false)
        let cell = TokenInfoCell(frame: CGRect(x: 16, y: 100, width: 370, height: 64))
        let controller = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        controller.view.addSubview(cell)
        let updateHeight = { [weak cell] in
            guard let cell else { return }
            cell.frame.size.height = cell.height ?? 0
            cell.layoutIfNeeded()
        }
        cell.configure(model: model, onHeightChange: updateHeight, onUserToggleAnimationChange: { _ in })
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        let compactHeight = try #require(cell.height)
        #expect(compactHeight > 200)
        #expect(compactHeight < 350)

        func record(_ name: String) {
            let image = UIGraphicsImageRenderer(bounds: cell.bounds).image { context in
                cell.layer.render(in: context.cgContext)
            }
            if let data = image.pngData() { Attachment.record(data, named: name) }
        }
        record("token-market-info.png")
        model.requestToggle()
        try await Task.sleep(for: .milliseconds(650))
        window.layoutIfNeeded()
        let fullHeight = try #require(cell.height)
        #expect(fullHeight > compactHeight + 100)
        #expect(abs(fullHeight - model.measuredExpandedHeight) < 1)
        record("token-market-info-full.png")

        model.requestToggle()
        try await Task.sleep(for: .milliseconds(650))
        #expect(abs((cell.height ?? 0) - compactHeight) < 1)

        model.configure(state: .details(details), hasBalance: true)
        cell.modelStateDidChange()
        try await Task.sleep(for: .milliseconds(650))
        #expect(cell.height == TokenInfoModel.collapsedHeight)
        #expect(!model.isExpanded)
        record("token-owned-info.png")

        model.requestToggle()
        try await Task.sleep(for: .milliseconds(650))
        #expect(model.isExpanded)
        #expect((cell.height ?? 0) > compactHeight)
        record("token-owned-info-full.png")
    }

    @Test(arguments: [true, false], [true, false])
    func `expanded cell fills its collection view allocation`(hasBalance: Bool, loadsAsynchronously: Bool) async throws {
        _ = WalletResourcesBundle.bundle.load()
        let volume = try JSONDecoder().decode(ApiTokenDetails.Volume.self, from: Data("""
        {"total":4030000,"buy":2440000,"sell":1580000,"change":0.8946,"currency":"USD"}
        """.utf8))
        let details = ApiTokenDetails(
            description: String(repeating: "A long token description. ", count: 30),
            links: nil,
            marketCap: 7_580_000_000,
            circulatingSupply: 19_000_000,
            totalSupply: 21_000_000,
            createdAt: Date(timeIntervalSince1970: 1_573_776_000),
            volume24h: volume
        )
        let model = TokenInfoModel(
            state: loadsAsynchronously ? .loading : .details(details),
            isExpanded: true,
            hasBalance: hasBalance
        )
        let layout = UICollectionViewCompositionalLayout { section, _ in
            let size = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: section == 0 ? .absolute(354) : .estimated(300)
            )
            return NSCollectionLayoutSection(group: .vertical(
                layoutSize: size,
                subitems: [NSCollectionLayoutItem(layoutSize: size)]
            ))
        }
        let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), collectionViewLayout: layout)
        let controller = UIViewController()
        let navigation = UINavigationController(rootViewController: controller)
        let window = UIWindow(frame: collection.bounds)
        window.rootViewController = navigation
        window.isHidden = false
        defer { window.isHidden = true }
        controller.view.addSubview(collection)
        let header = UICollectionView.CellRegistration<UICollectionViewCell, Int> { _, _, _ in }
        let info = UICollectionView.CellRegistration<TokenInfoCell, Int> { [weak collection] cell, indexPath, _ in
            cell.configure(model: model, onHeightChange: { [weak collection] in
                guard let collection else { return }
                let context = UICollectionViewLayoutInvalidationContext()
                context.invalidateItems(at: [indexPath])
                collection.collectionViewLayout.invalidateLayout(with: context)
                collection.layoutIfNeeded()
            }, onUserToggleAnimationChange: { _ in })
        }
        let source = UICollectionViewDiffableDataSource<Int, Int>(collectionView: collection) { collection, indexPath, item in
            if item == 0 {
                return collection.dequeueConfiguredReusableCell(using: header, for: indexPath, item: item)
            }
            return collection.dequeueConfiguredReusableCell(using: info, for: indexPath, item: item)
        }
        var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
        snapshot.appendSections([0, 1])
        snapshot.appendItems([0], toSection: 0)
        snapshot.appendItems([1], toSection: 1)
        await source.apply(snapshot, animatingDifferences: false)
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        let cell = try #require(collection.cellForItem(at: IndexPath(item: 0, section: 1)) as? TokenInfoCell)
        if loadsAsynchronously {
            #expect(cell.height == TokenInfoModel.collapsedHeight)
            model.configure(state: .details(details))
            cell.modelStateDidChange()
            try await Task.sleep(for: .milliseconds(650))
            window.layoutIfNeeded()
        }
        let clippingView = try #require(cell.contentView.subviews.first)
        #expect(model.measuredExpandedHeight > 350)
        #expect(abs((cell.height ?? 0) - model.measuredExpandedHeight) < 1)
        #expect(abs(cell.bounds.height - model.measuredExpandedHeight) < 1)
        #expect(abs(cell.contentView.bounds.height - cell.bounds.height) < 1)
        #expect(abs(clippingView.bounds.height - cell.bounds.height) < 1)

        navigation.pushViewController(UIViewController(), animated: false)
        window.layoutIfNeeded()
        navigation.popViewController(animated: false)
        collection.contentOffset.y = 354
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        #expect(abs(clippingView.bounds.height - cell.bounds.height) < 1)
    }

    @Test
    func `reconfiguring during crossfade keeps the measured hosting height`() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let model = TokenInfoModel(state: .loading, isExpanded: true)
        let cell = TokenInfoCell(frame: CGRect(x: 0, y: 100, width: 390, height: TokenInfoModel.collapsedHeight))
        let controller = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        controller.view.addSubview(cell)

        let updateHeight = { [weak cell] in
            guard let cell else { return }
            cell.frame.size.height = cell.height ?? 0
            cell.layoutIfNeeded()
        }
        cell.configure(model: model, onHeightChange: updateHeight, onUserToggleAnimationChange: { _ in })
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        model.configure(state: .details(ApiTokenDetails(
            description: String(repeating: "A long token description. ", count: 30),
            links: nil,
            marketCap: nil,
            circulatingSupply: nil,
            totalSupply: nil,
            createdAt: nil,
            volume24h: nil
        )))
        cell.modelStateDidChange()

        for _ in 0..<100 {
            window.layoutIfNeeded()
            if model.pendingPresentationRevision == nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.pendingPresentationRevision == nil)
        #expect(model.presentationOverlay != nil)
        #expect(model.measuredExpandedHeight > TokenInfoModel.collapsedHeight)
        cell.configure(model: model, onHeightChange: updateHeight, onUserToggleAnimationChange: { _ in })
        updateHeight()
        try await Task.sleep(for: .milliseconds(300))
        window.layoutIfNeeded()

        let host = try #require(cell.contentView.subviews.first?.subviews.first)
        #expect(abs(host.bounds.height - model.measuredExpandedHeight) < 1)
        #expect(abs(cell.bounds.height - model.measuredExpandedHeight) < 1)
    }

    @Test(arguments: [true, false])
    func `content stays at the top when the host and content heights differ`(isExpanded: Bool) async throws {
        _ = WalletResourcesBundle.bundle.load()
        let model = TokenInfoModel(state: .loading, isExpanded: isExpanded)
        var contentHeight = CGFloat.zero
        var contentFrame: CGRect?
        let hostingView = UIHostingConfiguration {
            TokenInfoView(model: model) { height, _ in
                contentHeight = height
            }
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) {
                contentFrame = $0
            }
        }
        .margins(.all, 0)
        .makeContentView()

        let controller = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        hostingView.frame = CGRect(x: 16, y: 100, width: 358, height: TokenInfoModel.collapsedHeight)
        controller.view.addSubview(hostingView)
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let initialFrame = try #require(contentFrame)
        #expect(abs(contentHeight - TokenInfoModel.collapsedHeight) < 1)

        let details = ApiTokenDetails(
            description: String(repeating: "A long token description. ", count: 30),
            links: nil,
            marketCap: 7_580_000_000,
            circulatingSupply: nil,
            totalSupply: nil,
            createdAt: nil,
            volume24h: nil
        )
        model.configure(state: .details(details))
        hostingView.setNeedsLayout()
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))

        #expect(contentHeight > TokenInfoModel.collapsedHeight)
        let frame = try #require(contentFrame)
        #expect(abs(frame.minY - initialFrame.minY) < 1)

        model.updateMeasuredExpandedHeight(contentHeight)
        model.beginPresentationTransition(revision: model.layoutRevision, animated: false)
        model.setExpansionProgress(model.targetExpansionProgress)
        hostingView.frame.size.height = contentHeight
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))

        // During a shrinking transition the outgoing layer is taller than the new host.
        model.configure(state: .error)
        hostingView.frame.size.height = TokenInfoModel.collapsedHeight
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))

        #expect(abs(contentHeight - TokenInfoModel.collapsedHeight) < 1)
        let shrinkingFrame = try #require(contentFrame)
        #expect(abs(shrinkingFrame.minY - initialFrame.minY) < 1)
    }
}
