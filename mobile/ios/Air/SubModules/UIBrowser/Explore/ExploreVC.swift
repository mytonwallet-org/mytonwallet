import Combine
import SwiftUI
import UIComponents
import WalletContext
import WalletCore

public final class ExploreVC: WViewController {
    // MARK: Public properties / Dependencies

    let exploreVM: ExploreVM = .init()
    var onSelectAny: () -> () = {}

    // MARK: - Private

    private let viewOutput = ViewOutput()
    private let externalEvents = ExternalEvents()
    private let observedViewState = ObservedViewState()

    private var trimmedSearchString: String = "" // Improvement: move searchBar to this screen

    private var cancelBag = Set<AnyCancellable>()

    public init() {
        super.init(nibName: nil, bundle: nil)
        exploreVM.delegate = self

        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard let self = self else { return }
            if !isViewLoaded { // preload
                exploreVM.loadExploreSites() // Improvement: viewDidLoad can happen just after this moment
                // if data is already in loading state, no need to call loadExploreSites()
            }
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: Overriden

    public override func viewDidLoad() {
        super.viewDidLoad()

        let titleFixingScrollView = initialSetup()
        bind(titleFixingScrollView: titleFixingScrollView)

        exploreVM.refresh()
    }

    public override func scrollToTop(animated _: Bool) {
        observedViewState.scrollToTop()
    }

    // MARK: - Initial Setup

    private func initialSetup() -> NavBarTitleFixingScrollView? {
        let titleFixingScrollView: NavBarTitleFixingScrollView? = if #available(iOS 26.0, *) {
            nil
        } else {
            configured(object: NavBarTitleFixingScrollView()) {
                $0.showsVerticalScrollIndicator = false
                $0.contentInsetAdjustmentBehavior = .never
                $0.alpha = 0
                let fakeContent = UIView()
                $0.addStretchedToBounds(subview: fakeContent)
                NSLayoutConstraint.activate([
                    fakeContent.widthAnchor.constraint(equalTo: $0.widthAnchor),
                    fakeContent.heightAnchor.constraint(equalToConstant: 1),
                ])
                view.addStretchedToBounds(subview: $0) // must be added first
            }
        }

        let rootView = ScreenView(viewState: observedViewState, viewOutput: viewOutput)
        let hostingController = UIHostingController(rootView: rootView)
        hostingController.view.backgroundColor = .clear
        hostingController.view.insetsLayoutMarginsFromSafeArea = false

        view.addStretchedToBounds(subview: hostingController.view)
        addChild(hostingController)
        hostingController.didMove(toParent: self)

        return titleFixingScrollView
    }

    private func bind(titleFixingScrollView: NavBarTitleFixingScrollView?) {
        bindViewOutput(titleFixingScrollView: titleFixingScrollView)

        externalEvents.searchStringDidChange
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .removeDuplicates()
            .debounce(for: .seconds(0.2), scheduler: DispatchQueue.main)
            .sink(withUnretained: self) { uSelf, searchText in
                uSelf.trimmedSearchString = searchText
                uSelf.updateViewState()
            }.store(in: &cancelBag)
    }

    private func bindViewOutput(titleFixingScrollView: NavBarTitleFixingScrollView?) {
        cancelBag.formUnion([
            viewOutput.connectedDappDidTap.sink { [exploreVM] connectedDappURL in
                if let connected = exploreVM.connectedDapps[connectedDappURL], let url = URL(string: connected.url) {
                    AppActions.openInBrowser(url, title: connected.name, injectDappConnect: true)
                } else {
                    Log.shared.error("Data is inconsistent for connectedDappURL \(connectedDappURL)")
                }
            },

            viewOutput.connectedDappSettingsDidTap.sink {
                AppActions.showConnectedDapps(push: false)
            },

            viewOutput.trendingDappDidTap
                .merge(with: viewOutput.dappFromFolderDidTap, viewOutput.searchResultDappDidTap)
                .sink(withUnretained: self) { uSelf, apiSite in
                    uSelf.view.window?.endEditing(true)
                    uSelf.onSelectAny()
                    if uSelf.exploreVM.exploreSites[apiSite.url] == nil {
                        Log.shared.error("inconsistency between UI and data ")
                    }
                    guard let url = URL(string: apiSite.url) else {
                        return Log.shared.error("URL from string failed: \(apiSite.url)")
                    }

                    if apiSite.shouldOpenExternally {
                        UIApplication.shared.open(url)
                    } else {
                        AppActions.openInBrowser(url, title: apiSite.name, injectDappConnect: true)
                    }
                },

            viewOutput.dappCategoryDidTap.sink(withUnretained: self) { uSelf, categoryId in
                let exploreVC = ExploreCategoryVC(exploreVM: uSelf.exploreVM, categoryId: categoryId)
                uSelf.navigationController?.pushViewController(exploreVC, animated: true)
            },
        ])

        if let titleFixingScrollView {
            viewOutput.scrollOffsetDidChange.sink { [titleFixingScrollView] scrollOffset in
                titleFixingScrollView.swiftuiDidUpdate(verticalOffset: scrollOffset)
            }.store(in: &cancelBag)
        }
    }

