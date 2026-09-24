import UIKit
import UIComponents
import WalletContext
import WalletCore

final class MintCardAvailabilityView: UIView {
    private let backdrop = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let outsideLabels = UIView()
    private let insideLabels = UIView()
    private let remaining = UILabel()
    private let sold = UILabel()
    private let filledRemaining = UILabel()
    private let filledSold = UILabel()
    private let fill = CALayer()
    private let fillMask = CALayer()
    private var remainingFraction: CGFloat = 0
    private var previousFillGeometry: (bounds: CGRect, position: CGPoint)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backdrop.contentView.backgroundColor = UIColor.white.withAlphaComponent(0.16)
        clipsToBounds = true
        isAccessibilityElement = true
        addSubview(backdrop)
        addSubview(outsideLabels)
        layer.addSublayer(fill)
        addSubview(insideLabels)
        insideLabels.layer.mask = fillMask
        outsideLabels.accessibilityElementsHidden = true
        insideLabels.accessibilityElementsHidden = true
        for layer in [fill, fillMask] { layer.backgroundColor = UIColor.white.cgColor }
        for (container, labels, color) in [
            (outsideLabels, [remaining, sold], UIColor.white),
            (insideLabels, [filledRemaining, filledSold], UIColor(hex: "8491A5")),
        ] {
            for label in labels {
                label.applyTextStyle(.calloutEmphasized, scaling: .dynamic)
                label.textColor = color
                label.numberOfLines = 0
                container.addSubview(label)
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ info: ApiCardInfo?, animated: Bool) {
        let showsCountdown = info?.mintCountdownDate != nil
        backdrop.isHidden = showsCountdown
        insideLabels.isHidden = showsCountdown
        fill.isHidden = showsCountdown
        remaining.textColor = UIColor.white.withAlphaComponent(showsCountdown ? 0.6 : 1)
        let fraction: CGFloat
        let remainingText: String
        let soldText: String?
        if let info, showsCountdown {
            fraction = 0
            remainingText = L10n.amountUniqueCardsTotal(amount: max(0, info.all))
            soldText = nil
        } else if let info, info.all > 0, info.notMinted > 0 {
            let count = min(info.notMinted, info.all)
            fraction = CGFloat(count) / CGFloat(info.all)
            remainingText = L10n.amountLeft(amount: localizedIntegerString(count))
            soldText = L10n.amountSold(amount: localizedIntegerString(info.all - count))
        } else {
            fraction = 0
            remainingText = lang(info == nil ? "Unavailable" : "This card has been sold out")
            soldText = nil
        }
        if fraction != remainingFraction {
            let current = fill.presentation() ?? fill
            previousFillGeometry = animated ? (current.bounds, current.position) : nil
            if !animated { [fill, fillMask].forEach { $0.removeAllAnimations() } }
            remainingFraction = fraction
        }
        for label in [remaining, filledRemaining] {
            MintCardTransition.setText(remainingText, on: label, animated: animated)
        }
        for label in [sold, filledSold] {
            MintCardTransition.setText(soldText, on: label, animated: animated)
        }
        accessibilityLabel = [remainingText, soldText].compactMap { $0 }.joined(separator: ", ")
        setNeedsLayout()
    }

    private func fitsHorizontally(_ width: CGFloat) -> Bool {
        let proposal = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        return remaining.sizeThatFits(proposal).width + sold.sizeThatFits(proposal).width + 12 <= width - 24
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let proposal = CGSize(width: max(0, size.width - 24), height: .greatestFiniteMagnitude)
        let firstHeight = remaining.sizeThatFits(proposal).height
        let lastHeight = sold.sizeThatFits(proposal).height
        let textHeight = fitsHorizontally(size.width) ? max(firstHeight, lastHeight)
            : firstHeight + lastHeight + (sold.text == nil ? 0 : 4)
        return CGSize(width: size.width, height: max(36, textHeight + 16))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        backdrop.frame = bounds
        outsideLabels.frame = bounds
        insideLabels.frame = bounds
        let rtl = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let track = bounds.insetBy(dx: 4, dy: 4)
        let width = max(0, track.width * remainingFraction)
        let fillFrame = CGRect(x: rtl ? track.maxX - width : track.minX, y: track.minY, width: width, height: max(0, track.height))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in [fill, fillMask] {
            layer.frame = fillFrame
            layer.cornerRadius = max(0, track.height / 2)
        }
        CATransaction.commit()
        if let previous = previousFillGeometry {
            previousFillGeometry = nil
            let resize = CABasicAnimation(keyPath: "bounds")
            resize.fromValue = NSValue(cgRect: previous.bounds)
            resize.toValue = NSValue(cgRect: fill.bounds)
            resize.duration = MintCardTransition.duration
            let move = CABasicAnimation(keyPath: "position")
            move.fromValue = NSValue(cgPoint: previous.position)
            move.toValue = NSValue(cgPoint: fill.position)
            move.duration = MintCardTransition.duration
            let animation = CAAnimationGroup()
            animation.animations = [resize, move]
            animation.duration = MintCardTransition.duration
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            // The fill and the contrasting text mask must share every animation.
            for layer in [fill, fillMask] { layer.add(animation, forKey: "availabilityProgress") }
        }

        let textWidth = max(0, bounds.width - 24)
        if fitsHorizontally(bounds.width), sold.text != nil {
            let first = rtl ? sold : remaining
            let last = rtl ? remaining : sold
            first.textAlignment = .left
            last.textAlignment = .right
            let firstWidth = first.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude)).width
            first.frame = CGRect(x: 12, y: 8, width: firstWidth, height: bounds.height - 16)
            last.frame = CGRect(x: first.frame.maxX + 12, y: 8, width: max(0, textWidth - firstWidth - 12), height: bounds.height - 16)
        } else {
            remaining.textAlignment = .center
            sold.textAlignment = .center
            remaining.frame = CGRect(x: 12, y: 8, width: textWidth, height: remaining.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude)).height)
            sold.frame = CGRect(x: 12, y: remaining.frame.maxY + 4, width: textWidth, height: sold.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude)).height)
        }
        for (original, duplicate) in [(remaining, filledRemaining), (sold, filledSold)] {
            duplicate.frame = original.frame
            duplicate.textAlignment = original.textAlignment
        }
    }
}
