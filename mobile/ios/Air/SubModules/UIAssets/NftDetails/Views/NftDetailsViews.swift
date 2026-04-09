import UIKit
import SwiftUI
import WalletContext
import UIComponents

// MARK: - NftDetailsCollectionButton

final class NftDetailsCollectionButton: UIView, NftDetailsContentColorConsumer {
    private let button = UIButton(type: .custom)
    private var contentColor: NftDetailsContentPalette?

    var name: String = "" {
        didSet { updateAttributedTitle() }
    }
    
    var onTap: (() -> Void)? {
        didSet {
            isUserInteractionEnabled = onTap != nil
            updateAttributedTitle()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(handleTap), for: .touchUpInside)
        addSubview(button)

        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: topAnchor),
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        updateAttributedTitle()
    }

    private func updateAttributedTitle() {
        guard let contentColor else {
            return
        }
        
        let textColor = contentColor.secondaryTextColor
        let font = UIFont.systemFont(ofSize: 16)
        let canTap = onTap != nil
        
        let attrString = NSMutableAttributedString()
        attrString.append(NSAttributedString(string: name, attributes: [.font: font, .foregroundColor: textColor]))

        if canTap {
            attrString.append(NSAttributedString(string: "\u{2009}", attributes: [.font: font, .foregroundColor: textColor])) // narrow space
            let symbolConfig = UIImage.SymbolConfiguration(pointSize: 12, weight: .regular)
            let chevronImage = UIImage(systemName: "chevron.right", withConfiguration: symbolConfig)?
                .withTintColor(textColor, renderingMode: .alwaysOriginal)
            let attachment = NSTextAttachment()
            attachment.image = chevronImage
            attachment.bounds = CGRect(
                x: 0,
                y: (font.descender) / 2,
                width: chevronImage?.size.width ?? 6,
                height: chevronImage?.size.height ?? 12
            )
            attrString.append(NSAttributedString(attachment: attachment))
        }
        
        var config = UIButton.Configuration.plain()
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)
        config.titleLineBreakMode = .byWordWrapping
        config.attributedTitle = AttributedString(attrString)
        button.configuration = config
        button.titleLabel?.numberOfLines = 0
        button.titleLabel?.textAlignment = .center
        if canTap {
            button.configurationUpdateHandler = { button in
                button.titleLabel?.alpha = button.isHighlighted ? 0.5 : 1
            }
        }
    }

    func applyContentColorPalette(_ palette: NftDetailsContentPalette) -> Bool {
        contentColor = palette
        updateAttributedTitle()
        return false
    }

    @objc private func handleTap() {
        onTap?()
    }
}

// MARK: - NftDetailsLabel

class NftDetailsLabel: UILabel, NftDetailsContentColorConsumer {
    var contentPadding: UIEdgeInsets = .zero {
        didSet { invalidateIntrinsicContentSize(); setNeedsLayout() }
    }

    override func textRect(forBounds bounds: CGRect, limitedToNumberOfLines numberOfLines: Int) -> CGRect {
        let insetBounds = bounds.inset(by: contentPadding)
        let textRect = super.textRect(forBounds: insetBounds, limitedToNumberOfLines: numberOfLines)
        return CGRect(
            x: bounds.minX,
            y: bounds.minY,
            width: textRect.width + contentPadding.left + contentPadding.right,
            height: textRect.height + contentPadding.top + contentPadding.bottom
        )
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: contentPadding))
    }

    func applyContentColorPalette(_ palette: NftDetailsContentPalette) -> Bool {
        textColor = palette.baseColor
        return false
    }
}

// MARK: - NftDetailsDescriptionTile

final class NftDetailsDescriptionTile: UIView, NftDetailsContentColorConsumer {
    private let backgroundView = ThinGlassView()
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    
    var titleText: String? {
        didSet { titleLabel.text = titleText }
    }
    
    var bodyText: String? {
        didSet {
            bodyLabel.setText(bodyText, font: UIFont.systemFont(ofSize: 17), lineHeight: 22)
        }
    }
        
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setup() {
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backgroundView)
        
        titleLabel.text = titleText
        titleLabel.font = .systemFont(ofSize: 14)
        titleLabel.numberOfLines = 0
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        
        bodyLabel.text = bodyText
        bodyLabel.font = .systemFont(ofSize: 17)
        bodyLabel.numberOfLines = 0
        
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bodyLabel)
                
        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),

            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            
            bodyLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            bodyLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            bodyLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            bodyLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])
    }
    
    func applyContentColorPalette(_ palette: NftDetailsContentPalette) -> Bool {
        titleLabel.textColor = palette.secondaryTextColor
        bodyLabel.textColor = palette.baseColor
        backgroundView.fillColor = palette.subtleBackgroundColor
        backgroundView.edgeColor = palette.edgeColor
        return false
    }
}

// MARK: - NftDetailsDomainTile

