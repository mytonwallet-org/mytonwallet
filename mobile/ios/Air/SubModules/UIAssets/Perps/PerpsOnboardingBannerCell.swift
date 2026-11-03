import ContextMenuKit
import UIComponents
import UIKit
import WalletContext

final class PerpsOnboardingBannerCell: UICollectionViewCell, UIGestureRecognizerDelegate {
    var onOpen: (() -> Void)?
    var onDismiss: (() -> Void)?
    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let artwork = UIImageView()
    private let illustration = UIImageView()
    private let closeButton = UIButton(type: .system)
    private var usesWideLayout: Bool?
    private let button = WInteractiveGlassButton(style: .primary)
    private let bannerTap = PerpsOnboardingPressGestureRecognizer(target: nil, action: nil)
    private let gradient = CAGradientLayer()
    private let artworkMask = CAGradientLayer()
    private var contentIdentity = UUID()
    private var isPreparingPresentation = false

    func presentationSource() -> StoriesPresentationSource {
        let identity = contentIdentity
        return StoriesPresentationSource(view: contentView, button: button, prepareForPresentation: { [weak self] in
            guard let self, contentIdentity == identity else { return {} }
            let visibleTransform = layer.presentation()?.sublayerTransform ?? layer.sublayerTransform
            resetPressAnimation(to: visibleTransform)
            isPreparingPresentation = true
            return { [weak self] in
                guard let self, contentIdentity == identity else { return }
                resetPressAnimation()
                isPreparingPresentation = false
            }
        }) { [weak self] in
            self?.contentIdentity == identity && self?.onOpen != nil
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "perps.onboarding.banner"
        contentView.layer.cornerRadius = 26
        contentView.layer.cornerCurve = .continuous
        contentView.clipsToBounds = true
        gradient.colors = [UIColor(red: 45 / 255, green: 189 / 255, blue: 1, alpha: 1).cgColor,
                           UIColor(red: 21 / 255, green: 144 / 255, blue: 1, alpha: 1).cgColor,
                           UIColor(red: 10 / 255, green: 108 / 255, blue: 240 / 255, alpha: 1).cgColor]
        gradient.locations = [0, 0.55, 1]
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        contentView.layer.addSublayer(gradient)
        artwork.contentMode = .scaleToFill
        artwork.isAccessibilityElement = false
        contentView.addSubview(artwork)

        titleLabel.accessibilityTraits.insert(.header)
        titleLabel.accessibilityIdentifier = "perps.onboarding.title"
        descriptionLabel.accessibilityIdentifier = "perps.onboarding.description"
        for label in [titleLabel, descriptionLabel] { label.numberOfLines = 0 }
        illustration.contentMode = .scaleAspectFit
        illustration.isAccessibilityElement = false
        illustration.accessibilityIdentifier = "perps.onboarding.illustration"
        button.setTitle(lang("PerpsOnboardingOpen"), for: .normal)
        button.layer.cornerRadius = 26
        button.accessibilityIdentifier = "perps.onboarding.open"
        button.addAction(UIAction { [weak self] _ in self?.onOpen?() }, for: .touchUpInside)
        closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)), for: .normal)
        closeButton.tintColor = .white.withAlphaComponent(0.92)
        closeButton.accessibilityLabel = lang("Close")
        closeButton.accessibilityIdentifier = "perps.onboarding.dismiss"
        closeButton.addAction(UIAction { [weak self] _ in self?.onDismiss?() }, for: .touchUpInside)
        let closeBackground = UIView()
        closeBackground.backgroundColor = .white.withAlphaComponent(0.18)
        closeBackground.layer.cornerRadius = 14
        closeBackground.isUserInteractionEnabled = false
        closeBackground.frame = CGRect(x: 8, y: 8, width: 28, height: 28)
        closeButton.insertSubview(closeBackground, at: 0)
        for view in [illustration, titleLabel, descriptionLabel, button, closeButton] { contentView.addSubview(view) }
        configureLayout(wide: false)
        bannerTap.delegate = self
        bannerTap.onPress = { [weak self] pressed in self?.setPressed(pressed) }
        bannerTap.onTap = { [weak self] in self?.onOpen?() }
        addGestureRecognizer(bannerTap)
        accessibilityElements = [titleLabel, descriptionLabel, button, closeButton]
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = contentView.bounds.width
        let wide = Self.isWide(width)
        configureLayout(wide: wide)
        let textWidth = Self.textWidth(for: width)
        let titleHeight = titleLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude)).height
        let descriptionHeight = descriptionLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude)).height
        let gap: CGFloat = wide ? 4 : 8
        let textHeight = titleHeight + gap + descriptionHeight
        let isRTL = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let textX = isRTL ? width - 24 - textWidth : 24
        let textY: CGFloat = wide ? (contentView.bounds.height - textHeight - 52) / 2 : 45
        titleLabel.frame = CGRect(x: textX, y: textY, width: textWidth, height: titleHeight)
        descriptionLabel.frame = CGRect(x: textX, y: titleLabel.frame.maxY + gap, width: textWidth, height: descriptionHeight)
        let imageSize = wide ? CGSize(width: 230, height: 134) : CGSize(width: 196, height: 114)
        let imageInset: CGFloat = wide ? 43 : 12
        illustration.frame = CGRect(x: isRTL ? imageInset : width - imageInset - imageSize.width,
                                    y: wide ? (contentView.bounds.height - imageSize.height) / 2 : 46,
                                    width: imageSize.width, height: imageSize.height)
        let buttonWidth = wide ? min(textWidth, ceil(button.glassTitleLabel.sizeThatFits(.init(width: textWidth, height: 40)).width) + 48) : width - 48
        button.frame = CGRect(x: isRTL ? width - 24 - buttonWidth : 24,
                              y: wide ? descriptionLabel.frame.maxY + 12 : contentView.bounds.height - 76,
                              width: buttonWidth, height: wide ? 40 : 52)
        closeButton.frame = CGRect(x: isRTL ? 4 : width - 48, y: 4, width: 44, height: 44)
        artwork.frame = CGRect(x: width - (wide ? 603 : 370), y: 0,
                               width: wide ? 603 : 370, height: contentView.bounds.height)
        if isRTL { artwork.frame.origin.x = 0 }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = contentView.bounds
        if width > artwork.bounds.width {
            artworkMask.frame = artwork.bounds
            artworkMask.colors = [UIColor.clear.cgColor, UIColor.white.cgColor, UIColor.white.cgColor]
            artworkMask.locations = [0, NSNumber(value: Double(40 / artwork.bounds.width)), 1]
            artworkMask.startPoint = CGPoint(x: isRTL ? 1 : 0, y: 0.5)
            artworkMask.endPoint = CGPoint(x: isRTL ? 0 : 1, y: 0.5)
            artwork.layer.mask = artworkMask
        } else {
            artwork.layer.mask = nil
        }
        CATransaction.commit()
    }

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let attributes = layoutAttributes.copy() as! UICollectionViewLayoutAttributes
        let wide = Self.isWide(attributes.size.width)
        configureLayout(wide: wide)
        let width = Self.textWidth(for: attributes.size.width)
        let textHeight = titleLabel.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
            + (wide ? 4 : 8) + descriptionLabel.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        attributes.size.height = wide ? max(140, 36 + textHeight + 12 + 40) : max(270, 45 + textHeight + 16 + 52 + 24)
        return attributes
    }

    private func configureLayout(wide: Bool) {
        guard usesWideLayout != wide else { return }
        usesWideLayout = wide
        contentView.layer.cornerRadius = wide ? 24 : 26
        titleLabel.attributedText = Self.text(lang("PerpsOnboardingTitle"), font: WTypography.uiFont(.startupTitle).withSize(wide ? 22 : 26), lineHeight: wide ? 28 : 32)
        let description = lang("PerpsOnboardingDescription")
        descriptionLabel.attributedText = Self.text(wide ? description.replacingOccurrences(of: "\n", with: " ") : description,
                                                   font: WTypography.uiFont(.supportingEmphasized), lineHeight: 20)
        artwork.image = .airBundleOptional(wide ? "PerpsOnboardingArtworkWide" : "PerpsOnboardingArtwork")
        illustration.image = .airBundleOptional(wide ? "PerpsOnboardingIllustrationWide" : "PerpsOnboardingIllustration")
        button.customTitleFont = WTypography.uiFont(.capsuleButton).withSize(wide ? 15 : 17)
        button.configureInteractiveGlass(tintColor: .white.withAlphaComponent(0.7),
                                         foregroundColor: UIColor(red: 11 / 255, green: 31 / 255, blue: 68 / 255, alpha: 1))
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        bannerTap.cancelTracking()
        resetPressAnimation()
        isPreparingPresentation = false
        contentView.transform = .identity
        contentIdentity = UUID()
        contentView.isHidden = false
        button.isHidden = false
        onOpen = nil
        onDismiss = nil
    }

    func acceptsBannerTouch(on view: UIView) -> Bool {
        onOpen != nil && ![button, closeButton].contains { view === $0 || view.isDescendant(of: $0) }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let view = touch.view else { return false }
        return acceptsBannerTouch(on: view)
    }

    private func setPressed(_ pressed: Bool) {
        guard !isPreparingPresentation else { return }
        let settings = PerpsOnboardingPressGestureRecognizer.animation
        let current = layer.presentation()?.sublayerTransform ?? layer.sublayerTransform
        let width = max(bounds.width, 1)
        let scale = pressed && TradeMotion.enabled ? max(settings.minimumScale, (width - settings.scaleInset) / width) : 1
        let target = CATransform3DMakeScale(scale, scale, 1)
        layer.removeAnimation(forKey: "perps.onboarding.press")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.sublayerTransform = target
        CATransaction.commit()
        guard TradeMotion.enabled else { return }
        let animation = CABasicAnimation(keyPath: "sublayerTransform")
        animation.fromValue = NSValue(caTransform3D: current)
        animation.toValue = NSValue(caTransform3D: target)
        animation.duration = pressed ? settings.pressInDuration : settings.releaseDuration
        animation.timingFunction = CAMediaTimingFunction(name: pressed ? .linear : .easeOut)
        layer.add(animation, forKey: "perps.onboarding.press")
    }

    private func resetPressAnimation(to transform: CATransform3D = CATransform3DIdentity) {
        layer.removeAnimation(forKey: "perps.onboarding.press")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.sublayerTransform = transform
        CATransaction.commit()
    }

    private static func isWide(_ width: CGFloat) -> Bool { width >= 560 }

    private static func textWidth(for width: CGFloat) -> CGFloat {
        isWide(width) ? min(300, width - 303) : min(160, max(1, width - 210))
    }

    private static func text(_ text: String, font: UIFont, lineHeight: CGFloat) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        return NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: UIColor.white, .paragraphStyle: paragraph])
    }
}

