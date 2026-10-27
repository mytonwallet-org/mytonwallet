import UIKit
import WalletContext
import WalletCore

public final class MtwCardAccountLineView: UIView {
    public let addressesButton = MtwCardTapView()
    public let saveButton = MtwCardTapView()
    private let foreground = MtwCardForegroundView()
    private let glyphs = UIView()
    private weak var nameLabel: UILabel?
    private var pieces: [Piece] = []
    private var copyFrames: [MAccount.AddressLine.Item: CGRect] = [:]
    private var configuration: Configuration?
    private var saveBackground: UIView?
    private var viewBadgeBackground: CardBadgeBackground?
    private weak var viewBadgeGlyphs: UIView?
    private var materialTilt = CGPoint.zero
    private var materialEmboss: CGFloat?
    private let saveLabel = UILabel()
    private let saveIcon = UIImageView(image: UIImage.airBundle("AddView").withRenderingMode(.alwaysTemplate))

    private struct Configuration: Equatable {
        var address: MAccount.AddressLine
        var name: String
        var showsName: Bool
        var temporary: Bool
        var nft: ApiNft?
    }

    private struct Piece {
        var view: UIView
        var size: CGSize
        var gap: CGFloat
        var offset: CGPoint = .zero
        var flexible = false
        var copyItem: MAccount.AddressLine.Item?
    }

    public init() {
        super.init(frame: .zero)
        addSubview(addressesButton)
        addSubview(saveButton)
        addressesButton.addSubview(foreground)
        foreground.mask = glyphs
        addressesButton.isAccessibilityElement = true
        addressesButton.accessibilityTraits = .button
        addressesButton.accessibilityHint = lang("Open addresses")
        if #available(iOS 18, *) {
            let gesture = UILongPressGestureRecognizer(target: self, action: #selector(copyAddress(_:)))
            gesture.minimumPressDuration = 0.25
            gesture.allowableMovement = 10
            addressesButton.addGestureRecognizer(gesture)
        }
        saveButton.accessibilityLabel = lang("$view_mode")
        saveLabel.font = WTypography.uiFont(.supportingStrong)
        saveLabel.text = lang("$view_mode")
        saveIcon.contentMode = .scaleAspectFit
        saveButton.addSubview(saveLabel)
        saveButton.addSubview(saveIcon)
        let background: UIView
        if #available(iOS 26, *) {
            let glass = UIGlassEffect(style: .clear)
            glass.isInteractive = true
            let effect = UIVisualEffectView(effect: glass)
            effect.cornerConfiguration = .capsule()
            background = effect
        } else {
            background = UIView()
            background.layer.cornerRadius = 14
            background.clipsToBounds = true
        }
        background.isUserInteractionEnabled = false
        saveButton.insertSubview(background, at: 0)
        saveBackground = background
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public func configure(address: MAccount.AddressLine, name: String, showsName: Bool, isTemporary: Bool, nft: ApiNft?) {
        let next = Configuration(address: address, name: name, showsName: showsName, temporary: isTemporary, nft: nft)
        guard configuration != next else { return }
        let animateTemporary = configuration != nil && configuration?.temporary != isTemporary
            && window != nil && AppStorageHelper.animations && !UIAccessibility.isReduceMotionEnabled
        if animateTemporary { layoutIfNeeded() }
        configuration = next
        pieces.forEach { $0.view.removeFromSuperview() }
        nameLabel = nil
        viewBadgeBackground?.removeFromSuperview()
        viewBadgeBackground = nil
        viewBadgeGlyphs = nil
        copyFrames = [:]
        pieces = []
        glyphs.subviews.forEach { $0.removeFromSuperview() }
        foreground.configure(nft: nft)
        saveButton.isHidden = !isTemporary && !animateTemporary
        if !animateTemporary { saveButton.alpha = isTemporary ? 1 : 0 }
        saveButton.tintColor = UIColor(getSecondaryForegroundColor(nft: nft))
        saveLabel.textColor = saveButton.tintColor
        if #unavailable(iOS 26) { saveBackground?.backgroundColor = saveButton.tintColor.withAlphaComponent(0.15) }
        addressesButton.accessibilityLabel = showsName ? name : address.items.first?.text
        let font = showsName ? WTypography.uiFont(.bodyStrong) : UIFont.compactDisplay(ofSize: 17, weight: .medium)
        let increasedOpacity = nft?.metadata?.mtwCardType?.isPremium == true
        if address.isTestnet { appendImage("inline_testnet", font: font, gap: 4) }
        switch address.leadingIcon {
        case .ledger:
            appendImage("LedgerBadge", alpha: increasedOpacity ? 1 : 0.75, gap: 4)
        case .view:
            appendViewBadge(increasedOpacity: increasedOpacity)
        case nil: break
        }
        if showsName {
            appendText(name, font: font, gap: 4, flexible: true, preservesColorGlyphs: true)
            appendImage("QRIcon", size: CGSize(width: 18, height: 18), alpha: 0.75, gap: 0)
        } else {
            let items = address.displayItems(maxChainCount: 1, multichainAddressCount: 1)
            for (index, item) in items.enumerated() {
                let comma = !item.item.isLast ? "," : ""
                appendImage("chain_\(item.item.chain.rawValue)", size: CGSize(width: 16, height: 16),
                            gap: item.showsAddress ? 4 : 0, monochrome: false, copyItem: item.item)
                let text = item.showsAddress
                    ? (item.item.isDomain ? item.item.text : formatStartEndAddress(item.item.text, prefix: items.count == 1 ? 6 : 0, suffix: 6)) + comma
                    : comma
                if !text.isEmpty {
                    appendText(text, font: font, gap: index == items.count - 1 ? 4 : 6,
                               flexible: item.showsAddress, copyItem: item.item)
                } else {
                    pieces[pieces.count - 1].gap = index == items.count - 1 ? 4 : 6
                }
            }
            appendImage("ArrowUpDownSmall", alpha: 0.5, gap: 0, offset: CGPoint(x: -1, y: 0.333))
        }
        setNeedsLayout()
        if animateTemporary {
            UIView.animate(withDuration: 0.5, delay: 0.18, usingSpringWithDamping: 1, initialSpringVelocity: 0,
                           options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.layoutIfNeeded()
                self.saveButton.alpha = isTemporary ? 1 : 0
            } completion: { [weak self] _ in
                guard let self else { return }
                self.saveButton.isHidden = self.configuration?.temporary != true
            }
        }
    }

