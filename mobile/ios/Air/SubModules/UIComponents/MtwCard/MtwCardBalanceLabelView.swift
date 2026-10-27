import CoreText
import SwiftUI
import UIKit
import WalletCore
import WalletContext

@MainActor
private struct BalanceLabelState: Equatable {
    var balance: BaseCurrencyAmount?
    var style: MtwCardBalanceView.Style = .homeCard
    var secondaryOpacity: CGFloat = 0.75
    var animates = false
    var usesCardGradient = true
    var flatCardColor: UIColor?
    var transitionGeneration = 0
    var attributedText: NSAttributedString {
        let color: UIColor = usesCardGradient ? flatCardColor ?? .white : .label
        return balance?.formatAttributed(
            format: .init(preset: .baseCurrencyEquivalentWithMinimumFractionDigits, roundHalfUp: true),
            integerFont: style.integerFont,
            fractionFont: style.fractionFont,
            symbolFont: style.symbolFont,
            integerColor: usesCardGradient ? color : style.integerColor ?? color,
            fractionColor: (usesCardGradient ? color : style.fractionColor ?? color).withAlphaComponent(secondaryOpacity),
            symbolColor: (usesCardGradient ? color : style.symbolColor ?? color).withAlphaComponent(secondaryOpacity)
        ) ?? NSAttributedString()
    }

    var textSize: CGSize {
        CGSize(width: ceil(attributedText.size().width), height: style.integerFont.lineHeight)
    }
}

// Only the attributed numeric text participates in SwiftUI layout and transitions.
private struct BalanceLabel: View {
    let state: BalanceLabelState
    var body: some View {
        let text = state.attributedText
        Text(text)
            .id(state.transitionGeneration)
            .contentTransition(state.animates ? .numericText() : .identity)
            .environment(\.contentTransitionAddsDrawingGroup, state.animates)
            .lineLimit(1)
            .environment(\.layoutDirection, .leftToRight)
            .fixedSize()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(state.animates ? .default : nil, value: state.balance)
            .transaction { if !state.animates { $0.disablesAnimations = true } }
    }
}

public final class MtwCardBalanceLabelView: MtwCardTapView {
    private var labelState = BalanceLabelState()
    private var renderedLabelState: BalanceLabelState?
    private var renderedTextSize: CGSize = .zero
    private var label: HostingView?
    private let tintedContent = UIView()
    private let snapshotContent = UIView()
    private let gradient = MtwCardForegroundView(style: .balance)
    private let placeholder = UIView()
    private let revealHint = UIImageView(image: .airBundle("HomeHide"))
    private var shyMask: ShyMask?
    private var deferred = ScrollDeferredValue<BaseCurrencyAmount?>(nil)
    private var isConfigured = false
    private var wasScrolling = false
    private var balanceIsMasked = false
    private var concealment = CardBalanceConcealment.mask
    private let dust = CardSpoilerDustView(frame: .zero)
    private let privacyTransition = CardPrivacyTransition()
    let elementTransition = CardElementTransition()
    private var particleEffectChanged = false
    private var privacyAnimationRequested = true
    public private(set) var numericTransitionCount = 0
    private(set) var hostingConfigurationUpdateCount = 0
    public var displayedBalance: BaseCurrencyAmount? { deferred.displayed }
    public var lineHeight: CGFloat { labelState.style.integerFont.lineHeight }

    public func alignmentFrame(for balance: BaseCurrencyAmount?, style: MtwCardBalanceView.Style, isHidden: Bool) -> CGRect {
        guard let balance, !isHidden else { return bounds }
        return fittedTextFrame(size: BalanceLabelState(balance: balance, style: style).textSize)
    }

    private func fittedTextFrame(size: CGSize) -> CGRect {
        let scale = min(1, max(0.1, bounds.width / max(1, size.width)))
        let size = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(x: bounds.midX - size.width / 2,
                      y: bounds.midY - size.height / 2 - 1 / max(1, traitCollection.displayScale),
                      width: size.width, height: size.height)
    }

