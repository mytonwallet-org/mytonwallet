//
//  WalletCreatedVC.swift
//  UICreateWallet
//
//  Created by Sina on 3/16/24.
//

import UIKit
import WalletCore
import WalletContext
import UIComponents
import UIPasscode

public class WalletCreatedVC: WViewController {
    
    var wordList: [String]
    var isFirstWallet: Bool
    var passedPasscode: String?

    public init(wordList: [String], passedPasscode: String?) {
        self.wordList = wordList
        self.isFirstWallet = passedPasscode == nil
        self.passedPasscode = passedPasscode
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

        let headerView = HeaderView(animationName: "Congratulations",
                                    animationPlaybackMode: .once,
                                    title: lang("Wallet Created"),
                                    description: lang("Your TON Wallet has just been created."))

        let proceedAction = BottomAction(
            title: lang("Proceed"),
            onPress: {
                self.proceedPressed()
            }
        )

        let removeWalletAction = BottomAction(
            title: lang("Cancel"),
            onPress: {
                self.cancelPressed()
            }
        )
        
        bottomActionsView = BottomActionsView(primaryAction: proceedAction, secondaryAction: removeWalletAction)
        view.addSubview(bottomActionsView)

        contentView.addArrangedSubview(headerView)
        contentView.addArrangedSubview(bottomActionsView)
        NSLayoutConstraint.activate([
            headerView.widthAnchor.constraint(equalTo: contentView.widthAnchor, constant: -64),
            bottomActionsView.widthAnchor.constraint(equalTo: contentView.widthAnchor, constant: -64)
        ])
    }

    private func proceedPressed() {
        if wordList.isEmpty {
            return
        }
        let wordDisplayVC = WordDisplayVC(wordList: wordList, passedPasscode: passedPasscode)
        navigationController?.pushViewController(wordDisplayVC, animated: true)
    }
    
    private func cancelPressed() {
        if navigationController?.viewControllers.count ?? 1 > 1 {
            navigationController?.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }

}

#if DEBUG
@available(iOS 17.0, *)
#Preview {
    return WalletCreatedVC(wordList: [], passedPasscode: nil)
}
#endif
