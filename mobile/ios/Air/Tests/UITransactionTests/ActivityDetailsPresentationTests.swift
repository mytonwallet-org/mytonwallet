import Testing
import UIKit
import UIComponents
import WalletCore
import WalletContext
import WalletResources
@testable import UITransaction

@MainActor
@Suite(.serialized)
struct ActivityDetailsPresentationTests {
    init() {
        _ = WalletResourcesBundle.bundle.load()
    }

    @Test
    func `phone presentation clears inherited sizing before loading the content`() throws {
        guard #available(iOS 17.0, *) else { return }
        let (details, navigation) = try makeDetails()
        let presenter = TraitPresenter(width: .compact, height: .regular)
        navigation.preferredContentSize = CGSize(width: 640, height: 700)
        details.prepareForPresentation(from: presenter)
        #expect(!details.isViewLoaded)
        #expect(navigation.preferredContentSize == .zero)
        #expect(details.preferredContentSize == .zero)
        #expect(details.viewModel.detailsCollapseEnabled)
        #expect(!details.viewModel.detailsExpanded)
        #expect(details.viewModel.scrollingDisabled)
        #expect(navigation.sheetPresentationController?.selectedDetentIdentifier == nil)
    }

    @Test
    func `floating to compact to fullscreen and back restores controls and detents`() throws {
        guard #available(iOS 17.0, *) else { return }
        let (details, navigation) = try makeDetails()
        let presenter = TraitPresenter(width: .regular, height: .regular)
        let sheet = try #require(navigation.sheetPresentationController)
        details.prepareForPresentation(from: presenter)
        #expect(navigation.preferredContentSize.width == 580)
        #expect(navigation.preferredContentSize.height >= 720)
        #expect(!details.viewModel.detailsCollapseEnabled)
        #expect(details.viewModel.detailsExpanded)
        #expect(!details.viewModel.progressiveRevealEnabled)
        #expect(!details.viewModel.scrollingDisabled)
        #expect(!sheet.prefersGrabberVisible)
        #expect(sheet.detents.map(\.identifier) == [.large])
        details.viewModel.onDetailsExpanded()
        #expect(details.viewModel.detailsExpanded)

        details.viewModel.collapsedHeight = 300
        details.viewModel.expandedHeight = 550
        presenter.set(width: .compact, height: .regular)
        details.prepareForPresentation(from: presenter)
        #expect(navigation.preferredContentSize == .zero)
        #expect(details.viewModel.detailsCollapseEnabled)
        #expect(!details.viewModel.detailsExpanded)
        #expect(details.viewModel.progressiveRevealEnabled)
        #expect(details.viewModel.scrollingDisabled)
        #expect(sheet.detents.count == 3)
        #expect(sheet.selectedDetentIdentifier == .detailsCollapsed)
        details.viewModel.onDetailsExpanded()
        #expect(details.viewModel.detailsExpanded)
        #expect(sheet.selectedDetentIdentifier == .detailsExpanded)

        presenter.set(width: .regular, height: .compact)
        details.prepareForPresentation(from: presenter)
        #expect(navigation.preferredContentSize == .zero)
        #expect(!details.viewModel.detailsCollapseEnabled)
        #expect(details.viewModel.detailsExpanded)
        #expect(!details.viewModel.scrollingDisabled)
        #expect(sheet.detents.map(\.identifier) == [.large])

        presenter.set(width: .regular, height: .regular)
        details.prepareForPresentation(from: presenter)
        #expect(navigation.preferredContentSize.width == 580)
        #expect(navigation.preferredContentSize.height >= 720)
        #expect(!details.viewModel.detailsCollapseEnabled)
    }

    @Test
    func `details pushed from the activity list start expanded on phones`() throws {
        guard #available(iOS 17.0, *) else { return }
        let (details, _) = try makeDetails()
        let navigation = UINavigationController(rootViewController: UIViewController())
        navigation.setViewControllers([navigation.viewControllers[0], details], animated: false)
        details.prepareForPresentation(from: TraitPresenter(width: .compact, height: .regular))
        #expect(details.viewModel.detailsCollapseEnabled)
        #expect(details.viewModel.detailsExpanded)
        #expect(!details.viewModel.scrollingDisabled)
        #expect(navigation.sheetPresentationController?.selectedDetentIdentifier == .large)
    }