@MainActor
final class PerpsOnboardingPressGestureRecognizer: UIGestureRecognizer {
    static let animation = ContextMenuPressAnimation.default(transformMode: .sublayerTransform)
    var onPress: ((Bool) -> Void)?
    var onTap: (() -> Void)?
    private var initialLocation: CGPoint?
    private var delayTimer: Timer?
    private var isPressed = false

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard touches.count == 1, let touch = touches.first, let view else {
            cancelTracking()
            state = .failed
            return
        }
        beginTracking(at: touch.location(in: view))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard let touch = touches.first, let view else { return }
        moveTracking(to: touch.location(in: view))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        endTracking()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        cancelTracking()
    }

    override func reset() {
        stopTracking()
        super.reset()
    }

    func beginTracking(at location: CGPoint) {
        guard initialLocation == nil, state == .possible else { return }
        initialLocation = location
        let timer = Timer(timeInterval: Self.animation.beginDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.initialLocation != nil, self.state == .possible else { return }
                self.isPressed = true
                self.onPress?(true)
            }
        }
        delayTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func moveTracking(to location: CGPoint) {
        guard let initialLocation else { return }
        if hypot(location.x - initialLocation.x, location.y - initialLocation.y) > Self.animation.allowableMovement
            || view?.bounds.contains(location) == false {
            cancelTracking()
        }
    }

    func endTracking() {
        guard initialLocation != nil, state == .possible else { return }
        stopTracking()
        state = .recognized
        onTap?()
    }

    func cancelTracking() {
        guard initialLocation != nil else { return }
        stopTracking()
        if state == .possible { state = .failed }
    }

    private func stopTracking() {
        delayTimer?.invalidate()
        delayTimer = nil
        initialLocation = nil
        if isPressed { isPressed = false; onPress?(false) }
    }
}
