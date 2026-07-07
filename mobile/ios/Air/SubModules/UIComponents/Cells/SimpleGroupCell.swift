import UIKit
import WalletContext

open class SimpleGroupCell: UICollectionViewListCell {
    private static let accessoryToTextSpacing: CGFloat = 8

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 17)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    public var title: String = "" {
        didSet { titleLabel.text = title }
    }

    private var _accessoryView: UIView?
    private var accessoryConstraints: [NSLayoutConstraint] = []
    private var titleTrailingConstraint: NSLayoutConstraint!

    public var accessoryView: UIView? {
        get { _accessoryView }
        set {
            _accessoryView?.removeFromSuperview()
            NSLayoutConstraint.deactivate(accessoryConstraints)
            titleTrailingConstraint?.isActive = false
            accessoryConstraints = []

            _accessoryView = newValue

            if let view = newValue {
                view.translatesAutoresizingMaskIntoConstraints = false
                contentView.addSubview(view)

                accessoryConstraints = [
                    view.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
                    view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                ]
                NSLayoutConstraint.activate(accessoryConstraints)

                titleTrailingConstraint = titleLabel.trailingAnchor.constraint(equalTo: view.leadingAnchor, constant: -Self.accessoryToTextSpacing)
                titleTrailingConstraint.isActive = true
            } else {
                titleTrailingConstraint = titleLabel.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor)
                titleTrailingConstraint.isActive = true
            }
        }
    }

    public func configureSwitchAccessory(isOn: Bool, onValueChange: @escaping (Bool) -> Void) {
        if let existing = accessoryView as? SwitchAccessory {
            existing.configure(isOn: isOn, onValueChange: onValueChange)
        } else {
            accessoryView = SwitchAccessory(isOn: isOn, onValueChange: onValueChange)
        }
    }

    /// Controls whether the cell shows a highlight animation on touch.
    /// This does NOT affect `didSelectItemAt` / `shouldSelectItemAt` delegate calls — implement those methods to
    /// actually allow or prevent, handle selection.
    public var isSelectable: Bool = true

    private let highlightingTime: Double = 0.1
    private let unhighlightingTime: Double = 0.5
    
    private var oldBackground: UIColor? = nil

    public override var isHighlighted: Bool {
        didSet {
            if isHighlighted != oldValue {
                let defaultColor: UIColor = .air.groupedItem
                if isHighlighted { oldBackground = defaultColor }
                UIView.animate(
                    withDuration: isHighlighted ? highlightingTime : unhighlightingTime,
                    delay: 0,
                    options: .allowUserInteraction
                ) { [self] in
                    var bg = UIBackgroundConfiguration.listGroupedCell()
                    bg.backgroundColor = isHighlighted ? .air.highlight : defaultColor
                    backgroundConfiguration = bg
                }
                if !isHighlighted { oldBackground = nil }
            }
        }
    }

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isSelectable { isHighlighted = true }
        super.touchesBegan(touches, with: event)
    }

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isSelectable { isHighlighted = false }
        super.touchesEnded(touches, with: event)
    }

    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isSelectable { isHighlighted = false }
        super.touchesCancelled(touches, with: event)
    }

    open override func prepareForReuse() {
        super.prepareForReuse()
        oldBackground = nil
        isHighlighted = false
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(titleLabel)
        let tc = titleLabel.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor)
        NSLayoutConstraint.activate([
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            tc,
        ])
        titleTrailingConstraint = tc

        var background = UIBackgroundConfiguration.listGroupedCell()
        background.backgroundColor = .air.groupedItem
        backgroundConfiguration = background
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension SimpleGroupCell {
    public final class TitledDisclosureAccessory: UIView {
        private let textLabel: UILabel = {
            let label = UILabel()
            label.font = .systemFont(ofSize: 17)
            label.textColor = .air.secondaryLabel
            label.translatesAutoresizingMaskIntoConstraints = false
            return label
        }()

        private let chevron: UIImageView = {
            let iv = UIImageView(image: UIImage.airBundle("RightArrowIcon").withRenderingMode(.alwaysTemplate))
            iv.tintColor = .air.secondaryLabel
            iv.contentMode = .scaleAspectFit
            iv.setContentHuggingPriority(.required, for: .horizontal)
            iv.translatesAutoresizingMaskIntoConstraints = false
            return iv
        }()

        public var text: String? {
            get { textLabel.text }
            set { textLabel.text = newValue }
        }

        public init(text: String? = nil) {
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            addSubview(textLabel)
            addSubview(chevron)
            NSLayoutConstraint.activate([
                textLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
                textLabel.topAnchor.constraint(equalTo: topAnchor),
                textLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
                chevron.leadingAnchor.constraint(equalTo: textLabel.trailingAnchor, constant: 8),
                chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
                chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
            self.text = text
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}

extension SimpleGroupCell {
    public final class SwitchAccessory: UIView {

        private let switchControl = UISwitch()
        private var valueAction: UIAction?

        public var isOn: Bool {
            get { switchControl.isOn }
            set { switchControl.isOn = newValue }
        }
        
        override public var intrinsicContentSize: CGSize {
            let cs = switchControl.intrinsicContentSize
            return CGSize(width: cs.width + 16, height: cs.height)
        }

        public init(isOn: Bool, onValueChange: @escaping (Bool) -> Void) {
            super.init(frame: .zero)
            addSubview(switchControl)
            switchControl.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                switchControl.centerYAnchor.constraint(equalTo: centerYAnchor),
                switchControl.leadingAnchor.constraint(equalTo: leadingAnchor),
                switchControl.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            ])
            configure(isOn: isOn, onValueChange: onValueChange)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        public func configure(isOn: Bool, onValueChange: @escaping (Bool) -> Void) {
            if let previous = valueAction {
                switchControl.removeAction(previous, for: .valueChanged)
            }
            let action = UIAction { [weak self] _ in
                onValueChange(self?.switchControl.isOn ?? false)
            }
            valueAction = action
            switchControl.addAction(action, for: .valueChanged)
            switchControl.isOn = isOn
        }
    }
}

public class SimpleGroupSectionFooter: UICollectionReusableView {
    private let label: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.numberOfLines = 0
        lbl.textColor = .secondaryLabel
        lbl.font = .systemFont(ofSize: 13)
        return lbl
    }()

    public var text: String = "" {
        didSet {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 2
            label.attributedText = NSAttributedString(
                string: text,
                attributes: [.paragraphStyle: paragraphStyle, .font: UIFont.systemFont(ofSize: 13)]
            )
        }
    }

    override public init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
