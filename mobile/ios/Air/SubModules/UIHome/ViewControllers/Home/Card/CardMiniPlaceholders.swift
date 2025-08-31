
import UIKit

final class CardMiniPlaceholders: UIView {
    
    init(state: WalletCardView.State) {
        super.init(frame: .zero)
        setup()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setup() {
        alpha = 0
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        let balancePlaceholderView = UIView()
        balancePlaceholderView.translatesAutoresizingMaskIntoConstraints = false
        balancePlaceholderView.backgroundColor = .white
        balancePlaceholderView.layer.cornerRadius = 0.75
        let changePlaceholderView = UIView()
        changePlaceholderView.translatesAutoresizingMaskIntoConstraints = false
        changePlaceholderView.backgroundColor = .white
        changePlaceholderView.alpha = 0.6
        changePlaceholderView.layer.cornerRadius = 0.75
        let addressPlaceholderView = UIView()
        addressPlaceholderView.translatesAutoresizingMaskIntoConstraints = false
        addressPlaceholderView.backgroundColor = .white
        addressPlaceholderView.alpha = 0.6
        addressPlaceholderView.layer.cornerRadius = 0.75
        addSubview(balancePlaceholderView)
        addSubview(changePlaceholderView)
        addSubview(addressPlaceholderView)
        NSLayoutConstraint.activate([
            balancePlaceholderView.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            balancePlaceholderView.centerXAnchor.constraint(equalTo: centerXAnchor),
            balancePlaceholderView.widthAnchor.constraint(equalToConstant: 16),
            balancePlaceholderView.heightAnchor.constraint(equalToConstant: 1.5),
            changePlaceholderView.topAnchor.constraint(equalTo: balancePlaceholderView.bottomAnchor, constant: 2.5),
            changePlaceholderView.centerXAnchor.constraint(equalTo: centerXAnchor),
            changePlaceholderView.widthAnchor.constraint(equalToConstant: 6),
            changePlaceholderView.heightAnchor.constraint(equalToConstant: 1.5),
            addressPlaceholderView.topAnchor.constraint(equalTo: changePlaceholderView.bottomAnchor, constant: 3.5),
            addressPlaceholderView.centerXAnchor.constraint(equalTo: centerXAnchor),
            addressPlaceholderView.widthAnchor.constraint(equalToConstant: 8),
            addressPlaceholderView.heightAnchor.constraint(equalToConstant: 1.5),
            widthAnchor.constraint(equalToConstant: 34),
            heightAnchor.constraint(equalToConstant: 20)
        ])
    }
}
