import UIKit

@MainActor
protocol ContextMenuPageViewDelegate: AnyObject {
    func pageView(_ pageView: ContextMenuPageView, didActivate action: ContextMenuPageAction)
}

struct ContextMenuActivation {
    let dismissesMenu: Bool
    let handler: (() -> Void)?
}

enum ContextMenuPageAction {
    case trigger(ContextMenuActivation)
    case back
    case submenu(ContextMenuPage)
}

struct ContextMenuRowPresentation {
    enum Accessory {
        case none
        case disclosure
    }

    let title: String
    let subtitle: String?
    let icon: ContextMenuIcon?
    let badgeText: String?
    let role: ContextMenuRole
    let isEnabled: Bool
    let accessory: Accessory
}

final class ContextMenuScrollView: UIScrollView {
    override func touchesShouldCancel(in view: UIView) -> Bool {
        true
    }
}

final class ContextMenuSelectionTouchView: UIView {
    var onBegan: ((CGPoint) -> Void)?
    var onMoved: ((CGPoint, CGPoint) -> Void)?
    var onEnded: ((CGPoint, Bool) -> Void)?
    var shouldCaptureTouch: ((CGPoint) -> Bool)?

    private var initialPoint: CGPoint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard super.point(inside: point, with: event) else {
            return false
        }
        return self.shouldCaptureTouch?(point) ?? true
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)

        guard let point = touches.first?.location(in: self) else {
            return
        }
        self.initialPoint = point
        self.onBegan?(point)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)

        guard let point = touches.first?.location(in: self), let initialPoint = self.initialPoint else {
            return
        }
        self.onMoved?(initialPoint, point)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)

        guard let point = touches.first?.location(in: self) else {
            self.initialPoint = nil
            return
        }
        self.onEnded?(point, true)
        self.initialPoint = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)

        let point = touches.first?.location(in: self) ?? self.initialPoint ?? .zero
        self.onEnded?(point, false)
        self.initialPoint = nil
    }
}

final class ContextMenuPageRowElement {
    let view: UIView
    let controlView: UIControl?
    let isSelectable: Bool
    let isEnabled: Bool
    let activation: ContextMenuPageAction?

    private let measuredSizeImpl: (CGFloat) -> CGSize
    private let applyLayoutImpl: (CGSize) -> Void
    private let updateColorsImpl: () -> Void
    private let setDirectInteractionEnabledImpl: (Bool) -> Void

    init(
        view: UIView,
        controlView: UIControl?,
        isSelectable: Bool,
        isEnabled: Bool,
        activation: ContextMenuPageAction?,
        measuredSize: @escaping (CGFloat) -> CGSize,
        applyLayout: @escaping (CGSize) -> Void,
        updateColors: @escaping () -> Void,
        setDirectInteractionEnabled: @escaping (Bool) -> Void
    ) {
        self.view = view
        self.controlView = controlView
        self.isSelectable = isSelectable
        self.isEnabled = isEnabled
        self.activation = activation
        self.measuredSizeImpl = measuredSize
        self.applyLayoutImpl = applyLayout
        self.updateColorsImpl = updateColors
        self.setDirectInteractionEnabledImpl = setDirectInteractionEnabled
    }

    func measuredSize(maxWidth: CGFloat) -> CGSize {
        self.measuredSizeImpl(maxWidth)
    }

    func applyLayout(size: CGSize) {
        self.applyLayoutImpl(size)
    }

    func updateColors() {
        self.updateColorsImpl()
    }

    func setDirectInteractionEnabled(_ isEnabled: Bool) {
        self.setDirectInteractionEnabledImpl(isEnabled)
    }
}

final class ContextMenuSeparatorView: UIView {
    private let lineView = UIView()
    private let style: ContextMenuStyle

    init(style: ContextMenuStyle) {
        self.style = style
        super.init(frame: .zero)

        self.addSubview(self.lineView)
        self.isUserInteractionEnabled = false
        self.updateColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let height = 1.0
        let horizontalInset = self.style.rowSideInset + 4.0
        self.lineView.frame = CGRect(
            x: horizontalInset,
            y: floor((self.bounds.height - height) * 0.5),
            width: max(0.0, self.bounds.width - horizontalInset * 2.0),
            height: height
        )
    }

    func updateColors() {
        self.lineView.backgroundColor = ContextMenuVisuals.separatorColor(for: self.traitCollection)
    }
}

final class ContextMenuRowView: UIControl {
    private let presentation: ContextMenuRowPresentation
    private let style: ContextMenuStyle

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let iconView = UIImageView()
    private let badgeView = UIImageView()
    private let accessoryView = UIImageView()

