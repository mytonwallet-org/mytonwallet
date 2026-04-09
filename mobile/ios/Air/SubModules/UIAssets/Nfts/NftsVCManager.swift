import UIKit
import WalletContext
import WalletCore

@MainActor
public class NftsVCManager {
    private let tabsViewModel: WalletAssetsViewModel
    private var viewControllers = NSHashTable<NftsVC>.weakObjects()
    private var updateCounter = 0
    private var isUpdating: Bool = false
    private var selectionTargetVC: NftsVC? { viewControllers.allObjects.first(where: \.inSelectionMode) }

    public lazy var editingNavigator = NftsEditingNavigator(manager: self)
    public var restoreTabsOnReorderCanceling = false
    public var onStateChange: ((State, State) -> Void)?
    
    private(set) var state = State.empty

    public init(tabsViewModel: WalletAssetsViewModel) {
        self.tabsViewModel = tabsViewModel
    }
    
    func isFavorited(filter: NftCollectionFilter) -> Bool {
        tabsViewModel.isFavorited(filter: filter)
    }
    
    func setIsFavorited(filter: NftCollectionFilter, isFavorited: Bool) async throws {
        beginUpdate()
        defer { endUpdate() }
        
        _ = try? await tabsViewModel.setIsFavorited(filter: filter, isFavorited: isFavorited)
        
        // Temporary fix until the WalletAssetsViewModel refactoring. Wait a little until all changes went through write/read/observe DB
        try? await Task.sleep(nanoseconds: 200_000_000)
    }
    
    func startSelection(in viewController: NftsVC) {
        beginUpdate()
        defer { endUpdate() }

        if let editingState = state.editingState {
            if editingState == .selection {
                return
            }
            stopEditing(isCanceled: true)
        }

        guard viewControllers.allObjects.contains(viewController) else {
            assertionFailure()
            return
        }

        viewControllers.allObjects.forEach {
            if $0 === viewController {
                $0.startSelection()
            } else {
                $0.stopSelection()
            }
        }
    }
    
    func startReordering() {
        beginUpdate()
        defer { endUpdate() }
        
        if let editingState = state.editingState {
            if editingState == .reordering {
                return
            }
            stopEditing(isCanceled: true)
        }

        tabsViewModel.startOrdering()
        for vc in viewControllers.allObjects {
            vc.loadViewIfNeeded()
            vc.startReordering()
        }
    }
    
    public func stopEditing(isCanceled: Bool) {
        guard let editingState = state.editingState else {
            return
        }
        
        beginUpdate()
        defer { endUpdate() }
        
        switch editingState {
        case .reordering:
            tabsViewModel.stopReordering(isCanceled: isCanceled, restoreTabsOnCancel: restoreTabsOnReorderCanceling)
            for vc in viewControllers.allObjects {
                vc.stopReordering(isCanceled: isCanceled, )
            }
        case .selection:
            viewControllers.allObjects.forEach { $0.stopSelection() }
        }
    }

    public func toggleSelectAll() {
        guard state.editingState == .selection else {
            assertionFailure()
            return
        }

        beginUpdate()
        defer { endUpdate() }
        
        selectionTargetVC?.toggleSelectAllNfts()
    }
     
    func beginUpdate() {
        updateCounter += 1
    }
    
