//
//  SendVC.swift
//  MyTonWalletAir
//
//  Created by nikstar on 21.11.2024.
//

import Foundation
import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext


public final class SendVC: WNavigationController {
    
    let sendModel: SendModel
    let rootVC: UIViewController

    public init(accountContext: AccountContext, prefilledValues: SendPrefilledValues) {
        self.sendModel = SendModel(accountContext: accountContext, prefilledValues: prefilledValues)
        
        switch sendModel.mode {
        case .burnNft, .sellToMoonpay:
            rootVC = SendConfirmVC(model: sendModel)
        case .regular, .sendNft:
            rootVC = SendComposeVC(model: sendModel)
        }
        super.init(rootViewController: rootVC)
    }
    
    @MainActor public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        let textField = UITextField()
        view.addSubview(textField)
        textField.becomeFirstResponder()
        textField.resignFirstResponder()
        textField.removeFromSuperview()
    }
}
