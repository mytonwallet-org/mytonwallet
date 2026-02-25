import UIKit
import UIComponents
import WalletCore
import WalletContext

final class CrosschainFromWalletView: UIStackView, WThemedView {
    
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
    
    private lazy var descriptionLabel = {
        let lbl = UILabel()
        lbl.text = lang("Please provide an address of your wallet in %blockchain% blockchain to receive bought tokens.", arg1: getChainName(buyingToken.chain))
        lbl.font = .systemFont(ofSize: 13)
        lbl.numberOfLines = 0
        lbl.textColor = WTheme.secondaryLabel
        return lbl
    }()
    
    private func setupViews() {
        translatesAutoresizingMaskIntoConstraints = false
        axis = .vertical
        alignment = .fill
        addArrangedSubview(addressTextField, margin: .init(top: 12, left: 0, bottom: 8, right: 0))
        addArrangedSubview(descriptionLabel, margin: .init(top: 0, left: 16, bottom: 0, right: 16))
        updateTheme()
    }
    
    public func updateTheme() {
        addressTextField.backgroundColor = WTheme.background
        addressTextField.attributedPlaceholder = NSAttributedString(
            string: lang("Your address on another blockchain"),
            attributes: [
                .font: UIFont.systemFont(ofSize: 17),
                .foregroundColor: WTheme.secondaryLabel
            ])
    }
    
    @objc private func scanPressed() {
        Task {
            if let result = await AppActions.scanQR() {
                switch result {
                case .url(_):
                    return
                case .address(let address, let possibleChains):
                    guard possibleChains.contains(where: { it in
                        it == self.buyingToken.chain
                    }) else {
                        return
                    }
                    addressTextField.textView.text = address
                    addressTextField.textViewDidChange(addressTextField.textView)
                }
            }
        }
    }
}