    func endUpdate() {
        guard updateCounter > 0 else {
            updateCounter = 0
            assertionFailure()
            return
        }
        updateCounter -= 1
        guard updateCounter == 0 else { return }

        guard !isUpdating else {
            assertionFailure("Recursive update(). Check the code")
            return
        }
        isUpdating = true
        defer { isUpdating = false }
        
        var vcStates: [ObjectIdentifier: State.VCState] = [:]
        var inSelection = false
        var selectedItemCount = 0
        var canBurnSelection = false
        var canSendSelection = false
        
        for vc in viewControllers.allObjects {
            if vc.inSelectionMode {
                inSelection = true
                if let nfts = vc.collectMultiSelectedNfts() {
                    selectedItemCount = nfts.count
                }
                canBurnSelection = vc.$account.account.supportsBurn
                canSendSelection = vc.$account.account.supportsSend
            }
            
            vcStates[ObjectIdentifier(vc)] = State.VCState(
                itemCount: vc.allShownNftsCount,
                isFavorited: isFavorited(filter: vc.filter),
                height: vc.isViewLoaded ? vc.calculateHeight(isHosted: false) : 0,
                heightHosted: vc.isViewLoaded ? vc.calculateHeight(isHosted: true) : 0,
            )
        }
        
        let newState = State(
            editingState: tabsViewModel.isReordering ? .reordering : (inSelection ? .selection : nil),
            selectedItemCount: selectedItemCount,
            canSendSelection: canSendSelection,
            canBurnSelection: canBurnSelection,
            controllerStates: vcStates
        )
        
        if newState != self.state {
            let oldState = self.state
            self.state = newState
            onStateChange?(oldState, newState)
            editingNavigator.notifyStateChange(oldState, newState)
        }
        
        // Auto-cancel editing if no items are in the single view controller
        if state.itemCount == 0, state.controllerStates.count == 1, state.editingState != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.stopEditing(isCanceled: false)
            }
        }
    }

    internal func addController(_ vc: NftsVC) {
        viewControllers.add(vc)
        notifyStateChange()
    }

    internal func notifyStateChange() {
        beginUpdate()
        endUpdate()
    }
    
    private func canSendOrBurnItems(nfts: [ApiNft]) -> Bool {
        guard !nfts.isEmpty else {
            assertionFailure()
            return false
        }
        
        // Single chain only
        let chains = Set(nfts.map(\.chain))
        if chains.count > 1 {
            AppActions.showToast(message: lang("$nft_batch_different_chains"))
            return false
        }
        
        // No onSale
        let hasOnSale = nfts.contains(where: \.isOnSale)
        if hasOnSale {
            AppActions.showToast(message: lang("$nft_batch_on_sale"))
            return false
        }
        
        return true
    }
    
    internal func burnSelected() {
        guard let vc = selectionTargetVC, let nfts = vc.collectMultiSelectedNfts() else {
            assertionFailure()
            return
        }
        guard canSendOrBurnItems(nfts: nfts) else {
            return
        }
        
        AppActions.showSend(accountContext: vc.$account, prefilledValues: .init(mode: .burnNft, nfts: nfts))
        stopEditing(isCanceled: false)
    }

    internal func sendSelected() {
        guard let vc = selectionTargetVC, let nfts = vc.collectMultiSelectedNfts() else {
            assertionFailure()
            return
        }
        guard canSendOrBurnItems(nfts: nfts) else {
            return
        }
        
        AppActions.showSend(accountContext: vc.$account, prefilledValues: .init(mode: .sendNft, nfts: nfts))
        stopEditing(isCanceled: false)
    }
    
    internal func hideSelected() {
        guard let vc = selectionTargetVC, let nfts = vc.collectMultiSelectedNfts() else {
            assertionFailure()
            return
        }
        NftStore.setHiddenByUser(accountId: vc.$account.account.id, nftIds: nfts.map { $0.id }, isHidden: true)
    }
}

extension NftsVCManager {
    public enum EditingState { case reordering, selection }
    
    public struct State: Equatable {
        static var empty: State {
            .init(
                editingState: nil,
                selectedItemCount: 0,
                canSendSelection: false,
                canBurnSelection: false,
                controllerStates: [:]
            )
        }
        
        public let editingState: EditingState?
        public let selectedItemCount: Int
        public let canSendSelection: Bool
        public let canBurnSelection: Bool
        
        var itemCount: Int {
            var result = 0
            for (_, info) in self.controllerStates {
                result += info.itemCount
            }
            return result
        }
                
        func heightChanged(since oldState: State) -> Bool {
            guard controllerStates.count == oldState.controllerStates.count else {
                return true
            }
            for (_, (lhs, rhs)) in zip(controllerStates.indices, zip(oldState.controllerStates.values, self.controllerStates.values)) {
                if lhs.heightHosted != rhs.heightHosted || lhs.height != rhs.height {
                    return true
                }
            }
            return false
        }
        
        // internal usage only, just as a signature of changes
        fileprivate struct VCState: Equatable {
            var itemCount: Int
            var isFavorited: Bool
            var height: CGFloat
            var heightHosted: CGFloat
        }
        fileprivate let controllerStates: [ObjectIdentifier: VCState]
    }
}