    @Test
    func `returning to the activity list restores its sheet after compact adaptation`() throws {
        guard #available(iOS 17.0, *) else { return }
        let account = MAccount(id: "sheet-test-mainnet", title: "Test", type: .view, byChain: [.ton: .init(address: "test")])
        let list = ActivityDetailsListVC(accountContext: AccountContext(source: .constant(account)), activities: [], context: .external)
        let (details, _) = try makeDetails()
        let navigation = UINavigationController(rootViewController: list)
        let presenter = TraitPresenter(width: .regular, height: .regular)
        list.prepareForPresentation(from: presenter)
        navigation.setViewControllers([list, details], animated: false)
        details.prepareForPresentation(from: presenter)
        let sheet = try #require(navigation.sheetPresentationController)
        sheet.delegate = details
        details.viewModel.collapsedHeight = 300
        details.viewModel.expandedHeight = 550

        presenter.set(width: .compact, height: .regular)
        details.prepareForPresentation(from: presenter)
        sheet.prefersGrabberVisible = true
        #expect(sheet.selectedDetentIdentifier == .detailsCollapsed)

        // Beginning a pop must preserve the detail configuration in case the user cancels it.
        list.viewWillAppear(true)
        #expect(sheet.selectedDetentIdentifier == .detailsCollapsed)
        #expect(sheet.delegate === details)
        #expect(sheet.prefersGrabberVisible)

        navigation.setViewControllers([list], animated: false)
        list.viewDidAppear(true)
        #expect(sheet.detents.map(\.identifier) == [.large])
        #expect(sheet.selectedDetentIdentifier == .large)
        #expect(sheet.delegate == nil)
        #expect(!sheet.prefersGrabberVisible)
        #expect(navigation.preferredContentSize == .zero)
    }

    @Test
    func `activity list uses the same floating size policy`() {
        guard #available(iOS 17.0, *) else { return }
        let account = MAccount(id: "sheet-test-mainnet", title: "Test", type: .view, byChain: [.ton: .init(address: "test")])
        let list = ActivityDetailsListVC(accountContext: AccountContext(source: .constant(account)), activities: [], context: .external)
        let navigation = UINavigationController(rootViewController: list)
        let presenter = TraitPresenter(width: .regular, height: .regular)
        list.prepareForPresentation(from: presenter)
        #expect(navigation.preferredContentSize.width == 580)
        #expect(navigation.preferredContentSize.height >= 720)
        presenter.set(width: .compact, height: .regular)
        list.prepareForPresentation(from: presenter)
        #expect(navigation.preferredContentSize == .zero)
    }


}

@available(iOS 17.0, *)
@MainActor
private final class TraitPresenter: UIViewController {
    init(width: UIUserInterfaceSizeClass, height: UIUserInterfaceSizeClass) {
        super.init(nibName: nil, bundle: nil)
        set(width: width, height: height)
    }

    required init?(coder: NSCoder) { fatalError() }

    func set(width: UIUserInterfaceSizeClass, height: UIUserInterfaceSizeClass) {
        traitOverrides.horizontalSizeClass = width
        traitOverrides.verticalSizeClass = height
    }
}

@MainActor
private func makeDetails() throws -> (ActivityDetailsVC, UINavigationController) {
    let account = MAccount(id: "sheet-test-mainnet", title: "Test", type: .view, byChain: [.ton: .init(address: "test")])
    let activity = try JSONDecoder().decode(ApiActivity.self, from: Data(#"{"kind":"swap","id":"sheet-test","timestamp":1893456000,"from":"toncoin","fromAmount":"12.5","to":"tether-usdt","toAmount":"37.42","networkFee":"0.05","swapFee":"0.1","status":"completed","transactionIds":{}}"#.utf8))
    let details = ActivityDetailsVC(activity: activity, accountSource: .constant(account), context: .normal)
    return (details, UINavigationController(rootViewController: details))
}
