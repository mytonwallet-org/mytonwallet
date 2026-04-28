//
//  WScalableButton.swift
//  MyTonWalletAir
//
//  Created by Sina on 11/22/24.
//

import UIKit
import WalletContext

public class WScalableButton: UIControl {
    
    public enum Style {
        case standard, thinGlass
    }
    
    public var onTap: (() -> Void)?

    public let style: Style
    
    /// If nil then UIColor.label is used
    public var titleColor: UIColor? {
        didSet {
            titleLabel.textColor = titleColor
        }
    }

    /// If nil then .tintColor is used
    public var imageTintColor: UIColor? {
        didSet {
            imageView.tintColor = imageTintColor
        }
    }
    
    public var fillColor: UIColor? {
        didSet {
            assert(style == .thinGlass)
            thinGlassView?.fillColor = fillColor
        }
    }

    public var highlightedFillColor: UIColor? {
        didSet {
            assert(style == .thinGlass)
        }
    }

    public var edgeColor: UIColor? {
        didSet {
            assert(style == .thinGlass)
            thinGlassView?.edgeColor = edgeColor
        }
    }

    private var titleLabelBottomConstraint: NSLayoutConstraint!
    private var titleLabelCenterYConstraint: NSLayoutConstraint!
    private var isCompact: Bool = false
    public static let preferredHeight: CGFloat = 66
    public static let preferredCornerRadius: CGFloat = 24

    private let baseCornerRadius: CGFloat = WScalableButton.preferredCornerRadius
    private var suppressNextTap: Bool = false

