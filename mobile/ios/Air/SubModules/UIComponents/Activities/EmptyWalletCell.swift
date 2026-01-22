import UIKit

final class EmptyWalletCell: UITableViewCell {
    private var walletCreatedView: WalletCreatedView?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        walletCreatedView?.alpha = 0
    }

    func set(animated: Bool) {
        showWalletCreatedView(animated: animated)
    }

    private func showWalletCreatedView(animated: Bool) {
        contentView.transform = .identity
        contentView.alpha = 1

        let walletCreatedView = walletCreatedView ?? WalletCreatedView()
        if walletCreatedView.superview == nil {
            walletCreatedView.alpha = 0
            contentView.addSubview(walletCreatedView)
            NSLayoutConstraint.activate([
                walletCreatedView.leftAnchor.constraint(equalTo: contentView.leftAnchor, constant: 20),
                walletCreatedView.rightAnchor.constraint(equalTo: contentView.rightAnchor, constant: -20),
                walletCreatedView.topAnchor.constraint(equalTo: contentView.topAnchor),
                walletCreatedView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor)
            ])
            self.walletCreatedView = walletCreatedView
        }

        if animated {
            layoutIfNeeded()
            UIView.animate(withDuration: 0.4) { [weak self] in
                self?.walletCreatedView?.alpha = 1
            }
        } else {
            walletCreatedView.alpha = 1
        }
    }
}
