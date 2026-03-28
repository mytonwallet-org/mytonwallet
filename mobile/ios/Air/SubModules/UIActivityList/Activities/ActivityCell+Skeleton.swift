
import UIKit
import UIComponents
import WalletContext


extension ActivityCell {
    
    public func configureSkeleton() {
        
        if skeletonView == nil {
            let skeletonView = ActivitySkeletonView()
            skeletonView.translatesAutoresizingMaskIntoConstraints = false
            skeletonView.layer.cornerRadius = 16
            contentView.addSubview(skeletonView)
            NSLayoutConstraint.activate([
                skeletonView.leftAnchor.constraint(equalTo: contentView.leftAnchor).withPriority(.defaultHigh),
                skeletonView.rightAnchor.constraint(equalTo: contentView.rightAnchor).withPriority(.defaultHigh),
                skeletonView.topAnchor.constraint(equalTo: contentView.topAnchor).withPriority(.defaultHigh),
                skeletonView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor).withPriority(.defaultLow),
            ])
            self.skeletonView = skeletonView
        } else {
            skeletonView?.alpha = 1
        }
        mainView.alpha = 0
        configureNft(activity: nil)
        configureComment(activity: nil)
        UIView.performWithoutAnimation {
            setNeedsLayout()
            layoutIfNeeded()
        }
        
        skeletonView?.layer.maskedCorners = contentView.layer.maskedCorners
    }

}

public final class ActivitySkeletonCollectionCell: UICollectionViewCell {
    nonisolated public static let defaultHeight: CGFloat = 60

    public let skeletonView = ActivitySkeletonView()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    @available(*, unavailable)
    public required init?(coder _: NSCoder) { nil }

    public override func prepareForReuse() {
        super.prepareForReuse()
        skeletonView.alpha = 1
    }

    public func configure() {
        skeletonView.alpha = 1
    }

    private func setupViews() {
        contentView.backgroundColor = .clear
        skeletonView.translatesAutoresizingMaskIntoConstraints = false
        skeletonView.layer.cornerRadius = 16
        contentView.addSubview(skeletonView)
        NSLayoutConstraint.activate([
            contentView.heightAnchor.constraint(equalToConstant: Self.defaultHeight),
            skeletonView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor).withPriority(.defaultHigh),
            skeletonView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor).withPriority(.defaultHigh),
            skeletonView.topAnchor.constraint(equalTo: contentView.topAnchor).withPriority(.defaultHigh),
            skeletonView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor).withPriority(.defaultLow),
        ])
        updateTheme()
    }

    private func updateTheme() {
        backgroundColor = .clear
        skeletonView.backgroundColor = .air.groupedItem
    }
}

public final class ActivitySkeletonView: UIView {

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    @available(*, unavailable)
    public required init?(coder _: NSCoder) { nil }

    private let iconView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.layer.cornerRadius = 20
        NSLayoutConstraint.activate([
            v.widthAnchor.constraint(equalToConstant: 40),
            v.heightAnchor.constraint(equalToConstant: 40),
        ])
        return v
    }()

    private let addressSkeletonView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.layer.cornerRadius = 4
        NSLayoutConstraint.activate([
            v.widthAnchor.constraint(equalToConstant: 88),
            v.heightAnchor.constraint(equalToConstant: 12),
        ])
        return v
    }()

    private let statusSkeletonView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.layer.cornerRadius = 4
        NSLayoutConstraint.activate([
            v.widthAnchor.constraint(equalToConstant: 48),
            v.heightAnchor.constraint(equalToConstant: 12),
        ])
        return v
    }()

    private let amountSkeletonView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.layer.cornerRadius = 4
        NSLayoutConstraint.activate([
            v.widthAnchor.constraint(equalToConstant: 88),
            v.heightAnchor.constraint(equalToConstant: 12),
        ])
        return v
    }()

    private let amountBaseCurrencySkeletonView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.layer.cornerRadius = 4
        NSLayoutConstraint.activate([
            v.widthAnchor.constraint(equalToConstant: 48),
            v.heightAnchor.constraint(equalToConstant: 12),
        ])
        return v
    }()

    private lazy var transactionContainerView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(iconView)
        v.addSubview(addressSkeletonView)
        v.addSubview(amountSkeletonView)
        v.addSubview(statusSkeletonView)
        v.addSubview(amountBaseCurrencySkeletonView)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 12),
            iconView.topAnchor.constraint(equalTo: v.topAnchor, constant: 10),
            iconView.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -10),

            addressSkeletonView.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            addressSkeletonView.topAnchor.constraint(equalTo: v.topAnchor, constant: 15),

            amountSkeletonView.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -16),
            amountSkeletonView.topAnchor.constraint(equalTo: v.topAnchor, constant: 15),

            statusSkeletonView.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            statusSkeletonView.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -13),

            amountBaseCurrencySkeletonView.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -16),
            amountBaseCurrencySkeletonView.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -13),
        ])
        return v
    }()

    private lazy var containerView: UIStackView = {
        let v = UIStackView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.axis = .vertical
        v.addArrangedSubview(transactionContainerView)
        return v
    }()

    private func setupViews() {
        addSubview(containerView)
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        updateTheme()
    }

    private func updateTheme() {
        backgroundColor = .clear
        iconView.backgroundColor = .air.groupedBackground
        addressSkeletonView.backgroundColor = .air.groupedBackground
        amountSkeletonView.backgroundColor = .air.groupedBackground
        statusSkeletonView.backgroundColor = .air.groupedBackground
        amountBaseCurrencySkeletonView.backgroundColor = .air.groupedBackground
    }
}
