import Dependencies
import SwiftUI
import UIKit
import XCTest
import UIComponents
@testable import UIReceive
import WalletCore
import WalletResources

@MainActor
final class ReceivePagingTests: XCTestCase {
    func testTokenWarningIncludesSourceTokenOnlyOnItsNetwork() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let account = MAccount(id: "0-mainnet", title: "Receive fixture", type: .view, byChain: [
            .ton: .init(address: "EQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAM9c"),
            .ethereum: .init(address: "0x0000000000000000000000000000000000000000"),
            .bitcoin: .init(address: "bc1qtabmenutest00000000000000000000000000000"),
        ])
        let tonWarning = "Send only GRAM or TON-based assets to this address. Sending other tokens will result in loss."
        let cases: [(ApiChain, String?, String)] = [
            (.ton, ApiToken.MYCOIN.slug, "Send only GRAM, MY, or other TON-based assets to this address. Sending other tokens will result in loss."),
            (.ton, ApiToken.TON_USDT.slug, "Send only GRAM, USD₮, or other TON-based assets to this address. Sending other tokens will result in loss."),
            (.ton, ApiToken.TONCOIN.slug, tonWarning),
            (.ton, nil, tonWarning),
            (.ton, "unknown-token", tonWarning),
            (.ton, ApiToken.ETH.slug, tonWarning),
            (.ethereum, ApiToken.MYCOIN.slug, "Send only ETH or Ethereum-based assets to this address. Sending other tokens will result in loss."),
            (.bitcoin, ApiToken.MYCOIN.slug, "Send only BTC to this address. Sending other tokens will result in loss."),
        ]
        try await withDependencies {
            $0.context = .preview
            $0.accountStore = .makePreview(accounts: [account], selectedAccountId: account.id)
        } operation: {
            for (chain, tokenSlug, expectedWarning) in cases {
                let receive = ReceiveVC(accountContext: AccountContext(accountId: account.id), chain: chain, buyingToken: tokenSlug)
                let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
                window.rootViewController = UINavigationController(rootViewController: receive)
                window.makeKeyAndVisible()
                defer { window.isHidden = true }
                window.layoutIfNeeded()
                let pager = try XCTUnwrap(receive.children.compactMap { $0 as? WPagerViewController }.first)
                let page = try XCTUnwrap(pager.children.compactMap { $0 as? ReceiveTableVC }.first { $0.chain == chain })
                for _ in 0..<40 where findTokenWarning(in: page.view) == nil {
                    try await Task.sleep(for: .milliseconds(25))
                }
                XCTAssertEqual(findTokenWarning(in: page.view), expectedWarning, "\(chain): \(tokenSlug ?? "none")")
            }
        }
    }

    func testFundTabSelectionSkipsIntermediatePagesAndHeaderNetworksInBothDirections() async throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "This checks direct page transitions in motion")
        _ = WalletResourcesBundle.bundle.load()
        let account = MAccount(
            id: "0-mainnet", title: "Paging fixture", type: .view,
            byChain: [
                .bitcoin: .init(address: "bc1qtabmenutest00000000000000000000000000000"),
                .ethereum: .init(address: "0x0000000000000000000000000000000000000000"),
                .base: .init(address: "0x0000000000000000000000000000000000000000"),
                .arc: .init(address: "0x0000000000000000000000000000000000000000"),
                .solana: .init(address: "11111111111111111111111111111111"),
            ]
        )
        for isRtl in [false, true] {
            try await withDependencies {
                $0.context = .preview
                $0.accountStore = .makePreview(accounts: [account], selectedAccountId: account.id)
            } operation: {
                let receive = ReceiveVC(accountContext: AccountContext(accountId: account.id), chain: .bitcoin)
                let navigation = UINavigationController(rootViewController: receive)
                navigation.view.semanticContentAttribute = isRtl ? .forceRightToLeft : .forceLeftToRight
                if #available(iOS 17, *) {
                    navigation.traitOverrides.layoutDirection = isRtl ? .rightToLeft : .leftToRight
                }
                let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
                window.rootViewController = navigation
                window.makeKeyAndVisible()
                defer { window.isHidden = true }
                window.layoutIfNeeded()
                let pager = try XCTUnwrap(receive.children.compactMap { $0 as? WPagerViewController }.first)
                let header = try XCTUnwrap(receive.children.compactMap { $0 as? UIHostingController<ReceiveHeaderView> }.first)
                header.view.layoutIfNeeded()
                let preparedQrCodeViews = findQrCodeViews(in: header.view)
                let transition = try XCTUnwrap(header.rootView.transition)
                let control = try XCTUnwrap(findControl(in: receive.navigationItem.titleView))
                let items = control.model.items
                XCTAssertGreaterThan(items.count, 2)
                XCTAssertEqual(preparedQrCodeViews.count, items.count, "The initial header must prepare every network's QR code")
                for _ in 0..<200 where pager.children.count < items.count {
                    try await Task.sleep(for: .milliseconds(25))
                }
                XCTAssertEqual(pager.children.count, items.count, "Idle Fund must prepare the network pages before selection")
                XCTAssertTrue(pager.children.allSatisfy { $0.isViewLoaded })
                let first = pager.selectedIndex
                let last = items.count - 1
                XCTAssertGreaterThan(last - first, 1)
                let endpoints = Set([items[first].id, items[last].id])
                for target in [last, first] {
                    control.model.onSelect(items[target])
                    XCTAssertEqual(pager.selectedIndex, target)
                    var movingFrames = 0
                    for _ in 0..<28 {
                        try await Task.sleep(for: .milliseconds(25))
                        XCTAssertEqual(
                            Set(findQrCodeViews(in: header.view).map(ObjectIdentifier.init)),
                            Set(preparedQrCodeViews.map(ObjectIdentifier.init)),
                            "Switching unchanged addresses must reuse the prepared QR views throughout the transition"
                        )
                        let selection = try XCTUnwrap(transition.selection)
                        XCTAssertTrue(endpoints.contains(selection.source))
                        XCTAssertTrue(endpoints.contains(selection.destination))
                        if selection.source != selection.destination { movingFrames += 1 }
                        let rendered = pager.children
                            .filter { $0.viewIfLoaded?.superview?.isHidden == false }
                            .compactMap { ($0 as? ReceiveTableVC)?.chain.rawValue }
                        XCTAssertTrue(Set(rendered).isSubset(of: endpoints))
                    }
                    XCTAssertGreaterThan(movingFrames, 0)
                    XCTAssertEqual(transition.selection?.source, items[target].id)
                    XCTAssertEqual(transition.selection?.destination, items[target].id)
                    XCTAssertEqual(control.model.selectedItem?.id, items[target].id)
                    XCTAssertEqual(pager.children.filter { $0.viewIfLoaded?.superview?.isHidden == false }.count, 1)
                }
            }
        }
    }

    func testAccountChangeCancelsPagingAndPreservesOnlyAvailableNetworks() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let first = MAccount(id: "0-mainnet", title: "First", type: .view, byChain: [
            .bitcoin: .init(address: "bc1qtabmenutest00000000000000000000000000000"),
            .ethereum: .init(address: "0x0000000000000000000000000000000000000000"),
            .arc: .init(address: "0x0000000000000000000000000000000000000000"),
        ])
        let second = MAccount(id: "1-mainnet", title: "Second", type: .view, byChain: [
            .ethereum: .init(address: "0x0000000000000000000000000000000000000001"),
            .arc: .init(address: "0x0000000000000000000000000000000000000001"),
        ])
        let third = MAccount(id: "2-mainnet", title: "Third", type: .view, byChain: [
            .ton: .init(address: "EQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAM9c"),
        ])
        try await withDependencies {
            $0.context = .preview
            $0.accountStore = .makePreview(accounts: [first, second, third], selectedAccountId: first.id)
        } operation: {
            let receive = ReceiveVC(accountContext: AccountContext(accountId: first.id), chain: .bitcoin)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            window.rootViewController = UINavigationController(rootViewController: receive)
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            window.layoutIfNeeded()
            let header = try XCTUnwrap(receive.children.compactMap { $0 as? UIHostingController<ReceiveHeaderView> }.first)
            let control = try XCTUnwrap(findControl(in: receive.navigationItem.titleView))
            let touchOverlay = UIView(frame: CGRect(x: 0, y: 0, width: 402, height: 360))
            receive.view.addSubview(touchOverlay)
            let target = try XCTUnwrap(control.model.items.last)
            XCTAssertTrue(second.supports(chain: ApiChain(rawValue: target.id)))
            control.model.onSelect(target)

            for (accountId, expectedId) in [(second.id, target.id), (third.id, "ton")] {
                let oldPager = try XCTUnwrap(receive.children.compactMap { $0 as? WPagerViewController }.first)
                header.rootView.accountContext.accountId = accountId
                for _ in 0..<40 where oldPager.parent != nil {
                    try await Task.sleep(for: .milliseconds(25))
                }
                XCTAssertNil(oldPager.parent)
                let newPager = try XCTUnwrap(receive.children.compactMap { $0 as? WPagerViewController }.first)
                XCTAssertFalse(newPager === oldPager)
                XCTAssertTrue(receive.view.subviews.last === touchOverlay)
                XCTAssertEqual(control.model.selectedItem?.id, expectedId)
                XCTAssertEqual(header.rootView.transition?.selection?.source, expectedId)
                XCTAssertEqual(header.rootView.transition?.selection?.destination, expectedId)
                try await Task.sleep(for: .milliseconds(400))
                XCTAssertEqual(control.model.selectedItem?.id, expectedId)
                XCTAssertEqual(header.rootView.transition?.selection?.source, expectedId)
            }
            XCTAssertEqual(control.model.items.map(\.id), ["ton"])
            XCTAssertTrue(control.isHidden)
        }
    }

    private func findTokenWarning(in view: UIView) -> String? {
        if let cell = view as? UICollectionViewCell, cell.accessibilityIdentifier == "receive_token_warning" {
            return (cell.contentConfiguration as? UIListContentConfiguration)?.text
        }
        return view.subviews.lazy.compactMap { self.findTokenWarning(in: $0) }.first
    }

    private func findControl(in view: UIView?) -> WSegmentedControl? {
        guard let view else { return nil }
        if let control = view as? WSegmentedControl { return control }
        return view.subviews.lazy.compactMap { self.findControl(in: $0) }.first
    }

    private func findQrCodeViews(in view: UIView) -> [QRCodeContainerView] {
        let current = (view as? QRCodeContainerView).map { [$0] } ?? []
        return current + view.subviews.flatMap { findQrCodeViews(in: $0) }
    }
}
