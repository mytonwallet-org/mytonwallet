
import SwiftUI
import UIKit
import WalletCore
import WalletContext

public final class NftPreviewLarge: UIView {
    
    private let imageView: UIImageView = .init()
    private var labelsStack: UIView = .init()
    private let nameLabel: UILabel = .init()
    private let collectionLabel: UILabel = .init()
    private var collectionConstraints: [NSLayoutConstraint] = []
    private var nft: ApiNft?
    
    // Store constraints to activate/deactivate them
    private var collectionLabelTopSpacingConstraint: NSLayoutConstraint?
    private var collectionLabelBottomConstraint: NSLayoutConstraint?
    private var nameLabelBottomConstraint: NSLayoutConstraint?

    public init() {
        super.init(frame: .zero)
        setup()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        imageView.contentMode = .scaleAspectFill
        imageView.layer.cornerRadius = 12
        imageView.layer.cornerCurve = .continuous
        imageView.layer.masksToBounds = true
        
        NSLayoutConstraint.activate([
            imageView.heightAnchor.constraint(equalToConstant: 54),
            imageView.widthAnchor.constraint(equalToConstant: 54),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        labelsStack.translatesAutoresizingMaskIntoConstraints = false
        labelsStack.accessibilityIdentifier = "labelsStack"
        addSubview(labelsStack)
        NSLayoutConstraint.activate([
            labelsStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            labelsStack.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 10),
            labelsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
        ])

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        labelsStack.addSubview(nameLabel)
        nameLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        nameLabel.textAlignment = .left

        collectionLabel.translatesAutoresizingMaskIntoConstraints = false
        labelsStack.addSubview(collectionLabel)
        collectionLabel.font = UIFont.systemFont(ofSize: 14)

        NSLayoutConstraint.activate([
            nameLabel.topAnchor.constraint(equalTo: labelsStack.topAnchor),
            nameLabel.leadingAnchor.constraint(equalTo: labelsStack.leadingAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: labelsStack.trailingAnchor),
        ])
        
        collectionLabelTopSpacingConstraint = collectionLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 1)
        collectionLabelBottomConstraint = collectionLabel.bottomAnchor.constraint(equalTo: labelsStack.bottomAnchor)
        nameLabelBottomConstraint = nameLabel.bottomAnchor.constraint(equalTo: labelsStack.bottomAnchor)

        NSLayoutConstraint.activate([
            collectionLabel.leadingAnchor.constraint(equalTo: labelsStack.leadingAnchor),
            collectionLabel.trailingAnchor.constraint(equalTo: labelsStack.trailingAnchor),
        ])

        updateTheme()
    }
    
    func updateTheme() {
        backgroundColor = .air.activityNftFill
        imageView.backgroundColor = WTheme.secondaryFill
        nameLabel.textColor = WTheme.primaryLabel
        collectionLabel.textColor = WTheme.secondaryLabel
    }

    public func setNft(_ nft: ApiNft?) {
        if self.nft == nft { return }
        self.nft = nft
        if let image = nft?.thumbnail?.nilIfEmpty, let url = URL(string: image) {
            imageView.kf.setImage(
                with: url,
                options: [.transition(.fade(0.2))]
            )
            imageView.kf.indicatorType = .activity
        } else {
            imageView.image = nil
        }
        nameLabel.text = nft?.name ?? "NFT"
        
        let hasSubtitle = nft?.collectionName?.nilIfEmpty != nil

        if hasSubtitle {
            collectionLabel.text = nft?.collectionName
            collectionLabel.isHidden = false
            nameLabelBottomConstraint?.isActive = false
            collectionLabelTopSpacingConstraint?.isActive = true
            collectionLabelBottomConstraint?.isActive = true
        } else {
            collectionLabel.text = nil
            collectionLabel.isHidden = true
            collectionLabelTopSpacingConstraint?.isActive = false
            collectionLabelBottomConstraint?.isActive = false
            nameLabelBottomConstraint?.isActive = true
        }
    }
}

