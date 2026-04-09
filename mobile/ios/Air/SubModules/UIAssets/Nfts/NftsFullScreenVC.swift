import UIKit
import WalletCore
import WalletContext
import UIComponents

private let log = Log("NftsFullScreenVC")

/// Stand-alone NftsVC wrapped with a view controller to be displayed in full-screen (collection view, as of now)
public class NftsFullScreenVC: WViewController {
    private let nftsVC: NftsVC
    private let filter: NftCollectionFilter
    private let nftsVCManager: NftsVCManager
    
    public init(accountSource: AccountSource, filter: NftCollectionFilter) {
        self.filter = filter
        self.nftsVCManager = NftsVCManager(tabsViewModel: WalletAssetsViewModel(accountSource: accountSource))
        self.nftsVC = .init(
            accountSource: accountSource,
            manager: nftsVCManager,
            layoutMode: .regular,
            canOpenCollection: false,
            filter: filter
        )
        
        super.init(nibName: nil, bundle: nil)
        
        addChild(nftsVC)
        nftsVC.didMove(toParent: self)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        nftsVC.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(nftsVC.view)
        NSLayoutConstraint.activate([
            nftsVC.view.topAnchor.constraint(equalTo: view.topAnchor),
            nftsVC.view.leftAnchor.constraint(equalTo: view.leftAnchor),
            nftsVC.view.rightAnchor.constraint(equalTo: view.rightAnchor),
            nftsVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        nftsVCManager.editingNavigator.onStateChange = { [weak self] _, _ in
            self?.updateState()
        }
        
        updateState()
    }
    
    private func updateState() {
        updateNavigationItem()
        
        let navigator = nftsVCManager.editingNavigator
        let state = navigator.state
        if state.editingState == .selection {
            navigator.installToolbar(into: view)
        }
        
        navigationController?.allowBackSwipeToDismiss(state.editingState == nil)
        navigationController?.isModalInPresentation = state.editingState != nil
    }
    
    private enum NavItemState: Equatable {
        case reordering
        case selection
        case normal(isFavorited: Bool, isTonNetwork: Bool, collectionItemCount: Int)
    }
    
    private var previousNavItemState: NavItemState?
    
    private func updateNavigationItem() {
        title = nftsVC.title
        
        // The function is called frequently (on every nftsVC.updateNfts() call). This may cause an issue with an open context menu:
        // if an update arrives while the menu is open, it gets recreated and visually closes.
        // Therefore, we check whether the state has actually changed.
        var navItemState: NavItemState
        do {
            let vcState = nftsVCManager.editingNavigator.state
            switch vcState.editingState {
            case .reordering:
                navItemState = .reordering
            case .selection:
                navItemState = .selection
            case nil:
                let isFavorited = nftsVCManager.isFavorited(filter: filter)
                var isTonNetwork = false 
                if case .collection(let collection) = filter, collection.chain == .ton {
                    isTonNetwork = true
                }
                navItemState = .normal(
                    isFavorited: isFavorited,
                    isTonNetwork: isTonNetwork,
                    collectionItemCount: nftsVCManager.state.itemCount
                )
            }
            guard previousNavItemState != navItemState else { return }
            previousNavItemState = navItemState
        }
                
        var leadingItemGroups: [UIBarButtonItemGroup] = []
        var trailingItemGroups: [UIBarButtonItemGroup] = []
        
        let navigator = nftsVCManager.editingNavigator
        switch navItemState {
        case .reordering:
            leadingItemGroups += navigator.cancelEditingBarButtonItem.asSingleItemGroup()
            trailingItemGroups += navigator.commitEditingBarButtonItem.asSingleItemGroup()
        case .selection:
            leadingItemGroups += navigator.selectAllBarButtonItem.asSingleItemGroup()
            trailingItemGroups += navigator.commitEditingBarButtonItem.asSingleItemGroup()
        case let .normal(isFavorited, isTonNetwork, collectionItemCount):
            var items: [UIBarButtonItem] = []
            items += UIBarButtonItem(image: UIImage(systemName: isFavorited ? "pin.slash" : "pin"),
                                     primaryAction: UIAction { [weak self] _ in self?.onFavorite() })
            if isTonNetwork || collectionItemCount > 0 {
                items += UIBarButtonItem(
                    image: UIImage(systemName: "ellipsis"),
                    menu: makeTopMenu(collectionItemCount: collectionItemCount)
                )
            }
            if !items.isEmpty {
                trailingItemGroups +=  UIBarButtonItemGroup(barButtonItems: items, representativeItem: nil)
            }
        }
        
        navigationItem.leadingItemGroups = leadingItemGroups
        navigationItem.trailingItemGroups = trailingItemGroups
    }
    
    private func onFavorite() {
        if filter != .none {
            let manager = self.nftsVCManager
            Task { @MainActor in
                do {
                    let newIsFavorited = !manager.isFavorited(filter: filter)
                    try await manager.setIsFavorited(filter: filter, isFavorited: newIsFavorited)
                    
                    if newIsFavorited {
                        Haptics.play(.success)
                    } else {
                        Haptics.play(.lightTap)
                    }
                    
                } catch {
                    log.error("failed to favorite collection: \(error)")
                }
            }
        }
    }
    
    private func makeTopMenu(collectionItemCount: Int) -> UIMenu {
        let openInSection: UIMenu
        do {
            var items: [UIMenuElement] = []
            
            if case .collection(let collection) = filter {
                if collection.chain == .ton {
                    if let url = ExplorerHelper.getgemsNftCollectionUrl(collectionAddress: collection.address) {
                        items += UIAction(title: "Getgems", image: .airBundle("MenuGetgems26")) { _ in AppActions.openInBrowser(url) }
                    }
                    if let url = ExplorerHelper.tonscanNftCollectionUrl(collectionAddress: collection.address) {
                        items += UIAction(
                            title: ExplorerHelper.selectedExplorerName(for: collection.chain),
                            image: .airBundle(ExplorerHelper.selectedExplorerMenuIconName(for: collection.chain))
                        ) { _ in AppActions.openInBrowser(url) }
                    }
                }
            }
            openInSection = UIMenu(title: "", options: .displayInline, children: items)
        }
        
        let otherSection: UIMenu
        do {
            var items: [UIMenuElement] = []
            if collectionItemCount > 1 {
                items += UIAction(title: lang("Reorder"), image: .airBundle("MenuReorder26")) { [weak self] _ in
                    self?.nftsVCManager.startReordering()
                }
            }
            if collectionItemCount > 0 {
                items += UIAction(title: lang("Select"), image: .airBundle("MenuSelect26")) { [weak self] _ in
                    guard let self else { return }
                    self.nftsVCManager.startSelection(in: nftsVC)
                }
            }
            otherSection = UIMenu(title: "", options: .displayInline, children: items)
        }
        
        let sections = [openInSection, otherSection].filter { !$0.children.isEmpty }
        return UIMenu(title: "", children: sections)
    }
}
