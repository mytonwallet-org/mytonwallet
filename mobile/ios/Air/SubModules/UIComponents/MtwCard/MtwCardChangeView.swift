import UIKit
import WalletCore
import WalletContext

public final class MtwCardChangeView: MtwCardTapView {
    public enum Style { case card, plainBackground }
    public var onOpenPortfolio: (() -> Void)?
    private let pill = UIView()
    private let blur = BackgroundBlurView(radius: 12)
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
    private var animates = true
    private var theme: ShyMask.Theme = .light

    public init() {
        super.init(frame: .zero)
        isAccessibilityElement = true
        accessibilityTraits = .button
        addSubview(pill)
        pill.isUserInteractionEnabled = false
        pill.addSubview(blur)
        pill.addSubview(fill)
        pill.addSubview(label)
        pill.addSubview(chevron)
        blur.clipsToBounds = true
        blur.layer.cornerRadius = 13
        blur.layer.cornerCurve = .continuous
        fill.layer.cornerRadius = 13
        fill.layer.cornerCurve = .continuous
        label.font = UIFont(name: "SFCompactDisplay-Medium", size: 17)!
        label.semanticContentAttribute = .forceLeftToRight
        chevron.image = UIImage(systemName: "chevron.forward", withConfiguration: UIImage.SymbolConfiguration(font: WTypography.uiFont(.caption2Strong, content: .technical)))
        chevron.contentMode = .center
        addSubview(placeholder)
        placeholder.layer.cornerRadius = 13
        placeholder.layer.cornerCurve = .continuous
        placeholder.isUserInteractionEnabled = false
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
                          nft: ApiNft?, style: Style = .card, isHidden: Bool, animates: Bool = true) {
        let nextText = Self.text(balance: balance, previous: previous, percent: percent)
        let contentChanged = text != nextText || globallyHidden != isHidden
        let wasConfigured = configured
        configured = true
        self.animates = animates
        let positive = balance != nil && previous != nil && balance!.amount > 0 && previous!.amount > 0 && balance!.amount > previous!.amount
        let secondary = UIColor(getSecondaryForegroundColor(nft: nft))
        let usesPositive = positive && (style == .plainBackground || nft == nil)
        let color: UIColor = style == .card
            ? (usesPositive ? .air.positiveBalance : secondary)
            : (usesPositive ? UIColor(hex: "34C759") : .air.secondaryLabel)
        updateContent(animated: wasConfigured && contentChanged) {
            self.text = nextText
            self.label.text = nextText
            self.label.textColor = color.withAlphaComponent(style == .card && !usesPositive ? 0.8 : 1)
            self.chevron.tintColor = self.label.textColor
            self.fill.backgroundColor = color.withAlphaComponent(style == .card && usesPositive ? 0.16 : 0.10)
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
        if animated, animates, window != nil, AppStorageHelper.animations, !UIAccessibility.isReduceMotionEnabled {
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
    }

    private func updateVisibility() {
        let hasText = text?.isEmpty == false
        let masked = hasText && globallyHidden && !locallyRevealed
        pill.isHidden = !hasText || masked
        placeholder.isHidden = text != nil
        if masked {
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
        accessibilityHint = masked ? nil : lang("Portfolio")
        isUserInteractionEnabled = hasText
    }

    private func activate() {
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

    public func prepareForReuse() {
        configured = false
        revealReset?.cancel()
        revealReset = nil
        locallyRevealed = false
        shyMask?.removeFromSuperview()
        shyMask = nil
        onOpenPortfolio = nil
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let size = label.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: 26))
        let iconSize = chevron.image?.size ?? .zero
        let width = size.width + 4 + iconSize.width + 16
        pill.frame = CGRect(x: (bounds.width - width) / 2, y: (bounds.height - 26) / 2, width: width, height: 26)
        blur.frame = pill.bounds
        fill.frame = pill.bounds
        let rtl = effectiveUserInterfaceLayoutDirection == .rightToLeft
        label.frame = CGRect(x: rtl ? 8 + iconSize.width + 4 : 8, y: (26 - size.height) / 2 - 0.5, width: size.width, height: size.height)
        chevron.frame = CGRect(x: rtl ? 8 : 8 + size.width + 4, y: (26 - iconSize.height) / 2, width: iconSize.width, height: iconSize.height)
        let scale = max(traitCollection.displayScale, 1)
        chevron.frame.origin.y = (chevron.frame.origin.y * scale).rounded() / scale
        chevron.transform = CGAffineTransform(scaleX: rtl ? -1 : 1, y: 1)
        placeholder.frame = CGRect(x: bounds.midX - 38, y: bounds.midY - 13, width: 76, height: 26)
    }
}
