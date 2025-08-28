//
//  ImportSuccessVC.swift
//  UICreateWallet
//
//  Created by Sina on 4/21/23.
//

import UIKit
import WalletCore
import WalletContext
import UIPasscode
import UIHome
import UIComponents

public class ImportSuccessVC: WViewController {
    
    private let didImport: Bool
    private let wordsToImport: [String]?
    
    public init(didImport: Bool, wordsToImport: [String]?) {
        self.didImport = didImport
        self.wordsToImport = wordsToImport
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
        navigationItem.hidesBackButton = true
        
        let proceedAction = BottomAction(
            title: lang("Proceed"),
            onPress: {
                self.proceedPressed()
            }
        )
        
        bottomActionsView = BottomActionsView(primaryAction: proceedAction)
        view.addSubview(bottomActionsView)
        NSLayoutConstraint.activate([
            bottomActionsView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -58),
            bottomActionsView.leftAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leftAnchor, constant: 48),
            bottomActionsView.rightAnchor.constraint(equalTo: view.safeAreaLayoutGuide.rightAnchor, constant: -48),
        ])
        
        let topView = UIView()
        topView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topView)
        NSLayoutConstraint.activate([
            topView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topView.leftAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leftAnchor),
            topView.rightAnchor.constraint(equalTo: view.safeAreaLayoutGuide.rightAnchor),
            topView.bottomAnchor.constraint(equalTo: bottomActionsView.topAnchor)
        ])
        
        let headerView = HeaderView(animationName: "Congratulations",
                                    animationPlaybackMode: .once,
                                    title: lang("Your wallet has just been imported!"))
        topView.addSubview(headerView)
        NSLayoutConstraint.activate([
            headerView.leftAnchor.constraint(equalTo: topView.leftAnchor, constant: 32),
            headerView.rightAnchor.constraint(equalTo: topView.rightAnchor, constant: -32),
            headerView.centerYAnchor.constraint(equalTo: topView.centerYAnchor)
        ])
    }
    
    func proceedPressed() {
        guard didImport == false else {
            viewWallet()
            return
        }
        let nextVC = SetPasscodeVC(onCompletion: { biometricsEnabled, passcode, onResult in
            Task { @MainActor in
                do {
                    _ = try await AccountStore.importMnemonic(network: .mainnet, words: self.wordsToImport!, passcode: passcode, version: nil)
                    KeychainHelper.save(biometricPasscode: passcode)
                    AppStorageHelper.save(isBiometricActivated: biometricsEnabled)
                    self.viewWallet()
                } catch {
                    self.showAlert(error: error)
                    onResult()
                }
            }
        })
        navigationController?.pushViewController(nextVC, animated: true)
    }
    
    private func viewWallet() {
        Task { @MainActor in   
            guard WalletContextManager.delegate?.isWalletReady != true else {
                dismiss(animated: true)
                return
            }
            let homeVC = HomeTabBarController()
            AppActions.transitionToNewRootViewController(homeVC, animationDuration: 0.35)
        }
    }
}

#if DEBUG
@available(iOS 17.0, *)
#Preview {
    UINavigationController(rootViewController: ImportSuccessVC(didImport: true, wordsToImport: nil))
}
#endif