    init(presentation: ContextMenuRowPresentation, style: ContextMenuStyle) {
        self.presentation = presentation
        self.style = style

        super.init(frame: .zero)

        self.titleLabel.font = ContextMenuVisuals.titleFont()
        self.titleLabel.numberOfLines = 2
        self.titleLabel.lineBreakMode = .byTruncatingTail

        self.subtitleLabel.font = ContextMenuVisuals.subtitleFont()
        self.subtitleLabel.numberOfLines = 1
        self.subtitleLabel.lineBreakMode = .byTruncatingTail

        self.iconView.contentMode = .scaleAspectFit
        self.iconView.image = presentation.icon?.resolvedImage

        self.badgeView.contentMode = .center

        self.accessoryView.contentMode = .center
        self.accessoryView.image = presentation.accessory == .disclosure ? ContextMenuVisuals.chevronImage() : nil

        self.addSubview(self.titleLabel)
        self.addSubview(self.subtitleLabel)
        self.addSubview(self.iconView)
        self.addSubview(self.badgeView)
        self.addSubview(self.accessoryView)

        self.titleLabel.text = presentation.title
        self.subtitleLabel.text = presentation.subtitle
        self.subtitleLabel.isHidden = presentation.subtitle == nil
        self.iconView.isHidden = presentation.icon?.resolvedImage == nil
        self.badgeView.isHidden = presentation.badgeText == nil
        self.accessoryView.isHidden = presentation.accessory == .none

        self.isEnabled = presentation.isEnabled
        self.updateColors()
        self.updateBadge()
        self.accessibilityTraits = .button
        self.accessibilityLabel = [presentation.title, presentation.subtitle].compactMap { $0 }.joined(separator: ", ")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet {
            let alpha: CGFloat = self.presentation.isEnabled ? (self.isHighlighted ? 0.82 : 1.0) : 0.5
            self.titleLabel.alpha = alpha
            self.subtitleLabel.alpha = alpha
            self.iconView.alpha = alpha
            self.badgeView.alpha = alpha
            self.accessoryView.alpha = alpha
        }
    }

    func measuredSize(maxWidth: CGFloat) -> CGSize {
        let chromeWidth = self.horizontalChromeWidth
        let availableTextWidth = max(1.0, maxWidth - chromeWidth)
        let idealTitleSize = self.titleLabel.sizeThatFits(CGSize(width: 10_000.0, height: 100.0))
        let idealSubtitleSize = self.subtitleLabel.isHidden
            ? .zero
            : self.subtitleLabel.sizeThatFits(CGSize(width: 10_000.0, height: 100.0))
        let laidOutTitleSize = self.titleLabel.sizeThatFits(CGSize(width: availableTextWidth, height: 100.0))
        let laidOutSubtitleSize = self.subtitleLabel.isHidden
            ? .zero
            : self.subtitleLabel.sizeThatFits(CGSize(width: availableTextWidth, height: 100.0))

        let width = chromeWidth + max(idealTitleSize.width, idealSubtitleSize.width.rounded(.up))

        var height = self.style.rowVerticalInset * 2.0 + laidOutTitleSize.height
        if !self.subtitleLabel.isHidden {
            height += 1.0 + laidOutSubtitleSize.height
        }

        return CGSize(width: width.rounded(.up), height: ceil(height))
    }

    func applyLayout(size: CGSize) {
        let iconX = self.style.iconSideInset
        if let image = self.iconView.image {
            let iconSize = image.size
            self.iconView.frame = CGRect(
                x: iconX + floor((self.reservedIconWidth - iconSize.width) * 0.5),
                y: floor((size.height - iconSize.height) * 0.5),
                width: iconSize.width,
                height: iconSize.height
            )
        } else {
            self.iconView.frame = .zero
        }

        let titleX = self.reservesIconSpace
            ? (self.style.iconSideInset + self.reservedIconWidth + self.style.iconSpacing)
            : self.style.rowSideInset
        var rightLimit = size.width - self.style.rowSideInset
        if self.presentation.accessory == .disclosure {
            let accessorySize = CGSize(width: 13.0, height: 13.0)
            self.accessoryView.frame = CGRect(
                x: size.width - self.style.rowSideInset - accessorySize.width,
                y: floor((size.height - accessorySize.height) * 0.5),
                width: accessorySize.width,
                height: accessorySize.height
            )
            rightLimit = self.accessoryView.frame.minX - 12.0
        } else {
            self.accessoryView.frame = .zero
        }

        if let badgeImage = self.badgeView.image {
            self.badgeView.frame = CGRect(
                x: rightLimit - badgeImage.size.width,
                y: floor((size.height - badgeImage.size.height) * 0.5),
                width: badgeImage.size.width,
                height: badgeImage.size.height
            )
            rightLimit = self.badgeView.frame.minX - 8.0
        } else {
            self.badgeView.frame = .zero
        }

        let availableTextWidth = max(1.0, rightLimit - titleX)
        let finalTitleSize = self.titleLabel.sizeThatFits(CGSize(width: availableTextWidth, height: 100.0))
        let finalSubtitleSize = self.subtitleLabel.isHidden ? .zero : self.subtitleLabel.sizeThatFits(CGSize(width: availableTextWidth, height: 100.0))

        let totalTextHeight = finalTitleSize.height + (self.subtitleLabel.isHidden ? 0.0 : 1.0 + finalSubtitleSize.height)
        let titleY = floor((size.height - totalTextHeight) * 0.5)
        self.titleLabel.frame = CGRect(x: titleX, y: titleY, width: availableTextWidth, height: finalTitleSize.height)
        self.subtitleLabel.frame = CGRect(x: titleX, y: self.titleLabel.frame.maxY + 1.0, width: availableTextWidth, height: finalSubtitleSize.height)
    }