    public init() {
        super.init(frame: .zero)
        isAccessibilityElement = true
        accessibilityTraits = .button
        addSubview(tintedContent)
        tintedContent.isUserInteractionEnabled = false
        tintedContent.addSubview(snapshotContent)
        snapshotContent.layer.compositingFilter = "normalBlendMode"
        gradient.layer.compositingFilter = "sourceAtop"
        snapshotContent.addSubview(gradient)
        placeholder.layer.cornerRadius = 12
        placeholder.layer.cornerCurve = .continuous
        placeholder.isUserInteractionEnabled = false
        snapshotContent.insertSubview(placeholder, belowSubview: gradient)
        revealHint.contentMode = .scaleAspectFit
        revealHint.alpha = 0.5
        revealHint.isUserInteractionEnabled = false
        addSubview(revealHint)
        dust.accessibilityIdentifier = "balanceSpoilerDust"
        addSubview(dust)
        setParticleSettings(.hero)
        setPrivacyAnimationActive(true)
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public func configure(balance: BaseCurrencyAmount?, style: MtwCardBalanceView.Style, nft: ApiNft?,
                          usesCardGradient: Bool, isHidden: Bool, isScrolling: Bool,
                          animates: Bool, concealment: CardBalanceConcealment = .particles) {
        let usesElements = concealment == .particles && dust.settings.effect == .disintegrate
        defer { particleEffectChanged = false }
        let previousConcealment = self.concealment
        self.concealment = concealment
        let wasLoaded = deferred.displayed != nil
        let first = !isConfigured
        isConfigured = true
        if first { deferred = ScrollDeferredValue(balance) }
        let changed = deferred.update(balance, isScrolling: isScrolling)
        var nextLabelState = labelState
        if first { nextLabelState.transitionGeneration += 1 }
        if isScrolling && !wasScrolling && labelState.animates {
            // Discard an in-flight numeric transition when a gesture interrupts it.
            nextLabelState.transitionGeneration += 1
        }
        wasScrolling = isScrolling
        let shouldAnimate = !first && !balanceIsMasked && changed && animates && !isScrolling && !isHidden
            && AppStorageHelper.animations && !UIAccessibility.isReduceMotionEnabled
        if shouldAnimate, labelState.balance != nil, deferred.displayed != nil { numericTransitionCount += 1 }
        if changed || first || isScrolling || !animates || isHidden { nextLabelState.animates = shouldAnimate }
        nextLabelState.style = style
        nextLabelState.usesCardGradient = usesCardGradient
        let flatCardColor: UIColor? = nft?.metadata?.mtwCardType?.isPremium == true ? nil
            : (nft?.metadata?.mtwCardTextType == .dark ? UIColor(hex: "2F3241") : .white)
        nextLabelState.flatCardColor = usesCardGradient ? flatCardColor : nil
        nextLabelState.secondaryOpacity = usesCardGradient && nft?.metadata?.mtwCardType?.isPremium != true ? 0.75 : 1
        nextLabelState.balance = deferred.displayed
        labelState = nextLabelState
        gradient.configure(nft: nft)
        let needsGradient = usesCardGradient && (flatCardColor == nil || isHidden)
        gradient.isHidden = !needsGradient
        snapshotContent.layer.compositingFilter = needsGradient ? "normalBlendMode" : nil
        let masked = isHidden && deferred.displayed != nil
        let visibilityChanged = wasLoaded != (deferred.displayed != nil) || balanceIsMasked != masked || previousConcealment != concealment
        let updateVisibility = {
            // Hidden balances still track the latest value, but need no SwiftUI text or layout.
            // Render inside the privacy transition so its outgoing snapshot stays masked.
            if !isHidden { self.updateLabel(nextLabelState) }
            if concealment != .particles || self.deferred.displayed == nil {
                self.privacyTransition.reset()
                self.elementTransition.reset()
                self.tintedContent.isHidden = false
                self.label?.isHidden = isHidden || self.deferred.displayed == nil
            }
            if concealment == .particles, self.deferred.displayed != nil {
                if usesElements {
                    self.privacyTransition.reset()
                    self.label?.isHidden = false
                } else {
                    self.elementTransition.reset()
                    self.tintedContent.isHidden = false
                }
            }
            self.placeholder.isHidden = self.deferred.displayed != nil
            self.balanceIsMasked = masked
            self.updateMask(style: style)
            self.setNeedsLayout()
        }
        if concealment == .mask, previousConcealment == .mask,
           !first, visibilityChanged, animates, !isScrolling, window != nil,
           AppStorageHelper.animations, !UIAccessibility.isReduceMotionEnabled {
            UIView.transition(with: self, duration: 0.25,
                              options: [.transitionCrossDissolve, .beginFromCurrentState, .allowUserInteraction]) {
                // Only crossfade the snapshots; newly inserted masks must not grow from a zero frame.
                UIView.performWithoutAnimation {
                    updateVisibility()
                    self.layoutIfNeeded()
                }
            }
        } else {
            updateVisibility()
        }
        if concealment == .particles, !usesElements, let label, deferred.displayed != nil {
            layoutIfNeeded()
            privacyTransition.setConcealed(masked, in: label,
                animated: !particleEffectChanged && !first && animates && !isScrolling && previousConcealment == concealment)
        }
        if usesCardGradient, flatCardColor == nil {
            dust.setGradient(MtwCardForegroundView.colors(for: nft))
        } else {
            dust.setColor(usesCardGradient ? flatCardColor ?? .white : .label)
        }
        if usesElements, deferred.displayed != nil {
            layoutIfNeeded()
            elementTransition.setConcealed(masked, in: tintedContent, snapshotSource: snapshotContent, dust: dust,
                animated: !particleEffectChanged && !first && animates && !isScrolling && previousConcealment == concealment)
        } else {
            dust.setConcealed(masked && concealment == .particles,
                animated: !particleEffectChanged && !first && animates && !isScrolling && previousConcealment == concealment)
        }
        isAccessibilityElement = deferred.displayed != nil
        placeholder.backgroundColor = (usesCardGradient ? UIColor.white : .label).withAlphaComponent(0.06)
        accessibilityLabel = balanceIsMasked ? lang("Tap to reveal") : deferred.displayed?.formatted(.baseCurrencyEquivalentWithMinimumFractionDigits)
        accessibilityHint = balanceIsMasked ? nil : lang("Hide Sensitive Data")
        setNeedsLayout()
    }

    private func updateLabel(_ state: BalanceLabelState) {
        guard renderedLabelState != state || label == nil else { return }
        guard state.balance != nil else { return }
        renderedLabelState = state
        renderedTextSize = state.textSize
        hostingConfigurationUpdateCount += 1
        if let label {
            label.contentView.configuration = UIHostingConfiguration {
                BalanceLabel(state: state)
            }.margins(.all, 0)
        } else {
            let label = HostingView { BalanceLabel(state: state) }
            label.translatesAutoresizingMaskIntoConstraints = true
            label.isUserInteractionEnabled = false
            label.accessibilityElementsHidden = true
            snapshotContent.insertSubview(label, belowSubview: gradient)
            self.label = label
        }
    }

    private func updateMask(style: MtwCardBalanceView.Style) {
        if balanceIsMasked && concealment == .mask {
            if shyMask?.cellSize != style.sensitiveDataCellSize {
                shyMask?.removeFromSuperview()
                shyMask = nil
            }
            if shyMask == nil {
                let mask = ShyMask(cols: 14, rows: 3, cellSize: style.sensitiveDataCellSize, theme: style.sensitiveDataTheme)
                mask.isUserInteractionEnabled = false
                mask.layer.cornerRadius = 12
                mask.clipsToBounds = true
                snapshotContent.insertSubview(mask, belowSubview: gradient)
                NSLayoutConstraint.activate([
                    mask.centerXAnchor.constraint(equalTo: tintedContent.centerXAnchor),
                    mask.centerYAnchor.constraint(equalTo: tintedContent.centerYAnchor),
                ])
                shyMask = mask
            }
        } else {
            shyMask?.removeFromSuperview()
            shyMask = nil
        }
        revealHint.isHidden = !balanceIsMasked || concealment == .particles
        revealHint.tintColor = style.sensitiveDataTheme.color
    }

    public func prepareForReuse() {
        setPrivacyAnimationActive(false)
        isConfigured = false
        wasScrolling = false
        numericTransitionCount = 0
        deferred = ScrollDeferredValue(nil)
        shyMask?.removeFromSuperview()
        shyMask = nil
        elementTransition.reset()
        tintedContent.isHidden = false
        dust.reset()
        privacyTransition.reset()
        balanceIsMasked = false
    }

    func setParticleSettings(_ settings: CardParticleSettings) {
        if dust.settings.effect != settings.effect {
            particleEffectChanged = true
            elementTransition.reset(); privacyTransition.reset(); tintedContent.isHidden = false
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
        privacyTransition.nextOrigin = point
        elementTransition.nextOrigin = point
        dust.nextOrigin = dust.convert(point, from: self)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        tintedContent.frame = bounds
        snapshotContent.frame = tintedContent.bounds
        // The former source-atop gradient included 40 pt padding on every edge.
        gradient.frame = bounds.insetBy(dx: -40, dy: -40)
        if let label {
            // Fit the host explicitly so the card transition can use the same
            // geometry as the displayed text, including horizontal shrinking.
            let frame = fittedTextFrame(size: renderedTextSize)
            let scale = frame.height / max(1, renderedTextSize.height)
            label.bounds = CGRect(origin: .zero, size: renderedTextSize)
            label.center = CGPoint(x: frame.midX, y: frame.midY)
            label.transform = CGAffineTransform(scaleX: scale, y: scale)
        }
        if label?.isHidden == false { label?.layoutIfNeeded() }
        let style = labelState.style
        let font = style.integerFont as CTFont
        var character: UniChar = 0x30
        var glyph = CGGlyph()
        CTFontGetGlyphsForCharacters(font, &character, &glyph, 1)
        let ink = CTFontGetBoundingRectsForGlyphs(font, .horizontal, &glyph, nil, 1)
        placeholder.frame = CGRect(x: bounds.midX - 60, y: (bounds.height - lineHeight) / 2 + style.integerFont.ascender - ink.maxY,
                                   width: 120, height: ink.height)
        let cell = style.sensitiveDataCellSize
        revealHint.bounds.size = CGSize(width: cell * 1.5, height: cell * 1.5)
        revealHint.center = CGPoint(x: bounds.midX, y: bounds.midY)
        dust.frame = bounds.insetBy(dx: -80, dy: -80)
        dust.gradientFrame = dust.convert(gradient.frame, from: tintedContent)
        // Use the production mask width. Neither the number of digits nor text
        // autoshrinking may reveal the amount through the concealed field's size.
        let fieldWidth = min(bounds.width, 14 * cell)
        let field = CGRect(x: bounds.midX - fieldWidth / 2,
                           y: placeholder.frame.minY - 1 / max(1, traitCollection.displayScale) - 1,
                           width: fieldWidth, height: ink.height + 2)
        dust.fieldRect = dust.convert(field, from: self)
    }
}
