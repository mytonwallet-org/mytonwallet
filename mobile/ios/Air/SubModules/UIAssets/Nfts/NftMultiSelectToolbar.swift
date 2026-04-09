import UIKit
import UIComponents
import WalletContext

protocol NftMultiSelectToolbarDelegate: AnyObject {
    func multiSelectToolbarDidDelectHideAction()
    func multiSelectToolbarDidDelectBurnAction()
    func multiSelectToolbarDidDelectSendAction()
}

class NftMultiSelectToolbar: UIView {
    private static let height: CGFloat = 70
    
    let burnButton = WButton(style: .thickCapsule)
    let hideButton = WButton(style: .thickCapsule)
    let sendButton = WButton(style: .thickCapsule)
    
    weak var delegate: NftMultiSelectToolbarDelegate?
        
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        let toolbar = UIStackView()
        toolbar.axis = .horizontal
        toolbar.distribution = .equalSpacing
        
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(toolbar)
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: trailingAnchor),
            heightAnchor.constraint(equalToConstant: Self.height),
            toolbar.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        
        burnButton.setTitle(lang("Burn"), for: .normal)
        burnButton.addTarget(self, action: #selector(burn), for: .touchUpInside)
        toolbar.addArrangedSubview(burnButton)

        hideButton.setTitle(lang("Hide"), for: .normal)
        hideButton.addTarget(self, action: #selector(hide), for: .touchUpInside)
        toolbar.addArrangedSubview(hideButton)

        sendButton.setTitle(lang("Send"), for: .normal)
        sendButton.addTarget(self, action: #selector(send), for: .touchUpInside)
        sendButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        toolbar.addArrangedSubview(sendButton)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func hide() {
        delegate?.multiSelectToolbarDidDelectHideAction()
    }

    @objc private func burn() {
        delegate?.multiSelectToolbarDidDelectBurnAction()
    }

    @objc private func send() {
        delegate?.multiSelectToolbarDidDelectSendAction()
    }
}
