import Combine
import UIKit
import WalletContext
import WalletCore

public final class MtwCardBackgroundView: UIView {
    private let cardView = UIView()
    private let imageView = UIImageView()
    private let borderView = CardBorderView()
    private var metalView: CardBackgroundMetalView?
    private var animationClock = CardBackgroundAnimationClock()
    private var snapshotGeneration = 0
    private var snapshotPending = false
    private var metadata: ApiNftMetadata?
    private var resolution = CardBackgroundResolution.full
    private var hasConfiguredImage = false
    private var seed: CardBackgroundSeed?
    private var baseImage: UIImage?
    private var surface = CardSurfaceConfiguration.current
    private var loadTask: Task<Void, Never>?
    private var animationRequested = false
    private var shineRequested = false
    private var light = CardSurfaceLight()
    private var animationObservation: AnyCancellable?
    private var suspensionObservation: AnyCancellable?

    public init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        cardView.backgroundColor = .air.groupedBackground
        cardView.layer.cornerRadius = 26
        cardView.layer.cornerCurve = .continuous
        cardView.layer.allowsEdgeAntialiasing = true
        cardView.clipsToBounds = true
        imageView.contentMode = .scaleToFill
        addSubview(cardView)
        cardView.addSubview(imageView)
        cardView.addSubview(borderView)
        animationObservation = CardBackgroundAnimationEnvironment.shared.objectWillChange
            .receive(on: RunLoop.main).sink { [weak self] in self?.updateAnimation() }
        // Capture before the queued environment update and before entering the
        // background, while GPU submissions are still allowed.
        suspensionObservation = CardBackgroundAnimationEnvironment.shared.willSuspend
            .sink { [weak self] _ in self?.stopAnimation() }
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func configure(nft: ApiNft?, hideBorder: Bool = false, borderWidthMultiplier: CGFloat = 1,
                          isAnimationEnabled: Bool = false, resolution: CardBackgroundResolution = .full,
                          isShineEnabled: Bool = false, surface: CardSurfaceConfiguration = .current) {
        borderView.configure(nft: nft, widthMultiplier: borderWidthMultiplier)
        borderView.isHidden = hideBorder
        animationRequested = isAnimationEnabled
        shineRequested = isShineEnabled
        let surface = surface.forArtwork(isCustom: nft?.isMtwCard == true)
        let artworkChanged = self.surface.defaultArtwork != surface.defaultArtwork
        let brushChanged = self.surface.radialBrush != surface.radialBrush
        self.surface = surface
        if artworkChanged, seed == nil {
            stopAnimation(preservingSnapshot: false)
            animationClock = CardBackgroundAnimationClock()
            if baseImage != nil { baseImage = CardDefaultBackground.artwork(surface.defaultArtwork).image }
            updateImage()
        }
        if brushChanged { updateImage() }
        guard !hasConfiguredImage || nft?.metadata != metadata || self.resolution != resolution else {
            updateAnimation()
            return
        }
        cancelImageLoading()
        hasConfiguredImage = true
        metadata = nft?.metadata
        self.resolution = resolution
        // A reused or loading card must already have a complete still before Metal starts.
        baseImage = CardDefaultBackground.artwork(surface.defaultArtwork).image
        updateImage()
        if let nft, nft.isMtwCard {
            cardView.backgroundColor = nft.metadata?.mtwCardTextType == .dark ? UIColor(white: 0.8, alpha: 1) : UIColor(white: 0.15, alpha: 1)
            loadTask = Task { [weak self] in
                guard let seed = try? await CardBackgroundNftSource.seed(for: nft), !Task.isCancelled,
                      let self, let image = try? CardBackgroundRenderer.shared.image(seed: seed, resolution: resolution) else { return }
                stopAnimation(preservingSnapshot: false)
                animationClock = CardBackgroundAnimationClock()
                self.seed = seed
                baseImage = image
                updateImage()
                setNeedsLayout()
                layoutIfNeeded()
                updateAnimation()
            }
        } else {
            cardView.backgroundColor = .air.groupedBackground
            layoutIfNeeded()
            updateAnimation()
        }
        setNeedsLayout()
    }

    public func cancelImageLoading() {
        loadTask?.cancel()
        loadTask = nil
        hasConfiguredImage = false
        seed = nil
        baseImage = nil
        imageView.image = nil
        stopAnimation(preservingSnapshot: false)
        animationClock = CardBackgroundAnimationClock()
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        updateAnimation()
    }

    public override var isHidden: Bool {
        didSet { updateAnimation() }
    }

