//
//  SentVC.swift
//  UISend
//
//  Created by Sina on 5/9/24.
//

import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext

class SentVC: WViewController {
    
    var model: SendModel
    var transferOptions: Api.SubmitTransferOptions?
    
    init(model: SendModel, transferOptions: Api.SubmitTransferOptions?) {
        self.model = model
        self.transferOptions = transferOptions
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func loadView() {
        super.loadView()
        setupViews()
    }

    private func setupViews() {

        let title = lang("Sent")
        addNavigationBar(title: title, closeIcon: true)

        // top view
        let hostingController = UIHostingController(rootView: SentView(model: model, transferOptions: transferOptions))
        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: navigationBarAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hostingController.didMove(toParent: self)
        hostingController.view.backgroundColor = .clear
        view.backgroundColor = WTheme.sheetBackground

        // view my wallet button
        let viewWalletButton = WButton(style: .primary)
        viewWalletButton.translatesAutoresizingMaskIntoConstraints = false
        viewWalletButton.setTitle(lang("Done"), for: .normal)
        viewWalletButton.addTarget(self, action: #selector(viewWalletPressed), for: .touchUpInside)
        view.addSubview(viewWalletButton)
        NSLayoutConstraint.activate([
            viewWalletButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            viewWalletButton.leftAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leftAnchor, constant: 16),
            viewWalletButton.rightAnchor.constraint(equalTo: view.safeAreaLayoutGuide.rightAnchor, constant: -16),
        ])


        bringNavigationBarToFront()
        
        updateTheme()
    }
    
    public override func updateTheme() {
    }
    
    @objc func viewWalletPressed() {
        dismiss(animated: true)
    }
}