    private func appendText(_ text: String, font: UIFont, gap: CGFloat, flexible: Bool = false,
                            copyItem: MAccount.AddressLine.Item? = nil, preservesColorGlyphs: Bool = false) {
        let label = UILabel()
        label.font = font
        label.text = text
        label.textColor = .white
        label.alpha = 0.75
        label.lineBreakMode = copyItem?.isDomain == true ? .byTruncatingMiddle : .byTruncatingTail
        label.allowsDefaultTighteningForTruncation = copyItem != nil
        if preservesColorGlyphs {
            addressesButton.addSubview(label)
            nameLabel = label
        } else {
            glyphs.addSubview(label)
        }
        pieces.append(Piece(view: label, size: label.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: 30)),
                            gap: gap, flexible: flexible, copyItem: copyItem))
    }

    private func appendImage(_ name: String, size: CGSize? = nil, font: UIFont? = nil, alpha: CGFloat = 1,
                             gap: CGFloat, offset: CGPoint = .zero, monochrome: Bool = true,
                             copyItem: MAccount.AddressLine.Item? = nil) {
        var image = UIImage.airBundle(name)
        if let font { image = image.withConfiguration(UIImage.SymbolConfiguration(font: font)) }
        let imageView = UIImageView(image: monochrome ? image.withRenderingMode(.alwaysTemplate) : image)
        imageView.tintColor = .white
        imageView.alpha = alpha
        imageView.contentMode = .scaleAspectFit
        (monochrome ? glyphs : addressesButton).addSubview(imageView)
        pieces.append(Piece(view: imageView, size: size ?? image.size, gap: gap, offset: offset, copyItem: copyItem))
    }

    private func appendViewBadge(increasedOpacity: Bool) {
        let badge = UIView()
        badge.alpha = increasedOpacity ? 1 : 0.75
        let fill = UIView()
        fill.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        fill.layer.cornerRadius = viewBadgeCornerRadius
        fill.layer.cornerCurve = .continuous
        let icon = UIImageView(image: UIImage.airBundle("ViewBadge").withRenderingMode(.alwaysTemplate))
        icon.tintColor = .white
        let text = UILabel()
        text.applyTextStyle(.captionStrong)
        text.textColor = .white
        text.text = lang("$view_mode")
        let textSize = text.sizeThatFits(CGSize(width: 300, height: 30))
        let iconSize = icon.image!.size
        let width = 6 + iconSize.width + 2 + textSize.width
        fill.frame = CGRect(x: 0, y: -3, width: width, height: 18)
        icon.frame = CGRect(x: 3, y: (12 - iconSize.height) / 2 + 0.334, width: iconSize.width, height: iconSize.height)
        text.frame = CGRect(x: 3 + iconSize.width + 2, y: (12 - textSize.height) / 2 - 0.333, width: textSize.width, height: textSize.height)
        [fill, icon, text].forEach(badge.addSubview)
        glyphs.addSubview(badge)
        pieces.append(Piece(view: badge, size: CGSize(width: width, height: 12), gap: 4))
        let background = CardBadgeBackground()
        background.setMaterialLight(tilt: materialTilt, emboss: materialEmboss)
        addressesButton.insertSubview(background, at: 0)
        viewBadgeBackground = background
        viewBadgeGlyphs = badge
    }

    /// Light the badge's surface, never an offset copy of its text or the address.
    /// A nil emboss removes the directional lighting while retaining the blur.
    public func setMaterialLight(tilt: CGPoint, emboss: CGFloat?) {
        materialTilt = tilt
        materialEmboss = emboss
        viewBadgeBackground?.setMaterialLight(tilt: tilt, emboss: emboss)
    }

    public func prepareForReuse() {
        configuration = nil
        copyFrames = [:]
        layer.removeAllAnimationsRecursive()
        saveButton.isHidden = true
        setMaterialLight(tilt: .zero, emboss: nil)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        guard let configuration else { return }
        saveButton.semanticContentAttribute = semanticContentAttribute
        let saveTextSize = saveLabel.sizeThatFits(CGSize(width: 200, height: 28))
        let saveIconSize = saveIcon.image?.size ?? .zero
        let naturalSaveWidth = 15 + saveIconSize.width + 2 + saveTextSize.width
        let saveWidth = configuration.temporary ? naturalSaveWidth : 0
        let gap: CGFloat = configuration.temporary ? 8 : 0
        let available = max(0, bounds.width - saveWidth - gap)
        let displayScale = max(traitCollection.displayScale, 1)
        let flexible = pieces.indices.filter { pieces[$0].flexible }.sorted { pieces[$0].size.width < pieces[$1].size.width }
        let fixedWidth = pieces.reduce(CGFloat.zero) { $0 + ($1.flexible ? 0 : $1.size.width) + $1.gap }
        var remaining = max(0, available - fixedWidth)
        var textWidths: [Int: CGFloat] = [:]
        for (offset, index) in flexible.enumerated() {
            let proposal = min(pieces[index].size.width, remaining / CGFloat(flexible.count - offset))
            let width = measuredTextWidth(pieces[index], maximum: proposal, scale: displayScale)
            textWidths[index] = width
            remaining -= width
        }
        let width = fixedWidth + textWidths.values.reduce(0, +)
        let rtl = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let start = (bounds.width - width - saveWidth - gap) / 2
        let alignedX = ((start + (rtl ? 0 : saveWidth + gap)) * displayScale).rounded() / displayScale
        addressesButton.frame = CGRect(x: alignedX, y: 0, width: width, height: bounds.height)
        saveButton.frame = CGRect(x: rtl ? start + width + gap : start, y: bounds.midY - 14, width: naturalSaveWidth, height: 28)
        saveBackground?.frame = saveButton.bounds
        saveIcon.frame = CGRect(x: rtl ? naturalSaveWidth - 7 - saveIconSize.width : 7, y: (28 - saveIconSize.height) / 2,
                                width: saveIconSize.width, height: saveIconSize.height)
        saveLabel.frame = CGRect(x: rtl ? 8 : 7 + saveIconSize.width + 2, y: (28 - saveTextSize.height) / 2,
                                 width: saveTextSize.width, height: saveTextSize.height)
        foreground.frame = addressesButton.bounds
        glyphs.frame = foreground.bounds
        var x: CGFloat = 0
        copyFrames = [:]
        for (index, piece) in pieces.enumerated() {
            let pieceWidth = textWidths[index] ?? piece.size.width
            let visualX = configuration.showsName && rtl ? width - x - pieceWidth : x
            piece.view.frame = CGRect(x: visualX + piece.offset.x, y: (bounds.height - piece.size.height) / 2 + piece.offset.y,
                                      width: pieceWidth, height: piece.size.height)
            piece.view.frame.origin.x = (piece.view.frame.origin.x * displayScale).rounded() / displayScale
            piece.view.frame.origin.y = (piece.view.frame.origin.y * displayScale).rounded() / displayScale
            if let item = piece.copyItem {
                copyFrames[item] = (copyFrames[item] ?? piece.view.frame).union(piece.view.frame)
            }
            if piece.view === viewBadgeGlyphs {
                viewBadgeBackground?.frame = piece.view.frame.insetBy(dx: 0, dy: -3)
            }
            x += pieceWidth + piece.gap
        }
        copyFrames = copyFrames.mapValues { $0.insetBy(dx: 0, dy: -8) }
        if let nameLabel {
            let rect = nameLabel.convert(nameLabel.bounds, to: foreground)
            let color = foreground.textColor(in: rect, scale: displayScale)
            if nameLabel.textColor != color { nameLabel.textColor = color }
        }
    }
    private func measuredTextWidth(_ piece: Piece, maximum: CGFloat, scale: CGFloat) -> CGFloat {
        guard let label = piece.view as? UILabel else { return maximum }
        var proposal = CGRect(x: 0, y: 0, width: ceil(maximum * scale) / scale, height: piece.size.height)
        if label.lineBreakMode == .byTruncatingTail, label.allowsDefaultTighteningForTruncation {
            // The original stack allocates a tail-truncated line's natural width
            // before tightening it. Keep that allocation when sharing space with domains.
            label.allowsDefaultTighteningForTruncation = false
            proposal.size.width = label.textRect(forBounds: proposal, limitedToNumberOfLines: 1).width
            label.allowsDefaultTighteningForTruncation = true
        }
        let rect = label.textRect(forBounds: proposal, limitedToNumberOfLines: 1)
        return min(piece.size.width, ceil(rect.width * scale) / scale)
    }

    @objc private func copyAddress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let point = gesture.location(in: addressesButton)
        guard let item = copyFrames.first(where: { $0.value.contains(point) })?.key else { return }
        UIPasteboard.general.string = item.textToCopy
        AppActions.showToast(icon: .animatedCopy, message: L10n.chainAddressCopied(chain: item.chain.title))
        Haptics.play(.lightTap)
    }
}

