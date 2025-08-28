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

    public init(prefilledValues: SendModel.PrefilledValues? = nil) {
        self.sendModel = SendModel(prefilledValues: prefilledValues)
        
        if sendModel.nftSendMode != .burn {
            rootVC = SendComposeVC(model: sendModel)
        } else {
            rootVC = SendConfirmVC(model: sendModel)
        }
        super.init(rootViewController: rootVC)
        
        sendModel.present = { [weak self] in
            self?.present($0, animated: true)
        }
        sendModel.push = { [weak self] in
            self?.isEditing = false
            self?.pushViewController($0, animated: true)
        }
        sendModel.dismiss = { [weak self] vc in
            self?.dismiss(animated: true)
        }
        sendModel.showAlert = { [weak self] error in
            self?.view.endEditing(true)
            self?.showAlert(error: error)
        }
    }
    
    @MainActor public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }    
}
