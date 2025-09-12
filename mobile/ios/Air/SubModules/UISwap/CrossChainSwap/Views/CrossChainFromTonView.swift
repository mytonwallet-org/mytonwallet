//
//  CrossChainFromTonView.swift
//  UISwap
//
//  Created by Sina on 5/11/24.
//

import UIKit
import UIQRScan
import UIComponents
import WalletCore
import WalletContext

class CrossChainFromTonView: UIStackView, WThemedView {
    
    private let buyingToken: ApiToken!
    private let onAddressChanged: (String) -> Void
    init(buyingToken: ApiToken, onAddressChanged: @escaping (String) -> Void) {
        self.buyingToken = buyingToken
        self.onAddressChanged = onAddressChanged
        super.init(frame: .zero)
        setupViews()
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private let titleLabel = {
        let lbl = UILabel()
        lbl.text = lang("Receive to")
        lbl.font = .systemFont(ofSize: 13)
        return lbl
    }()
    
    private lazy var addressTextField = {
        let textField = WAddressInput()
        textField.textChanged = { [weak self] str in
            self?.onAddressChanged(str)
        }
        textField.onScanPressed = { [weak self] in
            self?.scanPressed()
        }
        return textField
    }()
    
    private var descriptionLabel = {
        let lbl = UILabel()
        lbl.text = lang("Please provide an address of your wallet in another blockchain to receive bought tokens.")
        lbl.font = .systemFont(ofSize: 13)
        lbl.numberOfLines = 0
        lbl.textColor = WTheme.secondaryLabel
        return lbl
    }()
    
    private func setupViews() {
        translatesAutoresizingMaskIntoConstraints = false
        axis = .vertical
        alignment = .fill
        addArrangedSubview(titleLabel, margin: .init(top: 5, left: 16, bottom: 0, right: 16))
        addArrangedSubview(addressTextField, margin: .init(top: 5, left: 0, bottom: 8, right: 0))
        addArrangedSubview(descriptionLabel, margin: .init(top: 0, left: 16, bottom: 0, right: 16))
        updateTheme()
    }
    
    public func updateTheme() {
        titleLabel.textColor = WTheme.secondaryLabel
        addressTextField.backgroundColor = WTheme.background
        addressTextField.attributedPlaceholder = NSAttributedString(
            string: WStrings.CrossChainSwap_EnterChainAddress_Text(symbol: buyingToken.chain.uppercased()),
            attributes: [
                .font: UIFont.systemFont(ofSize: 17),
                .foregroundColor: WTheme.secondaryLabel
            ])
    }
    
    @objc private func scanPressed() {
        let qrScanVC = QRScanVC(callback: { [weak self] result in
            guard let self else {return}
            switch result {
            case .url(_):
                return
            case .address(let address, let possibleChains):
                guard possibleChains.contains(where: { it in
                    it.rawValue == self.buyingToken.chain
                }) else {
                    return
                }
                addressTextField.textView.text = address
                addressTextField.textViewDidChange(addressTextField.textView)
            @unknown default:
                break
            }
        })
        topViewController()?.present(WNavigationController(rootViewController: qrScanVC), animated: true)
    }
    
}