    private let imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.translatesAutoresizingMaskIntoConstraints = false
        view.tintColor = .tintColor
        return view
    }()

    private let baseTitleLabelFont = UIFont.systemFont(ofSize: 13, weight: .medium)
    private let titleLabelHorMargin: CGFloat = 8

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.font = baseTitleLabelFont
        label.textColor = UIColor.label
        label.translatesAutoresizingMaskIntoConstraints = false
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        label.textAlignment = .center
        return label
    }()

    private lazy var containerView: UIView = {
        switch style {
        case .standard:
            if #available(iOS 26, iOSApplicationExtension 26, *) {
                let effect = UIGlassEffect(style: .regular)
                effect.isInteractive = true
                effect.tintColor = UIColor.air.folderFill
                let view = UIVisualEffectView(effect: effect)
                view.cornerConfiguration = .corners(radius: .init(floatLiteral: baseCornerRadius))
                return view
            }
            
            let view = UIView()
            view.backgroundColor = .air.groupedItem
            view.layer.cornerRadius = baseCornerRadius
            view.layer.cornerCurve = .continuous
            view.clipsToBounds = true
            view.isUserInteractionEnabled = false
            return view
            
        case .thinGlass:
            let view = ThinGlassView()
            view.isUserInteractionEnabled = false
            return view
        }
    }()
    
    private var thinGlassView: ThinGlassView? {
        guard let cv = containerView as? ThinGlassView else {
            assertionFailure()
            return nil
        }
        return cv
    }
    
    private var containerContentView: UIView {
        switch style {
        case .standard:
            if #available(iOS 26, iOSApplicationExtension 26, *), let effectView = containerView as? UIVisualEffectView {
                effectView.contentView
            } else {
                containerView
            }
        case .thinGlass:
            containerView
        }
    }

    public init(title: String, image: UIImage?, style: Style = .standard, onTap: (() -> Void)? = nil) {
        self.style = style
        self.onTap = onTap
        super.init(frame: .zero)
        setup()
        configure(title: title, image: image)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure(title: String, image: UIImage?) {
        titleLabel.text = title
        imageView.image = image
        accessibilityLabel = title
    }
    
    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        isAccessibilityElement = true
        accessibilityTraits = .button

        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.isAccessibilityElement = false
        imageView.isAccessibilityElement = false
        titleLabel.isAccessibilityElement = false
        
        containerContentView.addSubview(imageView)
        containerContentView.addSubview(titleLabel)

        addSubview(containerView)

        titleLabelBottomConstraint = titleLabel.bottomAnchor.constraint(equalTo: containerContentView.bottomAnchor, constant: -9)
        titleLabelCenterYConstraint = titleLabel.centerYAnchor.constraint(equalTo: containerContentView.centerYAnchor)
        
        NSLayoutConstraint.activate([
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),
                  
            imageView.centerXAnchor.constraint(equalTo: containerContentView.centerXAnchor, constant: 0),
            imageView.centerYAnchor.constraint(equalTo: containerContentView.centerYAnchor, constant: -10),
            
            titleLabelBottomConstraint,
            titleLabel.leadingAnchor.constraint(equalTo: containerContentView.leadingAnchor, constant: titleLabelHorMargin),
            titleLabel.trailingAnchor.constraint(equalTo: containerContentView.trailingAnchor, constant: -titleLabelHorMargin),
        ])

        addTarget(self, action: #selector(didTap), for: .touchUpInside)
        
        if #available(iOS 26, iOSApplicationExtension 26, *) {
            let g = UITapGestureRecognizer(target: self, action: #selector(didTap))
            containerView.addGestureRecognizer(g)
        }
    }

    public override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.preferredHeight)
    }

    public override var isHighlighted: Bool {
        didSet {
            switch style {
            case .standard:
                guard !IOS_26_MODE_ENABLED else { return }
                UIView.animate(withDuration: isHighlighted ? 0.1 : 0.3, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                    self.containerView.backgroundColor = self.isHighlighted ? .air.highlight : .air.groupedItem
                }
            case .thinGlass:
                UIView.animate(withDuration: isHighlighted ? 0.1 : 0.3, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                    let fillColor = self.fillColor
                    var effectiveFillColor = fillColor
                    var transform: CGAffineTransform = .identity
                    if self.isHighlighted {
                        effectiveFillColor = self.highlightedFillColor ?? fillColor?.withAlphaComponent(max(fillColor?.alpha ?? 0, 0.2))
                        let scale: CGFloat = 1.15
                        transform = CGAffineTransform(scaleX: scale, y: scale)
                    }
                    self.thinGlassView?.fillColor = effectiveFillColor
                    self.transform = transform
                }
            }
        }
    }

    @objc private func didTap() {
        guard !consumeSuppressedTapIfNeeded() else { return }
        onTap?()
    }

    @discardableResult
    public func consumeSuppressedTapIfNeeded() -> Bool {
        let suppressNextTap = self.suppressNextTap
        self.suppressNextTap = false
        return suppressNextTap
    }

    public func cancelCurrentInteractionAndSuppressNextTap() {
        suppressNextTap = true
        cancelTracking(with: nil)
        isHighlighted = false
        switch style {
        case .standard:
            if #available(iOS 26, iOSApplicationExtension 26, *),
               let effectView = self.containerView as? UIVisualEffectView {
                effectView.effect = UIBlurEffect(style: .systemUltraThinMaterial)
                let effect = UIGlassEffect(style: .regular)
                effect.isInteractive = true
                effect.tintColor = UIColor.air.folderFill
                effectView.effect = effect
            }
        case .thinGlass:
            transform = .identity
        }
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            if titleColor == nil {
                titleLabel.textColor = UIColor.label
            }
            if imageTintColor == nil {
                imageView.tintColor = .tintColor
            }
        }
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()

        let height = bounds.height
        let scale = height < Self.preferredHeight ? height / Self.preferredHeight : 1
        set(scale: scale)
    }

    private func set(scale: CGFloat) {
        let radius = baseCornerRadius * scale
        
        if #available(iOS 26, iOSApplicationExtension 26, *),
           let effectView = containerView as? UIVisualEffectView {
            effectView.alpha = scale
            effectView.transform = CGAffineTransform(scaleX: scale, y: scale)
            effectView.cornerConfiguration = .corners(radius: UICornerRadius(floatLiteral: radius))
        } else {
            containerView.alpha = scale
            containerView.layer.cornerRadius = radius
            containerView.transform = CGAffineTransform(scaleX: scale, y: scale)
        }

        // Keeps label unscaled until some threshold
        let labelScale = 1 / max(scale, 0.7)
        titleLabel.transform = CGAffineTransform(scaleX: labelScale, y: labelScale)

        // Switch compact state
        let shouldCompact = scale < 0.9
        if shouldCompact != isCompact {
            isCompact = shouldCompact
            
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }

                UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
                    if shouldCompact {
                        self.imageView.alpha = 0
                        self.imageView.transform = CGAffineTransform(scaleX: 0.1, y: 0.1)
                    } else {
                        self.imageView.alpha = 1
                        self.imageView.transform = .identity
                    }
                    
                    self.titleLabelBottomConstraint.isActive = !shouldCompact
                    self.titleLabelCenterYConstraint.isActive = shouldCompact
                    self.layoutIfNeeded()
                }
            }
        }
    }
}

extension WScalableButton: ButtonsToolbarItem {

    public func onToolbarLayout(layoutContext: ButtonsToolbarLayoutContext) {
        guard let text = titleLabel.text?.nilIfEmpty else { return }
        switch layoutContext.pass {
        case .draft:
            let availableWidth = layoutContext.itemWidth - titleLabelHorMargin * 2
            let maxFont = self.maxFontSize(for: text, maxWidth: availableWidth)
            if let lFont = layoutContext.font {
                if lFont.pointSize > maxFont.pointSize {
                    layoutContext.font = maxFont
                }
            } else {
                layoutContext.font = maxFont
            }
        case .finalizing:
            titleLabel.font = layoutContext.font ?? baseTitleLabelFont
        }
    }

