import UIKit
import WalletCore
import WalletContext

public final class MtwCardChangeView: MtwCardTapView {
    public enum Style { case card, plainBackground }
    public var onOpenPortfolio: (() -> Void)?
    private let pill = UIView()
    private let pillVisibility = UIView()
    private let background = CardBadgeBackground(cornerRadius: 13)
    private let fill = UIView()
    private let label = UILabel()
    private let chevron = UIImageView()
    private let placeholder = UIView()
    private var shyMask: ShyMask?
    private var globallyHidden = false
    private var locallyRevealed = false
    private var revealReset: Task<Void, Never>?
    private var text: String?
    private var configured = false
    private var showsChevron = true
    private var pillHeight: CGFloat = 26
    private var animates = true
    private var theme: ShyMask.Theme = .light
    private var style: Style = .card
    private var materialTilt = CGPoint.zero
    private var materialEmboss: CGFloat?
    private var concealment = CardBalanceConcealment.mask
    private let dust = CardSpoilerDustView(frame: .zero)
    private let privacyTransition = CardPrivacyTransition()
    let elementTransition = CardElementTransition()
    private var particleEffectChanged = false
    private var privacyAnimationRequested = true

    public init() {
        super.init(frame: .zero)
        isAccessibilityElement = true
        accessibilityTraits = .button
        addSubview(pillVisibility)
        pillVisibility.addSubview(pill)
        pill.isUserInteractionEnabled = false
        pill.addSubview(background)
        pill.addSubview(fill)
        pill.addSubview(label)
        pill.addSubview(chevron)
        fill.layer.cornerRadius = 13
        fill.layer.cornerCurve = .continuous
        label.applyTextStyle(.bodyEmphasized)
        label.semanticContentAttribute = .forceLeftToRight
        chevron.image = UIImage(systemName: "chevron.forward", withConfiguration: UIImage.SymbolConfiguration(font: WTypography.uiFont(.caption2Strong, content: .technical)))
        chevron.contentMode = .center
        addSubview(placeholder)
        placeholder.layer.cornerRadius = 13
        placeholder.layer.cornerCurve = .continuous
        placeholder.isUserInteractionEnabled = false
        dust.accessibilityIdentifier = "portfolioSpoilerDust"
        addSubview(dust)
        setParticleSettings(.hero)
        setPrivacyAnimationActive(true)
        onTap = { [weak self] in self?.activate() }
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public static func text(balance: BaseCurrencyAmount?, previous: BaseCurrencyAmount?, percent: Double?) -> String? {
        guard let balance else { return nil }
        guard let previous, balance.amount > 0, previous.amount > 0 else { return "" }
        let change = BaseCurrencyAmount(balance.amount - previous.amount, balance.baseCurrency)
        let prefix = percent.map { "\(formatPercent($0)) · " } ?? ""
        return prefix + change.formatted(.baseCurrencyEquivalent, showMinus: false)
    }

    public func configure(balance: BaseCurrencyAmount?, previous: BaseCurrencyAmount?, percent: Double?,
                          nft: ApiNft?, style: Style = .card, isHidden: Bool, animates: Bool = true,
                          concealment: CardBalanceConcealment = .particles) {
        let nextText = Self.text(balance: balance, previous: previous, percent: percent)
        let positive = balance != nil && previous != nil && balance!.amount > 0 && previous!.amount > 0 && balance!.amount > previous!.amount
        let secondary = UIColor(getSecondaryForegroundColor(nft: nft))
        let usesPositive = positive && (style == .plainBackground || nft == nil)
        let color: UIColor = style == .card
            ? (usesPositive ? .air.positiveBalance : secondary)
            : (usesPositive ? UIColor(hex: "34C759") : .air.secondaryLabel)
        configureContent(text: nextText, color: color, secondary: secondary, style: style,
                         foregroundOpacity: style == .card && !usesPositive ? 0.8 : 1,
                         backgroundOpacity: style == .card && usesPositive ? 0.16 : 0.10,
                         showsChevron: true, height: 26, isHidden: isHidden, animates: animates, concealment: concealment)
    }

    /// Reuses the Home change pill and privacy effects for a caller-supplied change value.
    public func configure(text: String?, color: UIColor, backgroundOpacity: CGFloat = 0.10,
                          height: CGFloat = 26, isHidden: Bool, animates: Bool = true,
                          concealment: CardBalanceConcealment = .particles) {
        configureContent(text: text, color: color, secondary: .air.secondaryLabel, style: .plainBackground,
                         foregroundOpacity: 1, backgroundOpacity: backgroundOpacity, showsChevron: false,
                         height: height, isHidden: isHidden, animates: animates, concealment: concealment)
    }

    private func configureContent(text nextText: String?, color: UIColor, secondary: UIColor, style: Style,
                                  foregroundOpacity: CGFloat, backgroundOpacity: CGFloat, showsChevron: Bool,
                                  height: CGFloat, isHidden: Bool, animates: Bool, concealment: CardBalanceConcealment) {
        defer { particleEffectChanged = false }
        let previousConcealment = self.concealment
        self.concealment = concealment
        let contentChanged = text != nextText || globallyHidden != isHidden || previousConcealment != concealment
        let wasConfigured = configured
        configured = true
        self.animates = animates
        self.style = style
        self.showsChevron = showsChevron
        self.pillHeight = height
        chevron.isHidden = !showsChevron
        fill.layer.cornerRadius = height / 2
        label.applyTextStyle(.bodyEmphasized)
        setMaterialLight(tilt: materialTilt, emboss: materialEmboss)
        updateContent(animated: wasConfigured && contentChanged && previousConcealment == concealment) {
            self.text = nextText
            self.label.text = nextText
            self.label.textColor = color.withAlphaComponent(foregroundOpacity)
            self.dust.setColor(color)
            self.chevron.tintColor = self.label.textColor
            self.fill.backgroundColor = color.withAlphaComponent(backgroundOpacity)
            self.placeholder.backgroundColor = (style == .card ? UIColor.white : .label).withAlphaComponent(0.06)
            self.theme = style == .card ? .color(secondary) : .adaptive
            if self.globallyHidden != isHidden {
                self.globallyHidden = isHidden
                self.locallyRevealed = false
                self.revealReset?.cancel()
            }
        }
    }

    private func updateContent(animated: Bool, changes: @escaping () -> Void) {
        let updates = {
            changes()
            self.updateVisibility()
            self.setNeedsLayout()
        }
        if concealment == .mask, animated, animates, window != nil, AppStorageHelper.animations, !UIAccessibility.isReduceMotionEnabled {
            UIView.transition(with: self, duration: 0.25,
                              options: [.transitionCrossDissolve, .beginFromCurrentState, .allowUserInteraction]) {
                UIView.performWithoutAnimation {
                    updates()
                    self.layoutIfNeeded()
                }
            }
        } else {
            updates()
        }
        if concealment == .particles, text?.isEmpty == false {
            layoutIfNeeded()
            if dust.settings.effect == .disintegrate {
                privacyTransition.reset()
                elementTransition.setConcealed(globallyHidden && !locallyRevealed, in: pillVisibility, snapshotSource: pill, dust: dust,
                    animated: !particleEffectChanged && animated && animates)
            } else {
                elementTransition.reset()
                pillVisibility.isHidden = false
                privacyTransition.setConcealed(globallyHidden && !locallyRevealed, in: pill,
                    animated: !particleEffectChanged && animated && animates)
            }
        }
        if concealment != .particles || dust.settings.effect != .disintegrate || text?.isEmpty != false {
            dust.setConcealed(text?.isEmpty == false && globallyHidden && !locallyRevealed && concealment == .particles,
                              animated: !particleEffectChanged && animated && animates && concealment == .particles)
        }
    }

    private func updateVisibility() {
        let hasText = text?.isEmpty == false
        let masked = hasText && globallyHidden && !locallyRevealed
        if concealment != .particles || !hasText {
            privacyTransition.reset()
            elementTransition.reset()
            pillVisibility.isHidden = false
        }
        if concealment != .particles || !hasText || dust.settings.effect == .disintegrate {
            pill.isHidden = !hasText || (masked && concealment != .particles)
        }
        placeholder.isHidden = text != nil
        if masked && concealment == .mask {
            if shyMask == nil {
                let mask = ShyMask(cols: 10, rows: 2, cellSize: 13, theme: theme)
                mask.layer.cornerRadius = 13
                mask.clipsToBounds = true
                mask.isUserInteractionEnabled = false
                addSubview(mask)
                NSLayoutConstraint.activate([
                    mask.centerXAnchor.constraint(equalTo: centerXAnchor),
                    mask.centerYAnchor.constraint(equalTo: centerYAnchor),
                ])
                shyMask = mask
            }
            shyMask?.setTheme(theme)
        } else {
            shyMask?.removeFromSuperview()
            shyMask = nil
        }
        isAccessibilityElement = hasText
        accessibilityLabel = masked ? lang("Tap to reveal") : text
        accessibilityTraits = masked || showsChevron ? .button : .staticText
        accessibilityHint = !masked && showsChevron ? lang("Portfolio") : nil
        isUserInteractionEnabled = hasText
    }

    private func activate() {
        preparePrivacyTransition(at: lastTapLocation ?? CGPoint(x: bounds.midX, y: bounds.midY))
        if globallyHidden && !locallyRevealed {
            updateContent(animated: true) { self.locallyRevealed = true }
            revealReset?.cancel()
            revealReset = Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                guard let self else { return }
                updateContent(animated: true) { self.locallyRevealed = false }
            }
        } else {
            onOpenPortfolio?()
        }
    }

