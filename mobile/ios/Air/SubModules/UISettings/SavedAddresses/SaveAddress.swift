import UIKit
import UIComponents
import SwiftUI
import WalletCore
import WalletContext

private let log = Log("SaveAddress")

@MainActor public func makeSaveAddressAlertController(accountContext: AccountContext, chain: ApiChain, address: String) -> UIAlertController {
    return SaveAddressAlertController(accountContext: accountContext, chain: chain, address: address)
}

final class SaveAddressAlertController: UIAlertController, UITextFieldDelegate {

    var submitAction: UIAlertAction!
    
    convenience init(accountContext: AccountContext, chain: ApiChain, address: String) {
        self.init(
            title: lang("Save Address"),
            message: lang("You can save this address for quick access while sending."),
            preferredStyle: .alert
        )
        submitAction = UIAlertAction(title: lang("OK"), style: .default) { [unowned self] _ in
            let name = self.textFields![0].text ?? ""
            withAnimation {
                accountContext.savedAddresses.save(SavedAddress(name: name, address: address, chain: chain))
            }
        }
        submitAction.isEnabled = false
        
        addTextField()
        let textField = textFields![0]
        textField.text = ""
        textField.autocapitalizationType = .words
        textField.autocorrectionType = .yes
        textField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)

        addAction(submitAction)
        preferredAction = submitAction
        
        let cancelAction = UIAlertAction(title: lang("Cancel"), style: .cancel)
        addAction(cancelAction)
    }
    
    @objc func textFieldDidChange(textField: UITextField) {
        submitAction.isEnabled = textField.text?.trimmingCharacters(in: .whitespaces).nilIfEmpty != nil
    }
}