    private func maxFontSize(for text: String, maxWidth: CGFloat) -> UIFont {
        // In most cases the base font is good enough so we check it immediately
        let width = (text as NSString).size(withAttributes: [.font: baseTitleLabelFont]).width
        if width <= maxWidth {
            return baseTitleLabelFont
        }
        
        let minSize: CGFloat = 6
        let maxSize: CGFloat = baseTitleLabelFont.pointSize
        let tolerance: CGFloat = 0.5
        var low = minSize
        var high = maxSize
        while (high - low) > tolerance {
            let mid = (low + high) / 2
            let font = baseTitleLabelFont.withSize(mid)
            let width = (text as NSString).size(withAttributes: [.font: font]).width
            if width <= maxWidth {
                low = mid
            } else {
                high = mid
            }
        }
        return baseTitleLabelFont.withSize(low)
    }
}

// MARK: - Toolbar

@MainActor
public protocol ButtonsToolbarItem {
    func onToolbarLayout(layoutContext: ButtonsToolbarLayoutContext)
}

public class ButtonsToolbarLayoutContext {
    enum Pass {
        case draft
        case finalizing
    }
    
    var font: UIFont?
    var itemWidth: CGFloat
    var pass: Pass
    
    init(font: UIFont? = nil, itemWidth: CGFloat, pass: Pass) {
        self.font = font
        self.itemWidth = itemWidth
        self.pass = pass
    }
}

open class ButtonsToolbar: UIView {
    private struct ArrangedView {
        let view: UIView
        let widthConstraint: NSLayoutConstraint
        let leadingConstraint: NSLayoutConstraint
    }
    
    private var arrangedSubviews: [ArrangedView] = []
    private var updateCounter: Int = 0
    private let minItemWidth: CGFloat = 100
    
    public var spacing: CGFloat {
        didSet {
            if oldValue != spacing {
                update()
            }
        }
    }
    
    public override init(frame: CGRect) {
        spacing = screenWidth < 390 ? 8 : 10
        
        super.init(frame: frame)
    }
    
    @MainActor public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func beginUpdate() {
        updateCounter += 1
    }
    
    public func endUpdate() {
        updateCounter -= 1
        assert(updateCounter >= 0)
        if updateCounter <= 0 {
            updateCounter = 0
            setNeedsLayout()
        }
    }
    
    public func update() {
        beginUpdate()
        endUpdate()
    }
    
    public func addArrangedSubview(_ view: UIView) {
        beginUpdate()
        defer {
            endUpdate()
        }
        addSubview(view)
        view.tintColor = .tintColor
        let widthConstraint = view.widthAnchor.constraint(equalToConstant: minItemWidth)
        let leadingConstraint = view.leadingAnchor.constraint(equalTo: leadingAnchor)
        arrangedSubviews.append(.init(view: view, widthConstraint: widthConstraint, leadingConstraint: leadingConstraint))
        NSLayoutConstraint.activate([
             widthConstraint,
             leadingConstraint,
             view.heightAnchor.constraint(equalTo: heightAnchor)
        ])
    }
        
    public override func layoutSubviews() {
        let width = bounds.width
        
        let visibleItems = arrangedSubviews.filter { !$0.view.isHidden }
        let visibleCount = visibleItems.count
        let visibleCountF = CGFloat(visibleItems.count)
        var itemWidth = visibleCount > 0 ? ((width - spacing * (visibleCountF - 1)) /  visibleCountF).rounded() : minItemWidth
        itemWidth = min(itemWidth, minItemWidth)
        
        let context = ButtonsToolbarLayoutContext(font: nil, itemWidth: itemWidth, pass: .draft)
        visibleItems.forEach { arrangedView in
            if let item = arrangedView.view as? ButtonsToolbarItem {
                item.onToolbarLayout(layoutContext: context)
            }
        }
        context.pass = .finalizing
        visibleItems.forEach { arrangedView in
            if let item = arrangedView.view as? ButtonsToolbarItem {
                item.onToolbarLayout(layoutContext: context)
            }
        }
        
        var offsetX = max(0.0, ((width - visibleCountF * (itemWidth + spacing) + spacing) / 2).rounded())
        for btn in arrangedSubviews {
            btn.leadingConstraint.constant = offsetX
            btn.widthConstraint.constant = itemWidth
            if !btn.view.isHidden {
                offsetX += itemWidth + spacing
            }
        }
        
        super.layoutSubviews()
    }
}
