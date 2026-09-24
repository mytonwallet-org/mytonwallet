import UIKit
import UIComponents
import WalletContext
import WalletCore

final class MintCardHeroView: UIView {
    var onSelect: (Int) -> Void = { _ in }
    var onTransitionEnd: () -> Void = {}
    private(set) var isTransitioning = false

    private let mediaContainer = UIView()
    private var currentMedia = MintCardMediaView(frame: .zero)
    private var incomingMedia = MintCardMediaView(frame: .zero)
    private let sweep = CAGradientLayer()
    private let title = UILabel()
    private let availability = MintCardAvailabilityView()
    private let previousButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private let dots = UIStackView()
    private var displayedType: ApiMtwCardType?
    private var showsCountdown = false
    private var transitionGeneration = 0
    private var playbackActive = false
    private var lastSize = CGSize.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        addSubview(mediaContainer)
        mediaContainer.addSubview(currentMedia)
        mediaContainer.addSubview(incomingMedia)
        incomingMedia.isHidden = true
        sweep.colors = [UIColor.clear.cgColor, UIColor.white.cgColor]
        title.applyTextStyle(.statusTitle, scaling: .dynamic)
        title.textColor = .white
        title.textAlignment = .center
        title.numberOfLines = 0
        title.accessibilityTraits.insert(.header)
        dots.spacing = 8
        dots.alignment = .center
        dots.isUserInteractionEnabled = false
        dots.accessibilityElementsHidden = true
        for _ in MintCardTypeInfo.ordered {
            let dot = UIView()
            dot.backgroundColor = .white
            dot.layer.cornerRadius = 4
            dot.widthAnchor.constraint(equalToConstant: 8).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 8).isActive = true
            dots.addArrangedSubview(dot)
        }
        for (button, offset, symbol, label) in [
            (previousButton, -1, "chevron.backward", "Previous"),
            (nextButton, 1, "chevron.forward", "Next"),
        ] {
            button.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 24, weight: .medium)), for: .normal)
            button.tintColor = UIColor.white.withAlphaComponent(0.75)
            button.accessibilityLabel = lang(label)
            button.addAction(UIAction { [weak self] _ in self?.onSelect(offset) }, for: .touchUpInside)
        }
        for view in [title, availability, dots, previousButton, nextButton] { addSubview(view) }
        accessibilityElements = [title, availability, previousButton, nextButton]
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(info: MintCardTypeInfo, cardInfo: ApiCardInfo?, direction: Int = 1, animated: Bool = false) {
        let changesType = displayedType != info.type
        let shouldAnimate = animated && changesType && displayedType != nil && MintCardTransition.isEnabled(in: self)
        if changesType { finishTransition() }
        MintCardTransition.setText(lang(info.displayNameKey), on: title, animated: shouldAnimate)
        showsCountdown = cardInfo?.mintCountdownDate != nil
        availability.configure(cardInfo, animated: shouldAnimate)
        for (index, dot) in dots.arrangedSubviews.enumerated() {
            let selected = MintCardTypeInfo.ordered[index].type == info.type
            dot.alpha = selected ? 1 : 0.3
            dot.constraints.forEach { $0.constant = selected ? 10 : 8 }
            dot.layer.cornerRadius = selected ? 5 : 4
        }
        setNeedsLayout()
        guard changesType else { return }
        displayedType = info.type
        guard shouldAnimate else {
            currentMedia.configure(info)
            updatePlayback()
            return
        }

        currentMedia.setPlaybackActive(false)
        incomingMedia.configure(info)
        incomingMedia.isHidden = false
        mediaContainer.bringSubviewToFront(incomingMedia)
        incomingMedia.layer.mask = sweep
        isTransitioning = true
        transitionGeneration += 1
        let generation = transitionGeneration
        let fromRight = (direction > 0) != (effectiveUserInterfaceLayoutDirection == .rightToLeft)
        let start = CGPoint(x: fromRight ? 1 : 0, y: 0.5)
        let end = CGPoint(x: fromRight ? 4 : -3, y: 0.5)
        let finalStart = CGPoint(x: fromRight ? -3 : 4, y: 0.5)
        let finalEnd = CGPoint(x: fromRight ? 0 : 1, y: 0.5)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sweep.frame = bounds
        sweep.startPoint = finalStart
        sweep.endPoint = finalEnd
        CATransaction.setCompletionBlock { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, transitionGeneration == generation else { return }
                finishTransition()
            }
        }
        let animation = CAAnimationGroup()
        animation.duration = MintCardTransition.duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        animation.animations = [("startPoint", start, finalStart), ("endPoint", end, finalEnd)].map { key, from, to in
            let animation = CABasicAnimation(keyPath: key)
            animation.duration = MintCardTransition.duration
            animation.fromValue = NSValue(cgPoint: from)
            animation.toValue = NSValue(cgPoint: to)
            return animation
        }
        sweep.add(animation, forKey: "cardSweep")
        CATransaction.commit()
    }

    func setPlaybackActive(_ active: Bool) {
        playbackActive = active
        if !active {
            finishTransition()
            currentMedia.stop()
            incomingMedia.stop()
        } else {
            updatePlayback()
        }
    }

    private func updatePlayback() {
        currentMedia.setPlaybackActive(playbackActive && !isTransitioning && !UIAccessibility.isReduceMotionEnabled && AppStorageHelper.animations)
    }

    private func finishTransition() {
        guard isTransitioning else { return }
        transitionGeneration += 1
        isTransitioning = false
        sweep.removeAllAnimations()
        incomingMedia.layer.mask = nil
        swap(&currentMedia, &incomingMedia)
        incomingMedia.isHidden = true
        incomingMedia.stop()
        updatePlayback()
        onTransitionEnd()
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let proposal = CGSize(width: max(0, size.width - 32), height: .greatestFiniteMagnitude)
        let titleHeight = max(28, title.sizeThatFits(proposal).height)
        let pillHeight = availability.sizeThatFits(proposal).height
        // Grow below the artwork so larger text does not cover the card or chevrons.
        return CGSize(width: size.width, height: size.width + titleHeight - 28 + pillHeight - 36)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if lastSize != bounds.size { finishTransition(); lastSize = bounds.size }
        mediaContainer.frame = bounds
        currentMedia.frame = bounds
        incomingMedia.frame = bounds
        let width = max(0, bounds.width - 32)
        let pillHeight = availability.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        availability.frame = CGRect(x: 16, y: bounds.height - 16 - pillHeight, width: width, height: pillHeight)
        let titleHeight = max(28, title.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
        title.frame = CGRect(x: 16, y: availability.frame.minY - 16 - titleHeight, width: width, height: titleHeight)
        if showsCountdown { availability.frame.origin.y -= 12 }
        dots.frame = CGRect(x: (bounds.width - 74) / 2, y: title.frame.minY - 26, width: 74, height: 10)
        let rtl = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let controlsY = bounds.width * 164 / 402 - 36
        previousButton.frame = CGRect(x: rtl ? bounds.width - 56 : 12, y: controlsY, width: 44, height: 72)
        nextButton.frame = CGRect(x: rtl ? 12 : bounds.width - 56, y: controlsY, width: 44, height: 72)
    }
}
