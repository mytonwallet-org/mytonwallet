import UIKit
import WalletContext
import WalletCore

@MainActor
public class NftsEditingNavigator {
    
    private weak var manager: NftsVCManager?
    private var selectionToolbar: NftMultiSelectToolbar?
    private var selectionToolbarHiddenConstraint: NSLayoutConstraint?
    private var selectionToolbarVisibleConstraint: NSLayoutConstraint?

    internal init(manager: NftsVCManager) {
        self.manager = manager
    }
    
    deinit {
        if let toolBar = selectionToolbar {
            Task { @MainActor in
                toolBar.removeFromSuperview()
            }
        }
    }
    
    public var state: NftsVCManager.State { manager?.state ?? .empty }
    public var onStateChange: ((NftsVCManager.State, NftsVCManager.State) -> Void)?
    
    public func installToolbar(into hosterView: UIView) {
        // just in case: we change a hoster: uninstall the toolbar first
        if let selectionToolbar, selectionToolbar.superview != hosterView {
            hideToolbar()
        }
        
        // Skip existing
        if selectionToolbar != nil {
            return
        }
        
        // Create a new toolbar in hidden state
        let toolbar = NftMultiSelectToolbar()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        hosterView.addSubview(toolbar)
        selectionToolbarHiddenConstraint = toolbar.topAnchor.constraint(equalTo: hosterView.bottomAnchor, constant: 10)
        selectionToolbarVisibleConstraint = toolbar.bottomAnchor.constraint(equalTo: hosterView.safeAreaLayoutGuide.bottomAnchor, constant: -10)
        NSLayoutConstraint.activate([
            selectionToolbarHiddenConstraint!,
            toolbar.leadingAnchor.constraint(equalTo: hosterView.safeAreaLayoutGuide.leadingAnchor, constant: 32),
            toolbar.trailingAnchor.constraint(equalTo: hosterView.safeAreaLayoutGuide.trailingAnchor, constant: -32),
        ])
        toolbar.delegate = self
        selectionToolbar = toolbar
        updateToolbar()
        hosterView.layoutIfNeeded()
        
        // Appear the toolbar with animation
        selectionToolbarHiddenConstraint?.isActive = false
        selectionToolbarVisibleConstraint?.isActive = true
        UIView.animate(
            withDuration: 0.55,
            delay: 0,
            usingSpringWithDamping: 0.68,
            initialSpringVelocity: 0.35,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            hosterView.layoutIfNeeded()
        }
    }
    
    private func hideToolbar() {
        guard let toolbar = selectionToolbar else { return }
            
        selectionToolbarVisibleConstraint?.isActive = false
        selectionToolbarHiddenConstraint?.isActive = true
        selectionToolbar = nil
        selectionToolbarHiddenConstraint = nil
        selectionToolbarVisibleConstraint = nil
        if let hosterView = toolbar.superview {
            UIView.animate(withDuration: 0.35, delay: 0, options: [.curveEaseInOut], animations: {
                hosterView.layoutIfNeeded()
            }, completion: { _ in
                toolbar.removeFromSuperview()
            })
        }
    }
        
    private func updateToolbar() {
        guard let selectionToolbar, let state = manager?.state else { return }
        
        let hasSelection = state.selectedItemCount > 0
        
        if state.canSendSelection {
            selectionToolbar.sendButton.isEnabled = hasSelection
            selectionToolbar.sendButton.isHidden = false
        } else {
            selectionToolbar.sendButton.isHidden = true
        }

        if state.canBurnSelection {
            selectionToolbar.burnButton.isEnabled = hasSelection
            selectionToolbar.burnButton.isHidden = false
        } else {
            selectionToolbar.burnButton.isHidden = true
        }

        selectionToolbar.hideButton.isEnabled = hasSelection
    }
    
    internal func notifyStateChange(_ oldState: NftsVCManager.State, _ newState: NftsVCManager.State) {
        if newState.editingState != .selection {
            hideToolbar()
        } else {
            updateToolbar()
        }
        
        onStateChange?(oldState, newState)
    }
    
    public func cancelEditing() {
        manager?.stopEditing(isCanceled: true)
    }
    
    public lazy var cancelEditingBarButtonItem = UIBarButtonItem.cancelTextButtonItem { [weak self] in
        self?.cancelEditing()
    }
    
    public lazy var commitEditingBarButtonItem = UIBarButtonItem.doneButtonItem { [weak self] in
        self?.manager?.stopEditing(isCanceled: false)
    }

    public lazy var selectAllBarButtonItem = UIBarButtonItem.textButtonItem(text: lang("Select All")) { [weak self] in
        self?.manager?.toggleSelectAll()
    }
}

extension NftsEditingNavigator: NftMultiSelectToolbarDelegate {
    func multiSelectToolbarDidDelectHideAction() { manager?.hideSelected() }
    func multiSelectToolbarDidDelectBurnAction() { manager?.burnSelected() }
    func multiSelectToolbarDidDelectSendAction() {  manager?.sendSelected() }
}