    func updateColors() {
        let primaryColor = ContextMenuVisuals.primaryTextColor(
            for: self.traitCollection,
            role: self.presentation.role,
            enabled: self.presentation.isEnabled
        )
        self.titleLabel.textColor = primaryColor
        self.subtitleLabel.textColor = ContextMenuVisuals.secondaryTextColor(for: self.traitCollection)
        self.iconView.tintColor = primaryColor
        self.accessoryView.tintColor = ContextMenuVisuals.secondaryTextColor(for: self.traitCollection)
    }

    func updateBadge() {
        guard let badgeText = self.presentation.badgeText else {
            self.badgeView.image = nil
            return
        }
        self.badgeView.image = ContextMenuVisuals.makeBadgeImage(text: badgeText, traits: self.traitCollection)
    }

    private var reservesIconSpace: Bool {
        self.presentation.icon?.reservesSpace ?? false
    }

    private var horizontalChromeWidth: CGFloat {
        var width = self.reservesIconSpace
            ? (self.style.iconSideInset + self.reservedIconWidth + self.style.iconSpacing)
            : self.style.rowSideInset

        if let badgeImage = self.badgeView.image {
            width += badgeImage.size.width + 8.0
        }

        if self.presentation.accessory == .disclosure {
            width += self.style.rowSideInset + 18.0 + 12.0
        } else {
            width += self.style.rowSideInset
        }

        return width
    }

    private var reservedIconWidth: CGFloat {
        max(self.style.standardIconWidth, self.iconView.image?.size.width ?? 0.0)
    }
}

final class ContextMenuCustomRowView: UIControl {
    private let item: ContextMenuCustomRow
    private let hostedContentView: UIView
    private let containerView = UIView()

    init(item: ContextMenuCustomRow, context: ContextMenuCustomRowContext) {
        self.item = item
        self.hostedContentView = item.makeContentView(context)

        super.init(frame: .zero)

        self.isEnabled = item.interaction.isSelectable ? item.interaction.isEnabled : true

        self.hostedContentView.translatesAutoresizingMaskIntoConstraints = false
        self.containerView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.containerView)
        self.containerView.addSubview(self.hostedContentView)

        NSLayoutConstraint.activate([
            self.containerView.topAnchor.constraint(equalTo: self.topAnchor),
            self.containerView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            self.containerView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            self.containerView.bottomAnchor.constraint(equalTo: self.bottomAnchor),

            self.hostedContentView.topAnchor.constraint(equalTo: self.containerView.topAnchor),
            self.hostedContentView.leadingAnchor.constraint(equalTo: self.containerView.leadingAnchor),
            self.hostedContentView.trailingAnchor.constraint(equalTo: self.containerView.trailingAnchor),
            self.hostedContentView.bottomAnchor.constraint(equalTo: self.containerView.bottomAnchor)
        ])

        if item.interaction.isSelectable {
            self.hostedContentView.isUserInteractionEnabled = false
            self.accessibilityTraits = .button
        }

        if item.interaction.isSelectable, !item.interaction.isEnabled {
            self.alpha = 0.5
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet {
            guard self.item.interaction.isSelectable else {
                return
            }
            self.containerView.alpha = self.isHighlighted ? 0.82 : 1.0
        }
    }

    func measuredSize(maxWidth: CGFloat) -> CGSize {
        self.layoutIfNeeded()

        let targetWidth = self.preferredMeasurementWidth(maxWidth: maxWidth)
        let measuredHeight = self.measureHeight(for: targetWidth)
        return CGSize(width: ceil(targetWidth), height: ceil(measuredHeight))
    }

    func applyLayout(size: CGSize) {
        self.layoutIfNeeded()
    }

    func updateColors() {
    }

    private func preferredMeasurementWidth(maxWidth: CGFloat) -> CGFloat {
        if let preferredWidth = self.item.preferredWidth {
            return min(maxWidth, preferredWidth)
        }

        let targetHeight = self.item.sizing.fixedHeight ?? UIView.layoutFittingCompressedSize.height
        let measuredSize = self.systemLayoutSizeFitting(
            CGSize(width: maxWidth, height: targetHeight),
            withHorizontalFittingPriority: .fittingSizeLevel,
            verticalFittingPriority: self.item.sizing.fixedHeight == nil ? .fittingSizeLevel : .required
        )
        let width = measuredSize.width
        guard width.isFinite, width > 1.0 else {
            return maxWidth
        }
        return min(maxWidth, width)
    }

    private func measureHeight(for width: CGFloat) -> CGFloat {
        if let fixedHeight = self.item.sizing.fixedHeight {
            return fixedHeight
        }

        let measuredSize = self.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        let height = measuredSize.height
        guard height.isFinite, height > 1.0 else {
            return self.item.sizing.minimumHeight
        }
        return max(self.item.sizing.minimumHeight, height)
    }
}