    private func updateViewState() {
        let (sections, shouldShowWhiteBackground) =
            Self.makeViewStateSnapshot(exploreVM: exploreVM,
                                       shouldRestrictSites: ConfigStore.shared.shouldRestrictSites,
                                       trimmedSearchString: trimmedSearchString)
        observedViewState.update(sections: sections, shouldShowWhiteBackground: shouldShowWhiteBackground)
    }
}

// MARK: - External Events

extension ExploreVC {
    func searchTextDidChange(_ searchString: String) { externalEvents.searchStringDidChange.send(searchString) }
}

extension ExploreVC: ExploreVMDelegate {
    func didUpdateViewModelData() { updateViewState() }
}

extension ExploreVC {
    /// Events from parent / child screens
    private struct ExternalEvents {
        let searchStringDidChange = PassthroughSubject<String, Never>()
    }
}

import OrderedCollections

/// SwiftUI’s ScrollView doesn't trigger the navigation bar's title resizing behavior based on the scroll offset.
/// So use UIKit-based UIScrollView to mirror SwiftUI scroll position to signalize scroll offset to UIKit.
/// By tracking the last few scroll offsets and checking the scroll direction (ascending or descending), it ensures the
/// navigation bar's title resizes correctly in sync with the scroll, even during slow scrolling.
@available(iOS, deprecated: 26.0, message: "SwiftUI scroll is observed correctly in iOS 26")
fileprivate final class NavBarTitleFixingScrollView: UIScrollView {
    private var offsets: OrderedSet<CGFloat> = [0] // in iOS 16 equal values can appear, OrderedSet keep offsets unique
    private var assumedTitleSize: LayoutSizeVariant = .regular

    func swiftuiDidUpdate(verticalOffset scrollOffset: CGFloat) {
        if #unavailable(iOS 26.0) {
            guard offsets.append(scrollOffset).inserted else { return }
            if offsets.count > 4 { offsets.removeFirst() }

            switch checkOrder(offsets) {
            case .ascending:
                if scrollOffset > 15 {
                    contentOffset.y = scrollOffset
                    if assumedTitleSize == .regular {
                        assumedTitleSize = .compact // we really don't know whether it become large or not, this is logical flag
                    }
                }

            case .descending:
                if scrollOffset < 0 {
                    // negative offset is important for navBar title work correct
                    contentOffset.y = scrollOffset
                }
                if scrollOffset < 5, assumedTitleSize == .compact {
                    assumedTitleSize = .regular
                    contentOffset.y = scrollOffset
                }

            case .unordered: break
            }
        }
    }

    private enum SequenceOrder {
        case ascending
        case descending
        case unordered
    }

    private func checkOrder<T: Comparable & Hashable>(_ offset: OrderedSet<T>) -> SequenceOrder {
        guard offset.count > 1 else { return .unordered }

        var order: SequenceOrder = .unordered
        for i in 1 ..< offset.count {
            if offset[i] > offset[i - 1] {
                if order == .unordered {
                    order = .ascending // Found the first ascending pair
                } else if order == .descending {
                    return .unordered // Was descending, now ascending, so unordered
                }
            } else if offset[i] < offset[i - 1] {
                if order == .unordered {
                    order = .descending // Found the first descending pair
                } else if order == .ascending {
                    return .unordered // Was ascending, now descending, so unordered
                }
            }
        }
        return order
    }
}