/// Shared glass background for the view-account and portfolio-change badges.
/// Live blur stays underneath the translucent light and rim in every motion mode;
/// only these background layers catch the light, never a copy of the glyphs.
final class CardBadgeBackground: UIView {
    private let cornerRadius: CGFloat
    private let backdrop = BackgroundBlurView(radius: 12)
    private let sheen = CAGradientLayer()
    private let rim = CAGradientLayer()
    private let rimMask = CAShapeLayer()
    private var lightTilt = CGPoint.zero
    private var lightStrength: CGFloat?

    init(cornerRadius: CGFloat = viewBadgeCornerRadius) {
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        clipsToBounds = true
        layer.cornerRadius = cornerRadius
        layer.cornerCurve = .continuous
        addSubview(backdrop)
        layer.addSublayer(sheen)
        layer.addSublayer(rim)
        rim.mask = rimMask
        rimMask.fillColor = UIColor.clear.cgColor
        rimMask.strokeColor = UIColor.white.cgColor
        for gradient in [sheen, rim] {
            gradient.locations = (0...12).map { NSNumber(value: Double($0) / 12) }
        }
        setMaterialLight(tilt: .zero, emboss: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setMaterialLight(tilt: CGPoint, emboss: CGFloat?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sheen.isHidden = emboss == nil
        rim.isHidden = emboss == nil
        lightTilt = CGPoint(x: min(1, max(-1, tilt.x)), y: min(1, max(-1, tilt.y)))
        updateLightDirection()
        let strength = min(1, max(0, emboss ?? 0))
        if lightStrength != strength {
            lightStrength = strength
            sheen.colors = lightColors(highlight: 0.025 + strength * 0.04, shadow: 0.04)
            rim.colors = lightColors(highlight: 0.10 + strength * 0.18, shadow: 0.10)
        }
        CATransaction.commit()
    }

    private func updateLightDirection() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        // Keep the light axis nonzero even at full upward tilt. Span the whole
        // badge in points, with soft falloff beyond its edges at every angle.
        let dx = lightTilt.x * 0.65
        let dy = 1 + lightTilt.y * 0.65
        let extent = 0.65 * (abs(dx) * bounds.width + dy * bounds.height) / (dx * dx + dy * dy)
        let offset = CGPoint(x: dx * extent / bounds.width, y: dy * extent / bounds.height)
        for gradient in [sheen, rim] {
            gradient.startPoint = CGPoint(x: 0.5 - offset.x, y: 0.5 - offset.y)
            gradient.endPoint = CGPoint(x: 0.5 + offset.x, y: 0.5 + offset.y)
        }
    }

    private func lightColors(highlight: CGFloat, shadow: CGFloat) -> [CGColor] {
        (0...12).map { index in
            let light = cos(CGFloat.pi * CGFloat(index) / 12)
            return (light >= 0 ? UIColor.white : UIColor.black)
                .withAlphaComponent(abs(light) * (light >= 0 ? highlight : shadow)).cgColor
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdrop.frame = bounds
        sheen.frame = bounds
        rim.frame = bounds
        rimMask.frame = bounds
        let width = 1 / max(1, traitCollection.displayScale)
        rimMask.lineWidth = width
        rimMask.path = UIBezierPath(roundedRect: bounds.insetBy(dx: width / 2, dy: width / 2),
                                   cornerRadius: max(0, cornerRadius - width / 2)).cgPath
        updateLightDirection()
        CATransaction.commit()
    }
}

public final class MtwCardCollapsedTitleView: UIView {
    private let label = UILabel()
    private let icon = UIImageView()
    public init() {
        super.init(frame: .zero)
        label.applyTextStyle(.body)
        label.textColor = .secondaryLabel
        label.lineBreakMode = .byTruncatingTail
        icon.image = UIImage.airBundle("inline_view").withConfiguration(UIImage.SymbolConfiguration(font: WTypography.uiFont(.body), scale: .small))
        icon.tintColor = .secondaryLabel
        addSubview(label)
        addSubview(icon)
        isAccessibilityElement = true
    }
    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    public func configure(name: String, isView: Bool) {
        label.text = name
        accessibilityLabel = name
        icon.isHidden = !isView
        setNeedsLayout()
    }
    public override func layoutSubviews() {
        super.layoutSubviews()
        let iconSize = icon.isHidden ? .zero : icon.image?.size ?? .zero
        let gap: CGFloat = icon.isHidden ? 0 : 4
        var size = label.sizeThatFits(CGSize(width: max(0, bounds.width - iconSize.width - gap), height: bounds.height))
        size.width = min(size.width, max(0, bounds.width - iconSize.width - gap))
        let start = (bounds.width - size.width - iconSize.width - gap) / 2
        let rtl = effectiveUserInterfaceLayoutDirection == .rightToLeft
        label.frame = CGRect(x: start + (rtl ? 0 : iconSize.width + gap), y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
        icon.frame = CGRect(x: rtl ? start + size.width + gap : start, y: (bounds.height - iconSize.height) / 2, width: iconSize.width, height: iconSize.height)
    }
}
