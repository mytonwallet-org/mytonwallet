import UIKit
import Kingfisher
import WalletCore
import WalletContext

public final class IconAccessoryView: UIView {
    private let imageView = WImageView()
    private let overlayView = GradientView()
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

    public func configureChain(_ chain: String) {
        imageView.contentMode = .scaleToFill
        imageView.image = UIImage(named: "chain_\(chain)", in: AirBundle, compatibleWith: nil)
        imageView.tintColor = nil
        imageView.backgroundColor = .clear
        setShowsSoftLightOverlay(false)
    }

    public func configureChain(_ chain: ApiChain) {
        configureChain(chain.rawValue)
    }

    public func configurePending() {
        imageView.contentMode = .scaleToFill
        imageView.image = .airBundle("AccessoryPending")
        imageView.tintColor = nil
        imageView.backgroundColor = .clear
        setShowsSoftLightOverlay(false)
    }

    public func configurePendingTrusted() {
        imageView.contentMode = .scaleToFill
        imageView.image = .airBundle("AccessoryPendingTrusted")
        imageView.tintColor = nil
        imageView.backgroundColor = .clear
        setShowsSoftLightOverlay(false)
    }

    public func configureError() {
        imageView.contentMode = .scaleToFill
        imageView.image = .airBundle("AccessoryError")
        imageView.tintColor = nil
        imageView.backgroundColor = .clear
        setShowsSoftLightOverlay(false)
    }

    public func configureHold() {
        configureSymbol(name: "pause.fill", backgroundColor: .systemOrange)
        setShowsSoftLightOverlay(true)
    }

    public func configureExpired() {
        configureSymbol(name: "stop.fill", backgroundColor: .systemRed)
        setShowsSoftLightOverlay(true)
    }

    public func configurePercentBadge(backgroundColor: UIColor = WTheme.positiveAmount) {
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
}
