import UIKit
import Kingfisher
import WalletCore
import WalletContext

public final class IconAccessoryView: UIView {
    private let imageView = WImageView()
    private let overlayView = GradientView()
    private let clockView = AccessoryClockView()
    private var sizeConstraints: [NSLayoutConstraint] = []
    private var positionConstraints: [NSLayoutConstraint] = []
    private var imageSize: CGFloat = 0

    public override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        isHidden = true
        layer.masksToBounds = true

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleToFill
        imageView.layer.masksToBounds = true
        addSubview(imageView)

        clockView.translatesAutoresizingMaskIntoConstraints = false
        clockView.isHidden = true
        imageView.addSubview(clockView)

        overlayView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.isUserInteractionEnabled = false
        overlayView.colors = [
            UIColor.white.withAlphaComponent(1),
            UIColor.white.withAlphaComponent(0)
        ]
        overlayView.gradientLayer.locations = [0, 1]
        overlayView.gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
        overlayView.gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        overlayView.gradientLayer.opacity = 0.5
        overlayView.gradientLayer.compositingFilter = "softLightBlendMode"
        overlayView.isHidden = true

        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        imageView.addSubview(overlayView)
        NSLayoutConstraint.activate([
            clockView.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            clockView.centerYAnchor.constraint(equalTo: imageView.centerYAnchor),
            clockView.widthAnchor.constraint(equalTo: imageView.widthAnchor),
            clockView.heightAnchor.constraint(equalTo: imageView.heightAnchor)
        ])
        NSLayoutConstraint.activate([
            overlayView.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
            overlayView.topAnchor.constraint(equalTo: imageView.topAnchor),
            overlayView.bottomAnchor.constraint(equalTo: imageView.bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    public func setShowsSoftLightOverlay(_ isVisible: Bool) {
        overlayView.isHidden = !isVisible
    }

    public func configureChain(_ chain: ApiChain) {
        setClockVisible(false)
        imageView.contentMode = .scaleToFill
        imageView.image = UIImage(named: "chain_\(chain.rawValue)", in: AirBundle, compatibleWith: nil)
        imageView.tintColor = nil
        imageView.backgroundColor = .clear
        setShowsSoftLightOverlay(false)
    }

    public func configurePending() {
        setClockVisible(true, backgroundColor: .airBundle("AccessoryOrange"))
        imageView.contentMode = .scaleToFill
        setShowsSoftLightOverlay(true)
    }

    public func configurePendingTrusted() {
        setClockVisible(true, backgroundColor: .airBundle("AccessoryGray"))
        imageView.contentMode = .scaleToFill
        setShowsSoftLightOverlay(true)
    }

    public func configureError() {
        setClockVisible(false)
        imageView.contentMode = .scaleToFill
        imageView.image = .airBundle("AccessoryError")
        imageView.tintColor = nil
        imageView.backgroundColor = .clear
        setShowsSoftLightOverlay(false)
    }

    public func configureHold() {
        setClockVisible(false)
        configureSymbol(name: "pause.fill", backgroundColor: .systemOrange)
        setShowsSoftLightOverlay(true)
    }

    public func configureExpired() {
        setClockVisible(false)
        configureSymbol(name: "stop.fill", backgroundColor: .systemRed)
        setShowsSoftLightOverlay(true)
    }

    public func configurePercentBadge(backgroundColor: UIColor = WTheme.positiveAmount) {
        setClockVisible(false)
        imageView.contentMode = .scaleToFill
        imageView.image = .airBundle("Percent")
        imageView.tintColor = .white
        imageView.backgroundColor = backgroundColor
        setShowsSoftLightOverlay(false)
    }

    public func reset() {
        imageView.kf.cancelDownloadTask()
        imageView.image = nil
        imageView.tintColor = nil
        imageView.backgroundColor = nil
        setClockVisible(false)
        setShowsSoftLightOverlay(false)
    }

    public func apply(size: CGFloat, borderWidth: CGFloat, borderColor: UIColor?, horizontalOffset: CGFloat, verticalOffset: CGFloat, in parent: UIView) {
        backgroundColor = borderColor
        imageSize = size
        if superview !== parent {
            parent.addSubview(self)
        }
        NSLayoutConstraint.deactivate(sizeConstraints + positionConstraints)
        sizeConstraints = [
            widthAnchor.constraint(equalToConstant: size + 2 * borderWidth),
            heightAnchor.constraint(equalToConstant: size + 2 * borderWidth),
            imageView.widthAnchor.constraint(equalToConstant: size),
            imageView.heightAnchor.constraint(equalToConstant: size)
        ]
        positionConstraints = [
            rightAnchor.constraint(equalTo: parent.rightAnchor, constant: horizontalOffset),
            bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: verticalOffset)
        ]
        NSLayoutConstraint.activate(sizeConstraints + positionConstraints)
        let cornerRadius = (size + 2 * borderWidth) / 2
        layer.cornerRadius = cornerRadius
        imageView.layer.cornerRadius = size / 2
        overlayView.gradientLayer.cornerRadius = imageView.layer.cornerRadius
    }

    private func configureSymbol(name: String, backgroundColor: UIColor) {
        let pointSize = max(1, imageSize * 0.55)
        let configuration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        imageView.preferredSymbolConfiguration = configuration
        imageView.contentMode = .center
        imageView.image = UIImage(systemName: name)
        imageView.tintColor = .white
        imageView.backgroundColor = backgroundColor
        imageView.layer.cornerRadius = imageSize / 2
    }

    private func setClockVisible(_ isVisible: Bool, backgroundColor: UIColor? = nil) {
        clockView.isHidden = !isVisible
        if isVisible {
            imageView.image = nil
            imageView.tintColor = nil
            imageView.backgroundColor = backgroundColor
            clockView.startAnimating()
        } else {
            clockView.stopAnimating()
        }
    }
}

private final class AccessoryClockView: UIView {
    let fastHand = CAShapeLayer()
    let slowHand = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear

        [slowHand, fastHand].forEach { hand in
            hand.fillColor = nil
            hand.strokeColor = UIColor.white.cgColor
            hand.lineCap = .round
            hand.lineJoin = .round
            layer.addSublayer(hand)
        }
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    func startAnimating() {
        let now = CACurrentMediaTime()
        if fastHand.animation(forKey: "spin") == nil {
            fastHand.add(spinAnimation(duration: 1, time: now), forKey: "spin")
        }
        if slowHand.animation(forKey: "spin") == nil {
            slowHand.add(spinAnimation(duration: 6, time: now), forKey: "spin")
        }
    }

    func stopAnimating() {
        fastHand.removeAllAnimations()
        slowHand.removeAllAnimations()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = min(bounds.width, bounds.height)
        guard size > 0 else { return }

        let lineWidth = max(1, size * 0.1)
        fastHand.lineWidth = lineWidth
        slowHand.lineWidth = lineWidth
        fastHand.frame = bounds
        slowHand.frame = bounds

        let radius = size / 2
        let fastLength = radius * 0.5
        let slowLength = radius * 0.33

        fastHand.path = handPath(length: fastLength)
        slowHand.path = handPath(length: slowLength)
    }

    func handPath(length: CGFloat) -> CGPath {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let tip = CGPoint(x: center.x, y: center.y - length)

        let path = UIBezierPath()
        path.move(to: center)
        path.addLine(to: tip)
        return path.cgPath
    }

    func spinAnimation(duration: Double, time: CFTimeInterval) -> CABasicAnimation {
        let progress = time.truncatingRemainder(dividingBy: duration) / duration
        let phase = Double.pi * 2 * progress
        let animation = CABasicAnimation(keyPath: "transform.rotation.z")
        animation.fromValue = phase
        animation.toValue = phase + Double.pi * 2
        animation.duration = duration
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        return animation
    }
}
