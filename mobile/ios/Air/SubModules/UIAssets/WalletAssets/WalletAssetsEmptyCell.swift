import UIKit
import UIComponents
import WalletContext

final class WalletAssetsEmptyCell: UICollectionViewCell {
    nonisolated static let tokensHeight = CGFloat(170)
    nonisolated static let collectiblesHeight = CGFloat(152)

    private static let stickerSize = CGFloat(100)
    private static let horizontalInset = CGFloat(24)
    private static let contentSpacing = CGFloat(24)

    private var onAction: (() -> Void)?
    private var currentAnimationName: String?
    private var heightConstraint: NSLayoutConstraint!
    private var sticker: WAnimatedSticker?
    private var lastPlayedPlaybackSessionID: Int?

    private let stickerContainer = configured(object: UIView()) {
        $0.translatesAutoresizingMaskIntoConstraints = false
        $0.backgroundColor = .clear
    }

    private let titleLabel = configured(object: UILabel()) {
        $0.translatesAutoresizingMaskIntoConstraints = false
        $0.font = .systemFont(ofSize: 17, weight: .medium)
        $0.numberOfLines = 1
    }

    private let descriptionLabel = configured(object: UILabel()) {
        $0.translatesAutoresizingMaskIntoConstraints = false
        $0.font = .systemFont(ofSize: 14, weight: .regular)
        $0.numberOfLines = 4
    }

    private let actionButton = configured(object: UIButton(type: .system)) {
        $0.translatesAutoresizingMaskIntoConstraints = false
        var configuration = UIButton.Configuration.plain()
        configuration.contentInsets = .zero
        configuration.image = UIImage(
            systemName: "chevron.forward",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .regular)
        )
        configuration.imagePlacement = .trailing
        configuration.imagePadding = 4
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 14, weight: .regular)
            return outgoing
        }
        $0.configuration = configuration
        $0.contentHorizontalAlignment = .leading
    }

    private lazy var textStack = configured(object: UIStackView(arrangedSubviews: [titleLabel, descriptionLabel, actionButton])) {
        $0.translatesAutoresizingMaskIntoConstraints = false
        $0.axis = .vertical
        $0.alignment = .leading
        $0.spacing = 0
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { nil }

    override func prepareForReuse() {
        super.prepareForReuse()
        onAction = nil
        lastPlayedPlaybackSessionID = nil
        pauseAnimation()
        sticker?.showFirstFrame()
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        updateTheme()
    }

    func configure(
        animationName: String,
        title: String,
        description: String?,
        actionTitle: String?,
        height: CGFloat,
        descriptionNumberOfLines: Int,
        onAction: (() -> Void)? = nil
    ) {
        self.onAction = onAction
        heightConstraint.constant = height
        titleLabel.text = title
        descriptionLabel.text = description
        descriptionLabel.numberOfLines = descriptionNumberOfLines
        descriptionLabel.isHidden = description == nil

        var buttonConfiguration = actionButton.configuration
        buttonConfiguration?.title = actionTitle
        actionButton.configuration = buttonConfiguration
        actionButton.isHidden = actionTitle == nil || onAction == nil

        textStack.setCustomSpacing(descriptionLabel.isHidden ? (actionButton.isHidden ? 0 : 8) : 4, after: titleLabel)
        textStack.setCustomSpacing(actionButton.isHidden ? 0 : 8, after: descriptionLabel)

        updateSticker(animationName: animationName)
    }

    private func setupViews() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        heightConstraint = contentView.heightAnchor.constraint(equalToConstant: Self.collectiblesHeight)
        heightConstraint.isActive = true

        let container = UIStackView(arrangedSubviews: [stickerContainer, textStack])
        container.translatesAutoresizingMaskIntoConstraints = false
        container.axis = .horizontal
        container.alignment = .center
        container.spacing = Self.contentSpacing
        contentView.addSubview(container)

        actionButton.addTarget(self, action: #selector(actionButtonPressed), for: .touchUpInside)

        NSLayoutConstraint.activate([
            stickerContainer.widthAnchor.constraint(equalToConstant: Self.stickerSize),
            stickerContainer.heightAnchor.constraint(equalToConstant: Self.stickerSize),
            container.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Self.horizontalInset),
            container.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -Self.horizontalInset),
        ])

        updateTheme()
    }

    private func updateSticker(animationName: String) {
        guard currentAnimationName != animationName else {
            return
        }

        currentAnimationName = animationName
        stickerContainer.subviews.forEach { $0.removeFromSuperview() }

        let sticker = WAnimatedSticker()
        sticker.translatesAutoresizingMaskIntoConstraints = false
        sticker.animationName = animationName
        sticker.setup(
            width: Int(Self.stickerSize),
            height: Int(Self.stickerSize),
            playbackMode: .once
        )
        sticker.showFirstFrame()
        self.sticker = sticker
        lastPlayedPlaybackSessionID = nil
        stickerContainer.addSubview(sticker)

        NSLayoutConstraint.activate([
            sticker.leadingAnchor.constraint(equalTo: stickerContainer.leadingAnchor),
            sticker.trailingAnchor.constraint(equalTo: stickerContainer.trailingAnchor),
            sticker.topAnchor.constraint(equalTo: stickerContainer.topAnchor),
            sticker.bottomAnchor.constraint(equalTo: stickerContainer.bottomAnchor),
        ])
    }

    func updateAnimationPlayback(isPlaying: Bool, playbackSessionID: Int) {
        if isPlaying {
            guard lastPlayedPlaybackSessionID != playbackSessionID else {
                return
            }
            lastPlayedPlaybackSessionID = playbackSessionID
            sticker?.playOnceFromStart()
        } else {
            pauseAnimation()
        }
    }

    func pauseAnimation() {
        sticker?.pause()
    }

    private func updateTheme() {
        titleLabel.textColor = .label
        descriptionLabel.textColor = .air.secondaryLabel
        var buttonConfiguration = actionButton.configuration
        buttonConfiguration?.baseForegroundColor = .tintColor
        actionButton.configuration = buttonConfiguration
    }

    @objc private func actionButtonPressed() {
        onAction?()
    }
}
