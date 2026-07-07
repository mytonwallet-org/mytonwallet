import UIKit
import UIComponents
import WalletCore
import WalletContext

public final class NftPreviewLarge: UIView {
    
    private let mediaView = NftMediaView()
    private var labelsStack: UIView = .init()
    private let nameLabel: UILabel = .init()
    private let collectionLabel: UILabel = .init()
    private var nft: ApiNft?
    private var accountContext: AccountContext?
    
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
        
        mediaView.translatesAutoresizingMaskIntoConstraints = false
        mediaView.isUserInteractionEnabled = true
        mediaView.mediaContentMode = .scaleAspectFill
        mediaView.animationRenderingConfiguration = .activityPreviewDefault
        mediaView.disablesAnimationPlaybackInLowPowerMode = true
        mediaView.layer.cornerRadius = 12
        mediaView.layer.cornerCurve = .continuous
        mediaView.layer.masksToBounds = true
        addSubview(mediaView)
        
        NSLayoutConstraint.activate([
            mediaView.heightAnchor.constraint(equalToConstant: 54),
            mediaView.widthAnchor.constraint(equalToConstant: 54),
            mediaView.topAnchor.constraint(equalTo: topAnchor),
            mediaView.leadingAnchor.constraint(equalTo: leadingAnchor),
            mediaView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            mediaView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        labelsStack.translatesAutoresizingMaskIntoConstraints = false
        labelsStack.accessibilityIdentifier = "labelsStack"
        addSubview(labelsStack)
        NSLayoutConstraint.activate([
            labelsStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            labelsStack.leadingAnchor.constraint(equalTo: mediaView.trailingAnchor, constant: 10),
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
        
        let cardTap = UITapGestureRecognizer(target: self, action: #selector(onTap))
        let imageTap = UITapGestureRecognizer(target: self, action: #selector(onImageTap))
        cardTap.require(toFail: imageTap)
        addGestureRecognizer(cardTap)
        mediaView.addGestureRecognizer(imageTap)
    }
        
    @objc private func onTap() {
        showNft(isExpanded: false)
    }

    @objc private func onImageTap() {
        showNft(isExpanded: true)
    }

    private func showNft(isExpanded: Bool) {
        guard let accountContext, let nft else { return }
        AppActions.showNft(accountContext: accountContext, nft: nft, isExpanded: isExpanded)
    }
    
    private func updateTheme() {
        backgroundColor = .air.activityNftFill
        mediaView.backgroundColor = .air.secondaryFill
        nameLabel.textColor = UIColor.label
        collectionLabel.textColor = .air.secondaryLabel
    }

    public func setNft(_ nft: ApiNft?, accountContext: AccountContext) {
        self.accountContext = accountContext
        
        guard needsUpdate(for: nft) else { return }
        
        self.nft = nft
        mediaView.configure(nft: nft)
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

    private func needsUpdate(for nft: ApiNft?) -> Bool {
        self.nft?.id != nft?.id
            || self.nft?.thumbnail != nft?.thumbnail
            || self.nft?.image != nft?.image
            || self.nft?.metadata?.lottie != nft?.metadata?.lottie
            || self.nft?.name != nft?.name
            || self.nft?.collectionName != nft?.collectionName
    }
}

extension NftPreviewLarge: NftAnimationPlaybackTarget {
    public var nftAnimationPlaybackID: String? {
        self.nft?.id
    }

    public var hasPlayableAnimation: Bool {
        self.mediaView.hasPlayableAnimation
    }

    public func playNftAnimationOnce() {
        self.mediaView.animationRenderingConfiguration = .activityPreviewDefault
        self.mediaView.playAnimationOnce()
    }

    public func stopNftAnimationPlayback() {
        self.mediaView.stopAnimationPlayback()
    }
}
