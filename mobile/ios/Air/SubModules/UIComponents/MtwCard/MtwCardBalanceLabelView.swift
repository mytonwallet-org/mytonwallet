import CoreText
import SwiftUI
import UIKit
import WalletContext
import WalletCore

@MainActor
private struct BalanceLabelState: Equatable {
    var balance: BaseCurrencyAmount?
    var style: MtwCardBalanceView.Style = .homeCard
    var secondaryOpacity: CGFloat = 0.75
    var animates = false
    var usesCardGradient = true
    var flatCardColor: UIColor?
    var transitionGeneration = 0
}

// Only the attributed numeric text participates in SwiftUI layout and transitions.
private struct BalanceLabel: View {
    let state: BalanceLabelState
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let style = state.style
        let color: UIColor = state.usesCardGradient ? state.flatCardColor ?? .white : .label
        let text = state.balance?.formatAttributed(
            format: .init(preset: .baseCurrencyEquivalentWithMinimumFractionDigits, roundHalfUp: true),
            integerFont: style.integerFont,
            fractionFont: style.fractionFont,
            symbolFont: style.symbolFont,
            integerColor: state.usesCardGradient ? color : style.integerColor ?? color,
            fractionColor: (state.usesCardGradient ? color : style.fractionColor ?? color).withAlphaComponent(state.secondaryOpacity),
            symbolColor: (state.usesCardGradient ? color : style.symbolColor ?? color).withAlphaComponent(state.secondaryOpacity)
        ) ?? NSAttributedString()
        Text(text)
            .id(state.transitionGeneration)
            .contentTransition(state.animates ? .numericText() : .identity)
            .environment(\.contentTransitionAddsDrawingGroup, state.animates)
            .lineLimit(1)
            .minimumScaleFactor(0.1)
            .environment(\.layoutDirection, .leftToRight)
            .frame(minWidth: 14 * style.sensitiveDataCellSize)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .offset(y: -1 / displayScale)
            .animation(state.animates ? .default : nil, value: state.balance)
            .transaction { if !state.animates { $0.disablesAnimations = true } }
    }
}

public final class MtwCardBalanceLabelView: MtwCardTapView {
    private var labelState = BalanceLabelState()
    private var renderedLabelState: BalanceLabelState?
    private var label: HostingView?
    private let tintedContent = UIView()
    private let gradient = MtwCardForegroundView(style: .balance)
    private let placeholder = UIView()
    private let revealHint = UIImageView(image: .airBundle("HomeHide"))
    private var shyMask: ShyMask?
    private var deferred = ScrollDeferredValue<BaseCurrencyAmount?>(nil)
    private var isConfigured = false
    private var wasScrolling = false
    private var balanceIsMasked = false
    public private(set) var numericTransitionCount = 0
    private(set) var hostingConfigurationUpdateCount = 0
    public var displayedBalance: BaseCurrencyAmount? { deferred.displayed }
    public var lineHeight: CGFloat { labelState.style.integerFont.lineHeight }

    public init() {
        super.init(frame: .zero)
        isAccessibilityElement = true
        accessibilityTraits = .button
        addSubview(tintedContent)
        tintedContent.isUserInteractionEnabled = false
        tintedContent.layer.compositingFilter = "normalBlendMode"
        gradient.layer.compositingFilter = "sourceAtop"
        tintedContent.addSubview(gradient)
        placeholder.layer.cornerRadius = 12
        placeholder.layer.cornerCurve = .continuous
        placeholder.isUserInteractionEnabled = false
        tintedContent.insertSubview(placeholder, belowSubview: gradient)
        revealHint.contentMode = .scaleAspectFit
        revealHint.alpha = 0.5
        revealHint.isUserInteractionEnabled = false
        addSubview(revealHint)
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public func configure(balance: BaseCurrencyAmount?, style: MtwCardBalanceView.Style, nft: ApiNft?,
                          usesCardGradient: Bool, isHidden: Bool, isScrolling: Bool,
                          animates: Bool) {
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
        tintedContent.layer.compositingFilter = needsGradient ? "normalBlendMode" : nil
        let masked = isHidden && deferred.displayed != nil
        let visibilityChanged = wasLoaded != (deferred.displayed != nil) || balanceIsMasked != masked
        let updateVisibility = {
            // Hidden balances still track the latest value, but need no SwiftUI text or layout.
            // Render inside the privacy transition so its outgoing snapshot stays masked.
            if !isHidden { self.updateLabel(nextLabelState) }
            self.label?.isHidden = isHidden || self.deferred.displayed == nil
            self.placeholder.isHidden = self.deferred.displayed != nil
            self.balanceIsMasked = masked
            self.updateMask(style: style)
            self.setNeedsLayout()
        }
        if !first, visibilityChanged, animates, !isScrolling, window != nil,
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
            tintedContent.insertSubview(label, belowSubview: gradient)
            self.label = label
        }
    }

    private func updateMask(style: MtwCardBalanceView.Style) {
        if balanceIsMasked {
            if shyMask?.cellSize != style.sensitiveDataCellSize {
                shyMask?.removeFromSuperview()
                shyMask = nil
            }
            if shyMask == nil {
                let mask = ShyMask(cols: 14, rows: 3, cellSize: style.sensitiveDataCellSize, theme: style.sensitiveDataTheme)
                mask.isUserInteractionEnabled = false
                mask.layer.cornerRadius = 12
                mask.clipsToBounds = true
                tintedContent.insertSubview(mask, belowSubview: gradient)
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
        revealHint.isHidden = !balanceIsMasked
        revealHint.tintColor = style.sensitiveDataTheme.color
    }

    public func prepareForReuse() {
        isConfigured = false
        wasScrolling = false
        numericTransitionCount = 0
        deferred = ScrollDeferredValue(nil)
        shyMask?.removeFromSuperview()
        shyMask = nil
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        tintedContent.frame = bounds
        // The former source-atop gradient included 40 pt padding on every edge.
        gradient.frame = bounds.insetBy(dx: -40, dy: -40)
        label?.frame = bounds
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
    }
}
