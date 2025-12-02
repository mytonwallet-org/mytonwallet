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
import Ledger
import Dependencies

public class ConnectDappVC: WViewController, UISheetPresentationControllerDelegate {
    
    var viewModel: ConnectViewModel
    var hostingController: UIHostingController<ConnectDappViewOrPlaceholder>?
    
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
        sheetPresentationController?.delegate = self

        let hostingController = addHostingController(makeView(), constraints: .fill)
        self.hostingController = hostingController
        hostingController.sizingOptions = .preferredContentSize        
    }
    
    private func makeView() -> ConnectDappViewOrPlaceholder {
        ConnectDappViewOrPlaceholder(viewModel: viewModel)
    }
    
    public override func preferredContentSizeDidChange(forChildContentContainer container: any UIContentContainer) {
        if let sheet = sheetPresentationController {
            sheet.animateChanges {
                sheet.detents = [
                    .custom { context in
                        container.preferredContentSize.height
                    }
                ]
            }
        }
    }
    
    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        if !viewModel.didConfirm {
            viewModel.onCancel?()
        }
    }
}

#if DEBUG
@available(iOS 26, *)
#Preview {
//    let vc = ConnectDappVC(placeholderAccountId: "0-maiinet")
    let vc = ConnectDappVC(request: .sample, onConfirm: { _, _ in }, onCancel: {})
    sheetPreview(vc)
}
#endif
