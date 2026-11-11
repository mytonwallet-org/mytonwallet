import UIKit
import WalletContext

public final class WInteractiveGlassButton: WButton {
    private let glassView = WGlassView(cornerRadius: nil)
    public let glassTitleLabel = UILabel()
    private let glassImageView = UIImageView()
    private var outgoingTitleLabels: [UILabel] = []
    public var glassContentView: UIView { glassView.contentView }
    public private(set) var glassTintColor: UIColor = .clear

    public func configureInteractiveGlass(tintColor: UIColor, foregroundColor: UIColor) {
        glassTitleLabel.font = customTitleFont ?? WButton.font(for: style)
        glassTitleLabel.text = title(for: .normal)
        glassTitleLabel.textColor = foregroundColor
        glassTitleLabel.textAlignment = .center
        glassTitleLabel.numberOfLines = 2
        glassImageView.image = image(for: .normal)
        glassImageView.tintColor = foregroundColor
        glassImageView.contentMode = .center
        configuration = nil
        backgroundColor = .clear
        glassView.contentView.addSubview(glassTitleLabel)
        glassView.contentView.addSubview(glassImageView)
        if glassView.superview == nil {
            glassView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(glassTapped)))
            addSubview(glassView)
        }
        setGlassTintColor(tintColor)
        setNeedsLayout()
    }

    public override func setTitle(_ title: String?, for state: UIControl.State) {
        super.setTitle(title, for: state)
        if state == .normal {
            finishTitleTransition()
            glassTitleLabel.text = title
        }
    }

    public func setTitle(_ title: String?, animated: Bool) {
        guard animated, TradeMotion.enabled, window != nil, !glassTitleLabel.bounds.isEmpty,
              let previousText = glassTitleLabel.text, !previousText.isEmpty, let title, !title.isEmpty else {
            setTitle(title, for: .normal)
            return
        }
        guard previousText != title else { return }
        let previous = UILabel()
        previous.font = glassTitleLabel.font
        previous.textColor = glassTitleLabel.textColor
        previous.textAlignment = glassTitleLabel.textAlignment
        previous.numberOfLines = glassTitleLabel.numberOfLines
        previous.lineBreakMode = glassTitleLabel.lineBreakMode
        previous.text = previousText
        if let attributedText = glassTitleLabel.attributedText { previous.attributedText = attributedText }
        previous.isAccessibilityElement = false
        previous.bounds = glassTitleLabel.bounds
        previous.center = glassTitleLabel.center
        let visible = glassTitleLabel.layer.presentation()
        previous.alpha = CGFloat(visible?.opacity ?? Float(glassTitleLabel.alpha))
        previous.transform = visible?.affineTransform() ?? glassTitleLabel.transform
        glassContentView.addSubview(previous)
        outgoingTitleLabels.append(previous)

        super.setTitle(title, for: .normal)
        glassTitleLabel.layer.removeAllAnimations()
        glassTitleLabel.text = title
        glassTitleLabel.alpha = 0
        glassTitleLabel.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
        UIView.animate(withDuration: 0.28, delay: 0, options: [.allowUserInteraction, .curveEaseInOut]) {
            previous.alpha = 0
            previous.transform = CGAffineTransform(scaleX: 1.04, y: 1.04)
            self.glassTitleLabel.alpha = 1
            self.glassTitleLabel.transform = .identity
        } completion: { [weak self, weak previous] _ in
            previous?.removeFromSuperview()
            self?.outgoingTitleLabels.removeAll { $0 === previous }
        }
    }

    func finishTitleTransition() {
        outgoingTitleLabels.forEach { $0.removeFromSuperview() }
        outgoingTitleLabels.removeAll()
        glassTitleLabel.layer.removeAllAnimations()
        glassTitleLabel.alpha = 1
        glassTitleLabel.transform = .identity
    }

    public override func setImage(_ image: UIImage?, for state: UIControl.State) {
        super.setImage(image, for: state)
        if state == .normal { glassImageView.image = image }
    }

    public func setGlassTintColor(_ color: UIColor) {
        glassTintColor = color
        glassView.setTint(color)
    }

    func setGlassMaterialized(_ isMaterialized: Bool) {
        glassView.setMaterialized(isMaterialized)
    }

    public override var isEnabled: Bool {
        didSet {
            glassView.isUserInteractionEnabled = isEnabled
            glassView.contentView.alpha = isEnabled ? 1 : 0.5
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        titleLabel?.isHidden = true
        imageView?.isHidden = true
        glassView.frame = bounds
        let titleFrame = glassView.bounds.insetBy(dx: 12, dy: 0)
        for label in [glassTitleLabel] + outgoingTitleLabels {
            label.bounds = CGRect(origin: .zero, size: titleFrame.size)
            label.center = CGPoint(x: titleFrame.midX, y: titleFrame.midY)
        }
        glassImageView.frame = glassView.bounds
        if #unavailable(iOS 26) { glassView.layer.cornerRadius = bounds.height / 2 }
    }

    @objc private func glassTapped() {
        guard isEnabled else { return }
        sendActions(for: [.touchUpInside, .primaryActionTriggered])
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { finishTitleTransition() }
    }
}
