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
    private var retainPausedRenderer = false
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

    public static func prepareBackground(nft: ApiNft?) async {
        guard let nft, nft.isMtwCard, let seed = try? await CardBackgroundNftSource.seed(for: nft),
              !Task.isCancelled else { return }
        _ = try? CardBackgroundRenderer.shared.image(seed: seed)
        await Task.yield()
        guard !Task.isCancelled else { return }
        _ = try? CardBackgroundRenderer.shared.layers(seed: seed, showContrast: true)
    }

    public func configure(nft: ApiNft?, hideBorder: Bool = false, borderWidthMultiplier: CGFloat = 1,
                          isAnimationEnabled: Bool = false, resolution: CardBackgroundResolution = .full,
                          isShineEnabled: Bool = false, surface: CardSurfaceConfiguration = .current,
                          retainPausedRenderer: Bool = false) {
        borderView.configure(nft: nft, widthMultiplier: borderWidthMultiplier, motionEnabled: surface.motion?.borderShine == true && nft?.isMtwCard == true, showsDefaultBorder: surface.motion?.blueBorderShine == true)
        borderView.isHidden = hideBorder
        animationRequested = isAnimationEnabled
        shineRequested = isShineEnabled
        self.retainPausedRenderer = retainPausedRenderer
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
        borderView.setLight(light)
    }

    private func updateImage() {
        imageView.image = baseImage.map { surface.radialBrush ? CardBrushTexture.applying(to: $0) : $0 }
    }

    private func updateAnimation() {
        let environment = CardBackgroundAnimationEnvironment.shared
        let animationEnabled = animationRequested && environment.cardEffectsEnabled
        let shineEnabled = shineRequested && environment.cardEffectsEnabled
        if !environment.cardEffectsEnabled { light = CardSurfaceLight() }
        let policy = CardBackgroundMotionPolicy(requested: (animationEnabled || shineEnabled) && resolution == .full,
            animationsEnabled: environment.animationsEnabled, lowPowerMode: environment.lowPowerMode,
            reduceMotion: environment.reduceMotion, applicationActive: environment.applicationActive,
            visible: window != nil && !isHidden)
        guard #available(iOS 17, *), policy.canAnimate, let image = baseImage else {
            // Swiping or collapsing pauses this visible cell; neither is a resource exit.
            // Keep the presented drawable and clock; no GPU readback or rebuild.
            if retainPausedRenderer, environment.cardEffectsEnabled, environment.animationsEnabled,
               !environment.lowPowerMode, !environment.reduceMotion, environment.applicationActive,
               window != nil, !isHidden, let metal = metalView {
                snapshotGeneration += 1
                snapshotPending = false
                metal.pause()
                return
            }
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
        metalView?.configure(animateBackground: animationEnabled, shine: shineEnabled, light: light, surface: surface,
            animateResume: retainPausedRenderer)
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
        let rendererFrameChanged = metalView?.frame != imageView.frame
        metalView?.frame = imageView.frame
        if rendererFrameChanged, metalView?.isPaused == true, !snapshotPending { metalView?.draw() }
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
