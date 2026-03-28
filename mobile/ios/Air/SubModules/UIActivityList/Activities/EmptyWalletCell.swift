import UIKit

final class EmptyWalletCell: UICollectionViewCell {
    private let containerView = UIView()
    private var walletCreatedView: WalletCreatedView?
    private var heightConstraint: NSLayoutConstraint!

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .clear
        containerView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(containerView)
        heightConstraint = containerView.heightAnchor.constraint(equalToConstant: 300)
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            heightConstraint,
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

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
            containerView.addSubview(walletCreatedView)
            NSLayoutConstraint.activate([
                walletCreatedView.leftAnchor.constraint(equalTo: containerView.leftAnchor, constant: 20),
                walletCreatedView.rightAnchor.constraint(equalTo: containerView.rightAnchor, constant: -20),
                walletCreatedView.topAnchor.constraint(equalTo: containerView.topAnchor),
                walletCreatedView.bottomAnchor.constraint(lessThanOrEqualTo: containerView.bottomAnchor)
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