    /// Keep the portfolio tint and glyphs separate from the moving glass lighting.
    public func setMaterialLight(tilt: CGPoint, emboss: CGFloat?) {
        materialTilt = tilt
        materialEmboss = emboss
        background.setMaterialLight(tilt: tilt, emboss: style == .card ? emboss : nil)
    }

    public func prepareForReuse() {
        setPrivacyAnimationActive(false)
        setMaterialLight(tilt: .zero, emboss: nil)
        configured = false
        revealReset?.cancel()
        revealReset = nil
        locallyRevealed = false
        shyMask?.removeFromSuperview()
        shyMask = nil
        onOpenPortfolio = nil
        elementTransition.reset()
        dust.reset()
        privacyTransition.reset()
    }

    func setParticleSettings(_ settings: CardParticleSettings) {
        if dust.settings.effect != settings.effect {
            particleEffectChanged = true
            elementTransition.reset(); privacyTransition.reset()
        }
        dust.settings = settings; elementTransition.settings = settings
    }

    public func setPrivacyAnimationActive(_ requested: Bool) {
        privacyAnimationRequested = requested
        let active = requested && window != nil
        dust.animationActive = active; privacyTransition.active = active; elementTransition.active = active
    }
    public override func didMoveToWindow() {
        super.didMoveToWindow()
        setPrivacyAnimationActive(privacyAnimationRequested)
    }
    public func setParticleInteractionPoint(_ point: CGPoint?, from view: UIView) {
        dust.setInteractionPoint(point.map { dust.convert($0, from: view) })
    }
    public func preparePrivacyTransition(at point: CGPoint) {
        layoutIfNeeded()
        privacyTransition.nextOrigin = pill.convert(point, from: self)
        elementTransition.nextOrigin = pill.convert(point, from: self)
        dust.nextOrigin = dust.convert(point, from: self)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let size = label.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: pillHeight))
        let iconSize = showsChevron ? chevron.image?.size ?? .zero : .zero
        let accessoryWidth = showsChevron ? 4 + iconSize.width : 0
        let width = size.width + accessoryWidth + 16
        let fitScale = min(1, max(0.1, bounds.width / max(1, width)))
        pillVisibility.bounds = CGRect(x: 0, y: 0, width: width, height: pillHeight)
        pillVisibility.center = CGPoint(x: bounds.midX, y: bounds.midY)
        pillVisibility.transform = CGAffineTransform(scaleX: fitScale, y: fitScale)
        pill.frame = pillVisibility.bounds
        background.frame = pill.bounds
        fill.frame = pill.bounds
        let rtl = effectiveUserInterfaceLayoutDirection == .rightToLeft
        label.frame = CGRect(x: rtl ? 8 + accessoryWidth : 8, y: (pillHeight - size.height) / 2 - 0.5, width: size.width, height: size.height)
        chevron.frame = CGRect(x: rtl ? 8 : 8 + size.width + 4, y: (pillHeight - iconSize.height) / 2, width: iconSize.width, height: iconSize.height)
        let scale = max(traitCollection.displayScale, 1)
        chevron.frame.origin.y = (chevron.frame.origin.y * scale).rounded() / scale
        placeholder.frame = CGRect(x: bounds.midX - 38, y: bounds.midY - pillHeight / 2, width: 76, height: pillHeight)
        dust.frame = bounds.insetBy(dx: -80, dy: -80)
        let fieldWidth = min(bounds.width, 10 * 13.0)
        dust.fieldRect = dust.convert(CGRect(x: bounds.midX - fieldWidth / 2,
            y: bounds.midY - pillHeight / 2, width: fieldWidth, height: pillHeight), from: self)
    }
}
