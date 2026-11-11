import SwiftUI
import Testing
import UIKit
import UIComponents
import WalletCore
import WalletResources
@testable import UIToken

@Suite(.serialized) @MainActor
struct PerpsReceiptPresentationTests {
    init() { _ = WalletResourcesBundle.bundle.load() }

    @Test func phoneConfiguresCompactSheetBeforeLoadingOrPresentation() throws {
        guard #available(iOS 17.0, *) else { return }
        let (receipt, navigation) = makeReceipt()
        navigation.preferredContentSize = CGSize(width: 640, height: 700)
        receipt.prepareForPresentation(from: ReceiptTraitPresenter(width: .compact, height: .regular))
        let sheet = try #require(navigation.sheetPresentationController)
        #expect(!receipt.isViewLoaded)
        #expect(navigation.presentingViewController == nil)
        #expect(navigation.preferredContentSize == .zero)
        #expect(sheet.detents.map(\.identifier) == [.init("perpsReceipt"), .large])
        #expect(sheet.selectedDetentIdentifier == .init("perpsReceipt"))
        #expect(sheet.prefersGrabberVisible)
        #expect(sheet.delegate === receipt)
        // The unmeasured 264-point summary sits below the 44-point bar and the 8-point content inset.
        let compact = try #require(sheet.detents.first)
        let summaryBottom: CGFloat = 264 + 44 + 8
        #expect(compact.resolvedValue(in: DetentContext(maximumDetentValue: 1_000)) == summaryBottom)
        #expect(compact.resolvedValue(in: DetentContext(maximumDetentValue: 200)) == 200)
    }

    @Test func adaptingRestoresCompactSizeWithoutCollapsingExpandedDetailsOnRepeatedSetup() throws {
        guard #available(iOS 17.0, *) else { return }
        let (receipt, navigation) = makeReceipt()
        let presenter = ReceiptTraitPresenter(width: .regular, height: .regular)
        receipt.prepareForPresentation(from: presenter)
        let sheet = try #require(navigation.sheetPresentationController)
        #expect(navigation.preferredContentSize.width == 580)
        #expect(navigation.preferredContentSize.height >= 720)
        #expect(sheet.detents.map(\.identifier) == [.large])
        #expect(!sheet.prefersGrabberVisible)

        presenter.traitOverrides.horizontalSizeClass = .compact
        receipt.prepareForPresentation(from: presenter)
        #expect(navigation.preferredContentSize == .zero)
        #expect(sheet.selectedDetentIdentifier == .init("perpsReceipt"))
        sheet.selectedDetentIdentifier = .large
        receipt.sheetPresentationControllerDidChangeSelectedDetentIdentifier(sheet)
        receipt.prepareForPresentation(from: presenter)
        #expect(sheet.selectedDetentIdentifier == .large)
        #expect(!sheet.prefersGrabberVisible)

        presenter.traitOverrides.verticalSizeClass = .compact
        receipt.prepareForPresentation(from: presenter)
        #expect(sheet.detents.map(\.identifier) == [.large])
        presenter.traitOverrides.verticalSizeClass = .regular
        receipt.prepareForPresentation(from: presenter)
        #expect(sheet.selectedDetentIdentifier == .init("perpsReceipt"))
        #expect(sheet.prefersGrabberVisible)
    }