    public func setLight(_ light: CardSurfaceLight) {
        let light = CardBackgroundAnimationEnvironment.shared.cardEffectsEnabled ? light : CardSurfaceLight()
        self.light = light
        metalView?.setLight(light)
    }

    private func updateImage() {
        imageView.image = baseImage.map { surface.radialBrush ? CardBrushTexture.applying(to: $0) : $0 }
    }

    private func updateAnimation() {
        let environment = CardBackgroundAnimationEnvironment.shared
        let shineEnabled = shineRequested && environment.cardEffectsEnabled
        if !environment.cardEffectsEnabled { light = CardSurfaceLight() }
        let policy = CardBackgroundMotionPolicy(requested: (animationRequested || shineEnabled) && resolution == .full,
            animationsEnabled: environment.animationsEnabled, lowPowerMode: environment.lowPowerMode,
            reduceMotion: environment.reduceMotion, applicationActive: environment.applicationActive,
            visible: window != nil && !isHidden)
        guard #available(iOS 17, *), policy.canAnimate, let image = baseImage else {
            // An explicit opt-out must not leave a frozen reflection in the still.
            let preserveSnapshot = environment.cardEffectsEnabled || !environment.applicationActive
            stopAnimation(preservingSnapshot: preserveSnapshot)
            if !preserveSnapshot { updateImage() }
            return
        }
        snapshotGeneration += 1
        snapshotPending = false
        if metalView == nil, let metal = CardBackgroundMetalView(image: image, seed: seed, defaultArtwork: surface.defaultArtwork, clock: animationClock) {
            metalView = metal
            metal.frame = imageView.frame
            cardView.insertSubview(metal, aboveSubview: imageView)
        }
        metalView?.configure(animateBackground: animationRequested, shine: shineEnabled, light: light, surface: surface)
    }

    private func stopAnimation(preservingSnapshot: Bool = true) {
        guard let metal = metalView else { return }
        if preservingSnapshot, snapshotPending { return }
        snapshotGeneration += 1
        let generation = snapshotGeneration
        animationClock = metal.clock
        metal.pause()
        guard preservingSnapshot, window != nil, !isHidden else {
            metal.removeFromSuperview()
            metalView = nil
            snapshotPending = false
            return
        }
        // If suspension has already happened, retain the frozen surface rather
        // than expose an older still or submit GPU work in the background.
        guard UIApplication.shared.applicationState != .background else { return }
        snapshotPending = true
        metal.snapshot { [weak self, weak metal] image in
            guard let self, let metal, metalView === metal, snapshotGeneration == generation else { return }
            snapshotPending = false
            guard let image else { return }
            imageView.image = image
            metal.removeFromSuperview()
            metalView = nil
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let width = max(0, min(bounds.width, bounds.height / CARD_RATIO))
        let size = CGSize(width: width, height: width * CARD_RATIO)
        let layoutFrame = CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
        cardView.frame = pixelAligned(layoutFrame)
        if let image = imageView.image, image.size.width > 0, image.size.height > 0 {
            let scale = max(size.width / image.size.width, size.height / image.size.height)
            let imageSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let frame = pixelAligned(CGRect(x: bounds.midX - imageSize.width / 2, y: bounds.midY - imageSize.height / 2, width: imageSize.width, height: imageSize.height))
            imageView.frame = frame.offsetBy(dx: -cardView.frame.minX, dy: -cardView.frame.minY)
        } else {
            imageView.frame = cardView.bounds
        }
        metalView?.frame = imageView.frame
        if metalView?.isPaused == true, !snapshotPending { metalView?.draw() }
        borderView.frame = cardView.bounds
    }

    private func pixelAligned(_ rect: CGRect) -> CGRect {
        let scale = traitCollection.displayScale
        guard scale > 0 else { return rect }
        let minX = (rect.minX * scale).rounded() / scale
        let minY = (rect.minY * scale).rounded() / scale
        let maxX = (rect.maxX * scale).rounded() / scale
        let maxY = (rect.maxY * scale).rounded() / scale
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

private final class CardBorderView: UIView {
    private let gradient = CAGradientLayer()
    private let highlight = CAGradientLayer()
    private let borderMask = CALayer()
    private var cardType: ApiMtwCardType?
    private var shine: ApiMtwCardBorderShineType?
    private var widthMultiplier: CGFloat = 1

    override init(frame: CGRect) {
        super.init(frame: frame)
        gradient.startPoint = CGPoint(x: 0.65, y: 0.1)
        gradient.endPoint = CGPoint(x: 0.45, y: 0.25)
        highlight.type = .radial
        highlight.startPoint = CGPoint(x: 0.5, y: 0.5)
        highlight.endPoint = CGPoint(x: 1, y: 1)
        highlight.colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor]
        borderMask.cornerRadius = 26
        borderMask.cornerCurve = .continuous
        borderMask.borderColor = UIColor.white.cgColor
        layer.addSublayer(gradient)
        layer.addSublayer(highlight)
        layer.mask = borderMask
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(nft: ApiNft?, widthMultiplier: CGFloat) {
        cardType = nft?.metadata?.mtwCardType
        shine = nft?.metadata?.mtwCardBorderShineType
        self.widthMultiplier = widthMultiplier
        updateColors()
        setNeedsLayout()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            updateColors()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        let dx = -0.2 * bounds.width * bounds.width
        let dy = 0.15 * bounds.height * bounds.height
        let length = 0.04 * bounds.width * bounds.width + 0.0225 * bounds.height * bounds.height
        let divisor = dx * dx + dy * dy
        if divisor > 0 {
            gradient.endPoint = CGPoint(x: 0.65 + dx * length / divisor, y: 0.1 + dy * length / divisor)
        }
        borderMask.contentsScale = traitCollection.displayScale
        borderMask.frame = bounds
        borderMask.borderWidth = (cardType == .black ? 2 : 1.333) * widthMultiplier
        highlight.bounds = bounds
        highlight.position = CGPoint(x: bounds.midX, y: bounds.midY)
        highlight.locations = [cardType == .black ? 0.1 : 0.05, 1]
        highlight.isHidden = highlightRotation == nil
        let rotation = (highlightRotation ?? 0) * .pi / 180
        highlight.setAffineTransform(
            CGAffineTransform(rotationAngle: rotation)
                .translatedBy(x: bounds.width * 0.5, y: 0)
                .scaledBy(x: cardType == .black ? 0.6 : 1, y: cardType == .black ? 1.3 : 0.5)
        )
        CATransaction.commit()
    }

    private var highlightRotation: CGFloat? {
        if cardType?.isPremium == true { return -45 }
        return switch shine {
        case .up: -80
        case .down: 70
        case .left: -190
        case .right: 10
        case .radioactive, nil: nil
        }
    }

    private func updateColors() {
        let colors: [UIColor]?
        if shine == .radioactive {
            colors = Array(repeating: UIColor(hex: "5CE850").withAlphaComponent(0.95), count: 2)
        } else {
            colors = switch cardType {
            case .black:
                [UIColor.white.withAlphaComponent(traitCollection.userInterfaceStyle == .dark ? 0.06 : 0.12),
                 UIColor.white.withAlphaComponent(traitCollection.userInterfaceStyle == .dark ? 0.12 : 0.24)]
            case .platinum:
                [UIColor(hex: "77777F").withAlphaComponent(0.4), UIColor.white.withAlphaComponent(0.4)]
            case .gold:
                [UIColor(hex: "4C3403").withAlphaComponent(0.4), UIColor(hex: "B07D1D").withAlphaComponent(0.4)]
            case .silver:
                [UIColor(hex: "272727").withAlphaComponent(0.4), UIColor(hex: "989898").withAlphaComponent(0.4)]
            case .standard:
                [UIColor(hex: "8C94B0").withAlphaComponent(0.5), UIColor(hex: "BABCC2").withAlphaComponent(0.85)]
            case nil: nil
            }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.colors = colors.map(premultipliedGradientColors)
        gradient.isHidden = colors == nil
        CATransaction.commit()
    }

    private func premultipliedGradientColors(_ colors: [UIColor]) -> [CGColor] {
        var r0: CGFloat = 0, g0: CGFloat = 0, b0: CGFloat = 0, a0: CGFloat = 0
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        colors[0].getRed(&r0, green: &g0, blue: &b0, alpha: &a0)
        colors[1].getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        if a0 == a1 { return colors.map(\.cgColor) }
        return (0...64).map { index in
            let t = CGFloat(index) / 64
            let alpha = a0 * (1 - t) + a1 * t
            guard alpha > 0 else { return UIColor.clear.cgColor }
            return UIColor(red: (r0 * a0 * (1 - t) + r1 * a1 * t) / alpha,
                           green: (g0 * a0 * (1 - t) + g1 * a1 * t) / alpha,
                           blue: (b0 * a0 * (1 - t) + b1 * a1 * t) / alpha,
                           alpha: alpha).cgColor
        }
    }

}
