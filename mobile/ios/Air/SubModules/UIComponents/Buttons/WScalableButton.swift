//
//  WScalableButton.swift
//  MyTonWalletAir
//
//  Created by Sina on 11/22/24.
//

import UIKit
import WalletContext

public class WScalableButton: UIControl {
    public var onTap: (() -> Void)?

    private var titleLabelBottomConstraint: NSLayoutConstraint!
    private var titleLabelCenterYConstraint: NSLayoutConstraint!
    private var isCompact: Bool = false
    private let baseCornerRadius: CGFloat = 24
    
    public static let preferredHeight: CGFloat = 66

    public let imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.translatesAutoresizingMaskIntoConstraints = false
        view.tintColor = .tintColor
        return view
    }()

    public let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = WTheme.primaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        label.textAlignment = .center
        return label
    }()

    private lazy var containerView: UIView = {
        if #available(iOS 26, iOSApplicationExtension 26, *) {
            let effect = UIGlassEffect(style: .regular)
            effect.isInteractive = true
            effect.tintColor = WColors.folderFill
            let view = UIVisualEffectView(effect: effect)
            view.cornerConfiguration = .corners(radius: .init(floatLiteral: baseCornerRadius))
            return view
        }

        let view = UIView()
        view.backgroundColor = WTheme.groupedItem
        view.layer.cornerRadius = baseCornerRadius
        view.layer.cornerCurve = .continuous
        view.clipsToBounds = true
        view.isUserInteractionEnabled = false
        return view
    }()
    
    private var containerContentView: UIView {
        if #available(iOS 26, iOSApplicationExtension 26, *),
           let effectView = containerView as? UIVisualEffectView {
            effectView.contentView
        } else {
            containerView
        }
    }

    public init(title: String, image: UIImage?, onTap: (() -> Void)? = nil) {
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
    }
    
    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false

        containerView.translatesAutoresizingMaskIntoConstraints = false
        
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
            titleLabel.leadingAnchor.constraint(equalTo: containerContentView.leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: containerContentView.trailingAnchor, constant: -8),
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
            guard !IOS_26_MODE_ENABLED else { return }
            UIView.animate(withDuration: isHighlighted ? 0.1 : 0.3, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.containerView.backgroundColor = self.isHighlighted ? WTheme.highlight : WTheme.groupedItem
            }
        }
    }

    @objc private func didTap() {
        guard !consumeMenuShownTapIfNeeded() else { return }
        onTap?()
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            titleLabel.textColor = WTheme.primaryLabel
            imageView.tintColor = .tintColor
        }
    }
    
    public func attachMenu(presentOnTap: Bool = false, makeConfig: @escaping () -> MenuConfig) {
        let menuContext = MenuContext()
        menuContext.makeConfig = makeConfig
        menuContext.presentOnTap = presentOnTap
        menuContext.onGetSourceViewLayout = { [weak self]  in
            guard let self, window != nil, !bounds.isEmpty else { return nil }
            let baseFrame = convert(bounds, to: nil)
            return MenuSourceViewLayout(
                frame: baseFrame,
                portalMaskFrame: baseFrame.insetBy(dx: -100, dy: -100) // a space for shadow
            )
        }
        
        menuContext.onAppear = { [weak self] in
            guard let self else { return }
            
            // Reset current interaction session transfomations
            if #available(iOS 26, iOSApplicationExtension 26, *), let effectView = self.containerView as? UIVisualEffectView {
                effectView.effect = UIBlurEffect(style: .systemUltraThinMaterial)
                let effect = UIGlassEffect(style: .regular)
                effect.isInteractive = true
                effect.tintColor = WColors.folderFill
                effectView.effect = effect
            }
        }

        menuContext.onDismiss = { [weak self] in
            guard let self else { return }
            
            self.consumeMenuShownTapIfNeeded()
        }

        super.attachMenu(menuContext: menuContext)
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

open class ButtonsToolbar: UIView, WThemedView {
    private struct ArrangedView {
        let view: UIView
        let widthConstraint: NSLayoutConstraint
        let leadingConstraint: NSLayoutConstraint
    }
    
    private var arrangedSubviews: [ArrangedView] = []
    private var updateCounter: Int = 0
    private let minItemWidth: CGFloat = 100
    
    public var spacing: CGFloat = 10.0 {
        didSet {
            if oldValue != spacing {
                update()
            }
        }
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
        addSubview(view)
        let widthConstraint = view.widthAnchor.constraint(equalToConstant: minItemWidth)
        let leadingConstraint = view.leadingAnchor.constraint(equalTo: leadingAnchor)
        arrangedSubviews.append(.init(view: view, widthConstraint: widthConstraint, leadingConstraint: leadingConstraint))
        NSLayoutConstraint.activate([
             widthConstraint,
             leadingConstraint,
             view.heightAnchor.constraint(equalTo: heightAnchor)
        ])
        update()
    }
    
    nonisolated public func updateTheme() {
        MainActor.assumeIsolated {
            for btn in subviews {
                btn.tintColor = WTheme.tint
            }
        }
    }
    
    public override func layoutSubviews() {
        let width = bounds.width
        
        let visibleCount = arrangedSubviews.filter { !$0.view.isHidden }.count
        let visibleCountF = CGFloat(visibleCount)
        var itemWidth = visibleCount > 0 ? ((width - spacing * (visibleCountF - 1)) /  visibleCountF).rounded() : minItemWidth
        itemWidth = min(itemWidth, minItemWidth)
        
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
