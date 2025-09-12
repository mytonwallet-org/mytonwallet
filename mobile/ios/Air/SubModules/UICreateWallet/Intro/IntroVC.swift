//
//  StartVC.swift
//  UICreateWallet
//
//  Created by Sina on 3/31/23.
//

import UIKit
import UIComponents
import WalletContext
import WalletCore

public class IntroVC: WViewController {

    public init() {
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func loadView() {
        super.loadView()
        setupViews()
    }
    
    private var bottomActionsView: BottomActionsView!

    func setupViews() {
        // content view
        let contentView = UIStackView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.axis = .vertical
        contentView.spacing = 32
        contentView.alignment = .center
        view.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.leftAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leftAnchor),
            contentView.rightAnchor.constraint(equalTo: view.safeAreaLayoutGuide.rightAnchor),
            contentView.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor)
        ])

        // header, center of top view
        let headerView = HeaderView(animationName: "Start",
                                    animationPlaybackMode: .loop,
                                    title: lang("MyTonWallet"),
                                    description: lang("Securely store and send crypto."))

        // bottom create wallet action
        let createWalletButton = BottomAction(
            title: lang("Create Wallet"),
            onPress: {
                self.createWalletPressed()
            }
        )
        
        // bottom import wallet action
        let importExistingWalletButton = BottomAction(
            title: lang("Import Existing Wallet"),
            onPress: {
                self.importWalletPressed()
            }
        )
        
        // bottom actions view
        bottomActionsView = BottomActionsView(primaryAction: createWalletButton,
                                              secondaryAction: importExistingWalletButton)

        contentView.addArrangedSubview(headerView)
        contentView.addArrangedSubview(bottomActionsView)
        NSLayoutConstraint.activate([
            headerView.widthAnchor.constraint(equalTo: contentView.widthAnchor, constant: -64),
            bottomActionsView.widthAnchor.constraint(equalTo: contentView.widthAnchor, constant: -64)
        ])
        
        view.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(onLongPress(_:))))
    }

    var isLoading = false {
        didSet {
            bottomActionsView.primaryButton.showLoading = isLoading
            view.isUserInteractionEnabled = !isLoading
        }
    }
    func createWalletPressed() {
        if isLoading {
            return
        }
        isLoading = true

        // generate mnemonic!
        Task { @MainActor in
            do {
                let words = try await Api.generateMnemonic()
                let walletCreatedVC = WalletCreatedVC(wordList: words, passedPasscode: nil)
                navigationController?.pushViewController(walletCreatedVC, animated: true)
                isLoading = false
            } catch {
                showAlert(error: error)
                isLoading = false
            }
        }
    }
    
    func importWalletPressed() {
        navigationController?.pushViewController(ImportWalletVC(passedPasscode: nil), animated: true)
    }
    
    func showAlert() {
        showAlert(title: lang("An Error Occurred"),
                  text: lang("Sorry. Please try again."),
                  button: lang("OK"))
    }
    
    @objc func onLongPress(_ gesture: UIGestureRecognizer) {
        if gesture.state == .began {
            (UIApplication.shared.delegate as? MtwAppDelegateProtocol)?.showDebugView()
        }
    }
}

#if DEBUG
@available(iOS 17.0, *)
#Preview {
    return UINavigationController(rootViewController: IntroVC())
}
#endif