    @Test func confirmationMorphKeepsTheSameSheetAndReceiptUpdatesInPlace() async throws {
        guard #available(iOS 17.0, *) else { return }
        let presenter = ReceiptTraitPresenter(width: .compact, height: .regular)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let navigation = UINavigationController()
        navigation.setViewControllers([UIViewController(), UIViewController()], animated: false)
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        navigation.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let sheet = try #require(navigation.sheetPresentationController)
        let receipt = PerpsPositionReceiptVC(data: makeReceipt().0.data, onShare: {})
        var data = receipt.data
        data.status = .submitted
        data.isEstimated = true
        receipt.update(data: data)
        let replacement = ContentReplaceAnimationCoordinator()
        let replaced = await replacement.replaceNavigationStack(with: receipt, in: navigation,
            targetViewControllers: [receipt], animateAlongside: {
                receipt.prepareForPresentation(from: presenter)
                receipt.animateToCollapsed()
            })
        #expect(replaced)
        #expect(navigation.sheetPresentationController === sheet)
        #expect(navigation.viewControllers.count == 1)
        #expect(navigation.topViewController === receipt)
        #expect(sheet.selectedDetentIdentifier == .init("perpsReceipt"))
        #expect(receipt.data.status == .submitted)
        #expect(receipt.data.title == receipt.data.event.title)
        let share = try #require(descendants(receipt.view).compactMap { $0 as? WScalableButton }
            .first { $0.accessibilityIdentifier == "perps.receipt.share" })
        #expect(!share.isHidden)
        data.status = .completed
        data.isEstimated = false
        data.margin = .fromDouble(99.8, .USD)
        receipt.update(data: data)
        try await Task.sleep(for: .milliseconds(100))
        #expect(receipt.data.margin == .fromDouble(99.8, .USD))
        #expect(!share.isHidden)
        #expect(descendants(receipt.view).first { $0.accessibilityIdentifier == "perps.receipt.share" } === share)
        #expect(sheet.selectedDetentIdentifier == .init("perpsReceipt"))
        #expect(navigation.topViewController === receipt)
    }

    private func descendants(_ view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap(descendants)
    }

    @Test func hideUnavailableClosedReceiptRows() async throws {
        func render(hasDetails: Bool) async throws -> CGFloat {
            let outcome = PerpsPositionOutcome(invested: hasDetails ? "$10.85" : "—",
                closingValue: hasDetails ? "$9.51" : "—", entryPrice: "$80 578", exitPrice: "$79 848",
                profitLoss: .init("−$0.23", tone: .negative),
                closingValueAmount: hasDetails ? .fromDouble(9.51, .USD) : nil)
            var data = PerpsPositionReceiptDisplayData(token: .ETH, direction: .long, leverage: 0,
                margin: .fromDouble(-0.23, .USD), timestamp: 1_792_866_000_000, positionSize: "$21.54",
                price: "$79 848", liquidationPrice: nil, paymentAmount: hasDetails ? "9.51 USDC" : "—",
                fee: "0.03 USDC", event: .closed(outcome))
            data.feeRows = [.init(id: "exchange", title: "Exchange Fee", value: "0.03 USDC"),
                            .init(id: "bridge", title: "Bridge Fee", value: hasDetails ? "0.2 USDC" : "—")]
            let presentation = PerpsPositionReceiptPresentation(data: data)
            presentation.detailsExpanded = true
            let controller = UIHostingController(rootView: PerpsPositionReceiptView(presentation: presentation,
                onDetails: {}, onShare: nil, onHeightChange: { _ in }).padding(16))
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 1100))
            window.rootViewController = controller
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            let height = controller.sizeThatFits(in: CGSize(width: 402, height: CGFloat.greatestFiniteMagnitude)).height
            controller.view.frame = CGRect(x: 0, y: 0, width: 402, height: height)
            controller.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { context in
                controller.view.layer.render(in: context.cgContext)
            }
            Attachment.record(try #require(image.pngData()), named: hasDetails ? "receipt-complete.png" : "receipt-missing.png")
            return height
        }
        let completeHeight = try await render(hasDetails: true)
        let missingHeight = try await render(hasDetails: false)
        #expect(completeHeight - missingHeight > 80)
    }

    private func makeReceipt() -> (PerpsPositionReceiptVC, UINavigationController) {
        let receipt = PerpsPositionReceiptVC(data: .init(token: .ETH, direction: .long, leverage: 5,
            margin: .fromDouble(100, .USD), timestamp: 1_792_866_000_000, positionSize: "$500", price: "$2 000",
            liquidationPrice: "$1 600", paymentAmount: "100 USDC", fee: "$0.05"))
        return (receipt, UINavigationController(rootViewController: receipt))
    }
}

@available(iOS 17.0, *)
@MainActor
private final class ReceiptTraitPresenter: UIViewController {
    init(width: UIUserInterfaceSizeClass, height: UIUserInterfaceSizeClass) {
        super.init(nibName: nil, bundle: nil)
        traitOverrides.horizontalSizeClass = width
        traitOverrides.verticalSizeClass = height
    }
    @available(*, unavailable) required init?(coder: NSCoder) { nil }
}

@MainActor
private final class DetentContext: NSObject, UISheetPresentationControllerDetentResolutionContext {
    let containerTraitCollection = UITraitCollection()
    let maximumDetentValue: CGFloat

    init(maximumDetentValue: CGFloat) {
        self.maximumDetentValue = maximumDetentValue
    }
}
