import SwiftUI
import UIKit
import WalletContext

public final class NativeTradeNoticeView: UIView {
    public struct Configuration: Equatable {
        public let title: String
        public let message: String
        public var isWarning = false
        public var actionTitle: String?

        public init(title: String, message: String, isWarning: Bool = false, actionTitle: String? = nil) {
            self.title = title
            self.message = message
            self.isWarning = isWarning
            self.actionTitle = actionTitle
        }
    }

    public var onAction: (() -> Void)?
    public private(set) var configuration: Configuration?
    private let textReplacement = BlurReplaceView()
    private var textLabel = UILabel()
    private let action = TradePressButton(frame: .zero)
    private lazy var actionPresence = TradePresenceView(action)
    private let actionLabel = UILabel()
    private let actionBackground = CAShapeLayer()
    private let noticeBackground = CAShapeLayer()
    private let sideBars = CAShapeLayer()
    private var previousBounds = CGRect.zero

    public override init(frame: CGRect) {
        super.init(frame: frame)
        layer.addSublayer(noticeBackground)
        layer.addSublayer(sideBars)
        addSubview(textReplacement)
        addSubview(actionPresence)
        textReplacement.maximumBlurRadius = 4
        textReplacement.animationDuration = TradeMotion.duration
        action.content.layer.addSublayer(actionBackground)
        action.content.addSubview(actionLabel)
        actionLabel.textAlignment = .center
        actionLabel.adjustsFontForContentSizeCategory = true
        action.addAction(UIAction { [weak self] _ in self?.onAction?() }, for: .touchUpInside)
        action.accessibilityIdentifier = "tokenTrade.hintAction"
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public func update(_ configuration: Configuration, animated: Bool) {
        guard self.configuration != configuration else { return }
        self.configuration = configuration
        updateContent(animated: animated)
    }

    private var color: UIColor {
        configuration?.isWarning == true ? .air.error : UIColor(light: "#DE8C00", dark: "#FFAB2F")
    }

    private func font(_ style: WTextStyle, textStyle: UIFont.TextStyle, weight: UIFont.Weight = .regular) -> UIFont {
        if Language.current == .fa {
            return WTypography.uiFont(style, scaling: .dynamic, compatibleWith: traitCollection)
        }
        // The SwiftUI reference uses the system's Dynamic Type sizes and leading for system fonts.
        let font = UIFont.preferredFont(forTextStyle: textStyle, compatibleWith: traitCollection)
        let descriptor = font.fontDescriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
        return UIFont(descriptor: descriptor, size: font.pointSize)
    }

    private func updateContent(animated: Bool) {
        guard let configuration else { return }
        let font = font(.footnote, textStyle: .footnote)
        let bold = self.font(.footnoteStrong, textStyle: .footnote, weight: .semibold)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        paragraph.baseWritingDirection = .natural
        paragraph.alignment = effectiveUserInterfaceLayoutDirection == .rightToLeft ? .right : .left
        let attributed = NSMutableAttributedString(string: configuration.title,
            attributes: [.font: bold, .foregroundColor: color, .paragraphStyle: paragraph])
        attributed.append(NSAttributedString(string: (configuration.title.isEmpty ? "" : "\n") + configuration.message,
            attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]))
        let label = UILabel()
        label.attributedText = attributed
        label.numberOfLines = 0
        label.accessibilityLabel = configuration.title + " " + configuration.message
        label.isAccessibilityElement = true
        textLabel = label
        textReplacement.replaceContent(with: label, animated: animated && TradeMotion.enabled)
        actionLabel.text = configuration.actionTitle
        actionLabel.font = self.font(.supportingBold, textStyle: .subheadline, weight: .bold)
        actionLabel.textColor = color
        action.accessibilityLabel = configuration.actionTitle
        actionPresence.setContentVisible(configuration.actionTitle != nil, animated: animated)
        let resolvedColor = color.resolvedColor(with: traitCollection)
        actionBackground.fillColor = resolvedColor.withAlphaComponent(0.12).cgColor
        noticeBackground.fillColor = resolvedColor.withAlphaComponent(0.12).cgColor
        sideBars.fillColor = resolvedColor.cgColor
        for shape in [actionBackground, noticeBackground, sideBars] {
            shape.contentsScale = traitCollection.displayScale
        }
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    private var stacksAction: Bool { traitCollection.preferredContentSizeCategory.isAccessibilityCategory }
    private var actionSize: CGSize {
        guard configuration?.actionTitle != nil else { return .zero }
        let text = actionLabel.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: text.width + 24, height: max(44, text.height + 12))
    }

    public override func sizeThatFits(_ size: CGSize) -> CGSize {
        let actionSize = actionSize
        let textWidth = max(1, size.width - 36 - (!stacksAction && actionSize.width > 0 ? actionSize.width + 12 : 0))
        let textHeight = textLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude)).height + 4
        let height = stacksAction && actionSize.height > 0 ? textHeight + 8 + actionSize.height : max(textHeight, actionSize.height)
        return CGSize(width: size.width, height: height + 24)
    }

    public override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric,
               height: bounds.width > 0 ? sizeThatFits(bounds.size).height : 44)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        if previousBounds.width != bounds.width { invalidateIntrinsicContentSize() }
        let actionSize = actionSize
        let textWidth = max(1, bounds.width - 36 - (!stacksAction && actionSize.width > 0 ? actionSize.width + 12 : 0))
        let textHeight = textLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude)).height
        let textY = stacksAction && actionSize.height > 0 ? 14 : (bounds.height - textHeight) / 2
        let rtl = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let textX = !stacksAction && actionSize.width > 0 && rtl ? 18 + actionSize.width + 12 : 18
        TradeMotion.place(textReplacement, in: CGRect(x: textX, y: textY, width: textWidth, height: textHeight))
        let actionX = rtl ? 18 : bounds.width - 18 - actionSize.width
        let actionY = stacksAction ? bounds.height - 12 - actionSize.height : (bounds.height - actionSize.height) / 2
        if actionSize.width > 0 {
            TradeMotion.place(actionPresence, in: CGRect(x: stacksAction ? (rtl ? actionX : 18) : actionX,
                                                             y: actionY, width: actionSize.width, height: actionSize.height))
            actionLabel.frame = CGRect(origin: .zero, size: actionSize)
            let capsuleHeight = actionLabel.sizeThatFits(actionSize).height + 12
            let capsule = CGRect(x: 0, y: (actionSize.height - capsuleHeight) / 2,
                                 width: actionSize.width, height: capsuleHeight)
            actionBackground.path = Capsule().path(in: capsule).cgPath
        }
        guard previousBounds != bounds else { return }
        previousBounds = bounds
        let radius = min(26, bounds.height / 2, bounds.width / 2)
        let barWidth = min(4, radius)
        let outer = RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: bounds)
        let inner = RoundedRectangle(cornerSize: CGSize(width: radius - barWidth, height: radius), style: .continuous)
            .path(in: bounds.insetBy(dx: barWidth, dy: 0))
        noticeBackground.path = RoundedRectangle(cornerRadius: 26, style: .continuous).path(in: bounds).cgPath
        // Resolve shared horizontal edges before rasterization, as in WarningBackground.
        sideBars.path = outer.cgPath.subtracting(inner.cgPath)
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateContent(animated: false)
    }
}
