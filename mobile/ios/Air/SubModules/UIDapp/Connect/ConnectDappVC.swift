//
//  ConnectDappVC.swift
//  UIDapp
//
//  Created by Sina on 8/13/24.
//

import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext
import Dependencies

public class ConnectDappVC: WViewController, UISheetPresentationControllerDelegate {
    
    var viewModel: ConnectViewModel
    var hostingController: UIHostingController<ConnectDappViewOrPlaceholder>?
    private var contentHeight: CGFloat = 0
    
    private var currentSheetPresentationController: UISheetPresentationController? {
        navigationController?.sheetPresentationController ?? sheetPresentationController
    }
    
    public init(
        request: ApiUpdate.DappConnect,
        onCancel: @escaping () -> ()
    ) {
        self.viewModel = ConnectViewModel(accountId: request.accountId, update: request, onCancel: onCancel)
        super.init(nibName: nil, bundle: nil)
    }
    
    init(placeholderAccountId: String?) {
        @Dependency(\.accountStore.currentAccountId) var currentAccountId
        self.viewModel = ConnectViewModel(accountId: placeholderAccountId ?? currentAccountId, update: nil, onCancel: nil)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func replacePlaceholder(
        request: ApiUpdate.DappConnect,
        onCancel: @escaping () -> ()
    ) {
        viewModel.accountContext.accountId = request.accountId
        withAnimation(.smooth(duration: 0.3)) {
            self.viewModel.update = request
        }
        self.viewModel.onCancel = onCancel
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        viewModel.presenter = self
        setupViews()
    }
    
    private func setupViews() {

        addCloseNavigationItemIfNeeded()
        // Route the close "X" through cancellation so the dapp is notified (otherwise it waits forever).
        if navigationItem.rightBarButtonItem != nil {
            navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in
                self?.closeTapped()
            })
        }
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        navigationItem.standardAppearance = appearance

        configureSheetWithOpaqueBackground(color: .air.sheetBackground)
        currentSheetPresentationController?.delegate = self

        let hostingController = addHostingController(makeView(), constraints: .fill)
        self.hostingController = hostingController
        hostingController.sizingOptions = .preferredContentSize
    }
    
    private func makeView() -> ConnectDappViewOrPlaceholder {
        ConnectDappViewOrPlaceholder(viewModel: viewModel, onHeightChange: { [weak self] height in
            self?.onHeightChange(height)
        })
    }
    
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateSheetHeight(animated: false)
    }

    public override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        viewModel.extraBottomPadding = max(0, 16 - view.safeAreaInsets.bottom)
    }
    
    private func onHeightChange(_ height: CGFloat) {
        guard height > 0 else { return }
        guard abs(contentHeight - height) > 0.5 else { return }
        contentHeight = height
        updateSheetHeight(animated: true)
    }
    
    private func updateSheetHeight(animated: Bool) {
        guard contentHeight > 0, let sheet = currentSheetPresentationController else { return }
        let contentHeight = self.contentHeight
        
        let apply = {
            sheet.detents = [
                .custom(identifier: .content) { context in
                    min(contentHeight, context.maximumDetentValue)
                }
            ]
            sheet.selectedDetentIdentifier = .content
        }
        
        if animated {
            sheet.animateChanges {
                apply()
            }
        } else {
            apply()
        }
    }
    
    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        if !viewModel.didConfirm {
            viewModel.onCancel?()
        }
    }

    private func closeTapped() {
        if !viewModel.didConfirm {
            viewModel.onCancel?()
        }
        dismiss(animated: true)
    }
}

private extension UISheetPresentationController.Detent.Identifier {
    static let content = UISheetPresentationController.Detent.Identifier("content")
}

#if DEBUG
@available(iOS 26, *)
#Preview {
//    let vc = ConnectDappVC(placeholderAccountId: "0-maiinet")
    let vc = ConnectDappVC(request: .sample, onCancel: {})
    previewSheet(vc)
}
#endif
