import Kingfisher
import UIKit
import WalletContext
import WalletCore

public final class MtwCardPromotionView: UIView {
    private let artwork = UIView()
    private let backgroundImage = UIImageView(image: .airBundle("PromoCardBg"))
    private let mascotContainer = UIView()
    private let mascotImage = UIImageView()
    private let foregroundImage = UIImageView(image: .airBundle("PromoCardOverlay"))
    private var promotion: ApiPromotion?
    private var mascot: ApiPromotion.CardOverlay.MascotIcon?
    private var imageURL: URL?
    private var hasConfigured = false
    private var configurationGeneration = 0

    public init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        artwork.alpha = 0
        addSubview(artwork)
        for image in [backgroundImage, mascotImage, foregroundImage] {
            image.layer.allowsEdgeAntialiasing = true
        }
        artwork.addSubview(backgroundImage)
        artwork.addSubview(mascotContainer)
        mascotContainer.addSubview(mascotImage)
        artwork.addSubview(foregroundImage)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func configure(promotion: ApiPromotion?, animated: Bool = true) {
        let next = promotion?.kind == .cardOverlay && promotion?.cardOverlay?.onClickAction == .openPromotionModal
            ? promotion : nil
        guard !hasConfigured || self.promotion != next else { return }
        configurationGeneration += 1
        let generation = configurationGeneration
        let shouldAnimate = animated && hasConfigured && window != nil && self.promotion?.id != next?.id
        let isInsertion = self.promotion == nil && next != nil
        hasConfigured = true
        self.promotion = next

        if let next {
            mascot = next.cardOverlay?.mascotIcon
            updateImage()
            if isInsertion {
                UIView.performWithoutAnimation {
                    setNeedsLayout()
                    layoutIfNeeded()
                }
            }
        }
        let changes = {
            self.artwork.alpha = next == nil ? 0 : 1
            self.setNeedsLayout()
            self.layoutIfNeeded()
        }
        let completion: (Bool) -> Void = { [weak self] _ in
            guard let self, self.configurationGeneration == generation, self.promotion == nil else { return }
            clearImage()
        }
        if shouldAnimate {
            if #available(iOS 17, *) {
                UIView.animate(springDuration: 0.3, bounce: 0, initialSpringVelocity: 0, delay: 0,
                               options: [.allowUserInteraction, .beginFromCurrentState],
                               animations: changes, completion: completion)
            } else {
                UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0,
                               options: [.allowUserInteraction, .beginFromCurrentState],
                               animations: changes, completion: completion)
            }
        } else {
            UIView.performWithoutAnimation(changes)
            completion(true)
        }
    }

    public func prepareForReuse() {
        configurationGeneration += 1
        promotion = nil
        hasConfigured = false
        artwork.layer.removeAllAnimations()
        mascotContainer.layer.removeAllAnimations()
        artwork.alpha = 0
        clearImage()
    }

    private func updateImage() {
        let url = mascot?.url.nilIfEmpty.flatMap(URL.init(string:))
        guard imageURL != url else { return }
        mascotImage.kf.cancelDownloadTask()
        mascotImage.layer.removeAllAnimations()
        mascotImage.image = nil
        imageURL = url
        if let url {
            mascotImage.kf.setImage(with: url, options: [.transition(.fade(0.15))]) { [weak self] _ in
                self?.setNeedsLayout()
            }
        }
    }

    private func clearImage() {
        mascotImage.kf.cancelDownloadTask()
        mascotImage.layer.removeAllAnimations()
        mascotImage.image = nil
        imageURL = nil
        mascot = nil
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        artwork.frame = bounds
        // The SwiftUI images have intrinsic sizes and stay on the physical right in RTL.
        for image in [backgroundImage, foregroundImage] {
            let size = image.image?.size ?? .zero
            let displayScale = max(traitCollection.displayScale, 1)
            let x = ((bounds.width - size.width) * displayScale).rounded() / displayScale
            image.frame = CGRect(x: x, y: 0, width: size.width, height: size.height)
        }
        if let mascot {
            let size = CGSize(width: mascot.width * 1.072, height: mascot.height * 1.075)
            let displayScale = max(traitCollection.displayScale, 1)
            let proposal = CGSize(width: (size.width * displayScale).rounded() / displayScale,
                                  height: (size.height * displayScale).rounded() / displayScale)
            let origin = CGPoint(x: bounds.width - size.width, y: 0)
            let alignedOriginX = (origin.x * displayScale).rounded() / displayScale
            // SwiftUI pixel-aligns the frame before resolving the rotation anchor.
            mascotContainer.bounds = CGRect(origin: .zero, size: proposal)
            mascotContainer.center = CGPoint(x: alignedOriginX + proposal.width / 2 + mascot.right,
                                             y: proposal.height / 2 - mascot.top)
            let direction: CGFloat = effectiveUserInterfaceLayoutDirection == .rightToLeft ? -1 : 1
            mascotContainer.transform = CGAffineTransform(rotationAngle: direction * mascot.rotation * .pi / 180)
            if let image = mascotImage.image, image.size.width > 0, image.size.height > 0 {
                let scale = min(proposal.width / image.size.width, proposal.height / image.size.height)
                let imageSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                let frame = CGRect(x: origin.x + (proposal.width - imageSize.width) / 2,
                                   y: (proposal.height - imageSize.height) / 2,
                                   width: imageSize.width, height: imageSize.height)
                // SwiftUI fits and pixel-aligns the image before rotating its fixed-size frame.
                mascotImage.frame = pixelAligned(frame).offsetBy(dx: -alignedOriginX, dy: 0)
            }
        }
    }

    private func pixelAligned(_ rect: CGRect) -> CGRect {
        let scale = max(traitCollection.displayScale, 1)
        let minX = (rect.minX * scale).rounded() / scale
        let minY = (rect.minY * scale).rounded() / scale
        let maxX = (rect.maxX * scale).rounded() / scale
        let maxY = (rect.maxY * scale).rounded() / scale
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        setNeedsLayout()
    }
}