final class NftDetailsDomainTile: UIView, NftDetailsContentColorConsumer {
    private let backgroundView = ThinGlassView()
    private let stackView = UIStackView()
    private let textLabel = UILabel()
    private let renewButton = UIButton(type: .custom)

    var text: String? {
        didSet { textLabel.setText(text, font: .systemFont(ofSize: 17), lineHeight: 22) }
    }

    var showsRenewButton: Bool = true {
        didSet { renewButton.isHidden = !showsRenewButton }
    }

    var onRenewTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backgroundView)

        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.distribution = .fill
        stackView.spacing = 20
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        textLabel.numberOfLines = 0
        textLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        stackView.addArrangedSubview(textLabel)

        renewButton.setTitle(lang("Renew"), for: .normal)
        renewButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        renewButton.addTarget(self, action: #selector(handleRenewTap), for: .touchUpInside)
        renewButton.setContentHuggingPriority(.required, for: .horizontal)
        renewButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        stackView.addArrangedSubview(renewButton)

        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            
            heightAnchor.constraint(greaterThanOrEqualToConstant: 56)
        ])
    }

    func applyContentColorPalette(_ palette: NftDetailsContentPalette) -> Bool {
        textLabel.textColor = palette.baseColor
        renewButton.setTitleColor(palette.baseColor, for: .normal)
        renewButton.setTitleColor(palette.baseColor.withAlphaComponent(0.5), for: .highlighted)
        backgroundView.fillColor = palette.subtleBackgroundColor
        backgroundView.edgeColor = palette.edgeColor
        return false
    }

    @objc private func handleRenewTap() {
        onRenewTap?()
    }
}

// MARK: - NftDetailsAttributesGrid

final class NftDetailsAttributesGrid: UIView, NftDetailsContentColorConsumer {
    let contentInsets = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
    
    private let keyValueSpacing: CGFloat = 12
    private let fixedWidth: CGFloat

    private let backgroundView = ThinGlassView()
    private let keyColumnBackgroundView = UIView()
    private let keyColumnSeparatorView = UIView()
    private let rowsStack = UIStackView()
    
    private struct RowContext {
        let attribute: NftDetailsItem.Attribute
        var keyLabel: UILabel!
        var valueLabel: UILabel!
        var separatorView: SeparatorView?
    }
    
    private var rows: [RowContext]
    
