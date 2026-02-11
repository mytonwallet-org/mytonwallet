//
//  ConnectDappVC.swift
//  UIDapp
//
//  Created by Sina on 8/13/24.
//

import SwiftUI
import UIKit
import UIPasscode
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
        onConfirm: @escaping (_ accountId: String, _ password: String) -> (),
        onCancel: @escaping () -> ()
    ) {
        self.viewModel = ConnectViewModel(accountId: request.accountId, update: request, onConfirm: onConfirm, onCancel: onCancel)
        super.init(nibName: nil, bundle: nil)
    }
    
    init(placeholderAccountId: String?) {
        @Dependency(\.accountStore.currentAccountId) var currentAccountId
        self.viewModel = ConnectViewModel(accountId: placeholderAccountId ?? currentAccountId, update: nil, onConfirm: nil, onCancel: nil)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func replacePlaceholder(
        request: ApiUpdate.DappConnect,
        onConfirm: @escaping (_ accountId: String, _ password: String) -> (),
        onCancel: @escaping () -> ()
    ) {
        withAnimation(.smooth(duration: 0.2)) {
            self.viewModel.update = request
        }
        self.viewModel.onConfirm = onConfirm
        self.viewModel.onCancel = onCancel
    }
    
    public override var hideNavigationBar: Bool { false }

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
    }
    
    private func setupViews() {
        
        addCloseNavigationItemIfNeeded()
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        navigationItem.standardAppearance = appearance

        configureSheetWithOpaqueBackground(color: WTheme.sheetBackground)
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
}

private extension UISheetPresentationController.Detent.Identifier {
    static let content = UISheetPresentationController.Detent.Identifier("content")
}

#if DEBUG
@available(iOS 26, *)
#Preview {
//    let vc = ConnectDappVC(placeholderAccountId: "0-maiinet")
    let vc = ConnectDappVC(request: .sample, onConfirm: { _, _ in }, onCancel: {})
    previewSheet(vc)
}
#endif
