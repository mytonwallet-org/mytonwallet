
import Kingfisher
import UIKit
import WalletContext
import WalletCore


extension ActivityCell {
    
    public func configureSkeleton() {
        
        if skeletonView == nil {
            let skeletonView = ActivityCell.Skeleton()
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

    func fadeOutSkeleton() {
        mainView.alpha = 0
        layoutIfNeeded()
        UIView.animate(withDuration: 0.3) { [self] in
            skeletonView?.alpha = 0
            mainView.alpha = 1
        }
    }

    class Skeleton: UIView, WThemedView {
        
        init() {
            super.init(frame: .zero)
            setupViews()
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
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
                containerView.trailingAnchor.constraint(equalTo: trailingAnchor)
            ])
            updateTheme()
        }
        
        public func updateTheme() {
            backgroundColor = .clear
            iconView.backgroundColor = WTheme.groupedBackground
            addressSkeletonView.backgroundColor = WTheme.groupedBackground
            amountSkeletonView.backgroundColor = WTheme.groupedBackground
            statusSkeletonView.backgroundColor = WTheme.groupedBackground
            amountBaseCurrencySkeletonView.backgroundColor = WTheme.groupedBackground
        }
        
    }
}