    init(width: CGFloat, attributes: [NftDetailsItem.Attribute]) {
        
        self.rows = attributes.map { .init(attribute: $0) }
        self.fixedWidth = width
        
        super.init(frame: .fromSize(width: width, height: .greatestFiniteMagnitude))
        setup()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private class SeparatorView: UIView {
        let contentInsets: UIEdgeInsets
        let lineLayer = CALayer()
        
        init(contentInsets: UIEdgeInsets) {
            self.contentInsets = contentInsets
            super.init(frame: .zero)
            layer.masksToBounds = false
            layer.addSublayer(lineLayer)
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        override func layoutSubviews() {
            super.layoutSubviews()
            
            var f = bounds
            f.origin.y = contentInsets.bottom
            f.size.height = 0.7
            f.origin.x -= contentInsets.left - 1
            f.size.width += contentInsets.left + contentInsets.right - 2
            lineLayer.frame = f
        }
        
        override var intrinsicContentSize: CGSize {
            .init(width: .greatestFiniteMagnitude, height: contentInsets.top + contentInsets.bottom)
        }
    }

    // Key column: as small as needed for keys when space allows; balance with values when tight
    private func calcKeyColumnWidth(maxKeyWidth: CGFloat, maxValueWidth: CGFloat) -> CGFloat {
        let availableWidth = fixedWidth - contentInsets.left - contentInsets.right - 2 * keyValueSpacing
        let totalNeeded = maxKeyWidth + maxValueWidth

        var keyColumnWidth: CGFloat
        let leftSpace = availableWidth - totalNeeded
        if leftSpace > 0 {
            // trying to distribute more free space. Will try be closer to the middle if possible
            let delta = availableWidth * 0.5 - maxKeyWidth
            if delta > 0 {
                keyColumnWidth = maxKeyWidth + min(delta, leftSpace)
            } else {
                keyColumnWidth = maxKeyWidth + min(leftSpace, contentInsets.right - keyValueSpacing) // slighly adjust
            }
        } else {
            keyColumnWidth = availableWidth * min(0.7, max(0.3, maxKeyWidth / totalNeeded))
            
            // edge case: if we have a chance to place all values in a line let's do it
            let newAvailableSpace = availableWidth - keyColumnWidth
            let needMoreToPlaceAllValues = maxValueWidth - newAvailableSpace
            if needMoreToPlaceAllValues > 0 && needMoreToPlaceAllValues < 40 {
                keyColumnWidth -= needMoreToPlaceAllValues
            }
        }
        return max(0, ceil(keyColumnWidth))
    }
    
    private func setup() {
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backgroundView)

        keyColumnBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        keyColumnBackgroundView.layer.cornerRadius = backgroundView.cornerRadius
        keyColumnBackgroundView.layer.maskedCorners = [
                .layerMinXMinYCorner,  // topLeft
                .layerMinXMaxYCorner   // bottomLeft
            ]
        keyColumnBackgroundView.layer.masksToBounds = true
        addSubview(keyColumnBackgroundView)

        keyColumnSeparatorView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(keyColumnSeparatorView)

        rowsStack.axis = .vertical
        rowsStack.alignment = .fill
        rowsStack.distribution = .fill
        rowsStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rowsStack)

        var constraints: [NSLayoutConstraint] = [
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            rowsStack.topAnchor.constraint(equalTo: topAnchor, constant: contentInsets.top),
            rowsStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: contentInsets.left),
            rowsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -contentInsets.right),
            rowsStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -(contentInsets.bottom + 4)),
            
            keyColumnBackgroundView.topAnchor.constraint(equalTo: topAnchor),
            keyColumnBackgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            keyColumnBackgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            keyColumnSeparatorView.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            keyColumnSeparatorView.leadingAnchor.constraint(equalTo: keyColumnBackgroundView.trailingAnchor),
            keyColumnSeparatorView.widthAnchor.constraint(equalToConstant: 0.7),
            keyColumnSeparatorView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
        ]
        
        let font = UIFont.systemFont(ofSize: 15)
        let infiniteSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        var maxKeyWidth1: CGFloat = 0
        var maxValueWidth: CGFloat = 0
        for (index, var row) in rows.enumerated() {
            do {
                let keyLabel = UILabel()
                keyLabel.setText(row.attribute.traitType, font: font, lineHeight: 22)
                keyLabel.numberOfLines = 0
                row.keyLabel = keyLabel
                let keyWidth = keyLabel.sizeThatFits(infiniteSize).width
                maxKeyWidth1 = max(maxKeyWidth1, keyWidth)
            }
            
            do {
                let valueLabel = UILabel()
                valueLabel.setText(row.attribute.value, font: font, lineHeight: 22)
                valueLabel.numberOfLines = 0
                row.valueLabel = valueLabel
                let valueWidth = valueLabel.sizeThatFits(infiniteSize).width
                maxValueWidth = max(maxValueWidth, valueWidth)
            }
            
            if index != 0 {
                row.separatorView = SeparatorView(contentInsets: contentInsets)
            }
            
            rows[index] = row
        }

        let keyColumnWidth = calcKeyColumnWidth(maxKeyWidth: maxKeyWidth1, maxValueWidth: maxValueWidth)
        constraints.append(keyColumnBackgroundView.widthAnchor.constraint(
            equalToConstant: keyColumnWidth + contentInsets.left + keyValueSpacing
        ))
        
        for row in rows {
            if let separatorView = row.separatorView {
                rowsStack.addArrangedSubview(separatorView)
            }
            
            let keyLabel = row.keyLabel!
            keyLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            keyLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
            constraints.append(keyLabel.widthAnchor.constraint(equalToConstant: keyColumnWidth))

            let valueLabel = row.valueLabel!
            valueLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
            valueLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

            let rowStack = UIStackView(arrangedSubviews: [keyLabel, valueLabel])
            rowStack.axis = .horizontal
            rowStack.spacing = keyValueSpacing * 2
            rowStack.alignment = .top
            rowStack.distribution = .fill
            rowsStack.addArrangedSubview(rowStack)
        }
        
        NSLayoutConstraint.activate(constraints)
    }
    
    func applyContentColorPalette(_ palette: NftDetailsContentPalette) -> Bool {
        let keyColor = palette.baseColor
        let valueColor = palette.baseColor
        let separatorColor = palette.baseColor.withAlphaComponent(0.2)
        
        for row in rows {
            row.separatorView?.lineLayer.backgroundColor = separatorColor.cgColor
            row.keyLabel.textColor = keyColor
            row.valueLabel.textColor = valueColor
        }
        
        keyColumnSeparatorView.backgroundColor = separatorColor
        keyColumnBackgroundView.backgroundColor = palette.subtleBackgroundColor
        backgroundView.fillColor = palette.subtleBackgroundColor
        backgroundView.edgeColor = palette.edgeColor
        return false
    }
}

// MARK: - NftDetailsTileBackground

private extension UILabel {
    func setText(_ text: String?, font: UIFont, lineHeight: CGFloat) {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
        
        attributedText = NSAttributedString(
            string: text ?? "",
            attributes: [
                .font: font,
                .paragraphStyle: style
            ]
        )
    }
}

extension WScalableButton: NftDetailsContentColorConsumer {
    func applyContentColorPalette(_ palette: NftDetailsContentPalette) -> Bool {
        imageTintColor = palette.baseColor
        titleColor = palette.baseColor
        fillColor = palette.subtleBackgroundColor
        highlightedFillColor = palette.highlightColor
        edgeColor = palette.edgeColor
        return false
    }
}
