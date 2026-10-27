import UIKit
import CoreImage
import UIComponents

#if DEBUG
private let showDebugMarker = false
#endif

class NftDetailsItemPreview: UIView, NftDetailsFullScreenOverlayContent {

    struct LayoutGeometry {
        let collapsedSize: CGSize
        let collapsedCornerRadius: CGFloat
    }
    
    let layoutGeometry: LayoutGeometry

    private var widthConstraint: NSLayoutConstraint!
    private var heightConstraint: NSLayoutConstraint!
    private let imageView = UIImageView()
    private let realImageView = UIImageView()
    private var imageAspectConstraint: NSLayoutConstraint?
    private let imageContainer = UIView()
    private let atmosphereContainer = UIView()
    private let atmosphereView = UIView()
    private let atmosphereEdgeView = UIView()
    private var expandedWidth: CGFloat = 400
    private var atmosphereHeightRatio: CGFloat = 0.5

    func setAtmosphereHeight(_ height: CGFloat, pageWidth: CGFloat) {
        expandedWidth = pageWidth
        let ratio = height / max(1, pageWidth)
        guard atmosphereHeightRatio != ratio else { return }
        atmosphereHeightRatio = ratio
        if case .loaded(let processed) = model?.processedImageState {
            setAtmosphereImage(processed.atmosphere(height: height, pageWidth: pageWidth)?.image)
        }
        setNeedsLayout()
    }
    private var imageContainerHeightConstraint: NSLayoutConstraint!
    private var expandedAspectRatio: CGFloat = 1
    private var model: NftDetailsItemModel?
    private var processedImageSubscription: NftDetailsItemModel.Subscription?
    private var isRealImage = false
    private var lottieViewer: NftDetailsLottieViewer?
    private var liveBlurDisplayLink: CADisplayLink?
    private(set) var isRenderingPageTransition = false

    /// The header masks this live view during paging; never rasterize full video frames.
    func beginPageTransition() -> Bool {
        guard let viewer = lottieViewer, !viewer.isHidden else { return false }
        isRenderingPageTransition = true
        isUserInteractionEnabled = false
        return true
    }

    func endPageTransition() {
        isRenderingPageTransition = false
    }
    private var baseColor: UIColor = .clear
    private let spinner = UIActivityIndicatorView(style: .large)
    private var isExpanded: Bool = false
    
    #if DEBUG
    private let debugMarker = UIView()
    #endif

    var centerYConstraint: NSLayoutConstraint?
    var centerXConstraint: NSLayoutConstraint?

    init(layoutGeometry: LayoutGeometry) {
        self.layoutGeometry = layoutGeometry
        super.init(frame: .fromSize(layoutGeometry.collapsedSize))
        
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setup() {
        clipsToBounds = false
        isAccessibilityElement = true
        accessibilityTraits = .image
        accessibilityIdentifier = "NFTPreview"

        imageContainer.clipsToBounds = true
        imageContainer.layer.cornerRadius = layoutGeometry.collapsedCornerRadius
        imageContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageContainer)

        imageView.clipsToBounds = false
        imageView.backgroundColor = .clear
        imageView.contentMode = .scaleToFill
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageContainer.addSubview(imageView)
        
        realImageView.contentMode = .scaleToFill
        realImageView.isHidden = false
        realImageView.translatesAutoresizingMaskIntoConstraints = false
        realImageView.layer.masksToBounds = true
        realImageView.layer.cornerRadius = layoutGeometry.collapsedCornerRadius
        imageContainer.insertSubview(realImageView, belowSubview: imageView)

        imageContainerHeightConstraint = imageContainer.heightAnchor.constraint(equalTo: widthAnchor, multiplier: 1.0)
        widthConstraint = widthAnchor.constraint(equalToConstant: layoutGeometry.collapsedSize.width)
        heightConstraint = heightAnchor.constraint(equalToConstant: layoutGeometry.collapsedSize.height)
        
        NSLayoutConstraint.activate([
            imageContainer.topAnchor.constraint(equalTo: topAnchor),
            imageContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageContainerHeightConstraint,
            
            imageView.topAnchor.constraint(equalTo: imageContainer.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: imageContainer.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: imageContainer.trailingAnchor),

            realImageView.topAnchor.constraint(equalTo: imageContainer.topAnchor),
            realImageView.leadingAnchor.constraint(equalTo: imageContainer.leadingAnchor),
            realImageView.trailingAnchor.constraint(equalTo: imageContainer.trailingAnchor),
            realImageView.widthAnchor.constraint(equalTo: realImageView.heightAnchor),
            
            widthConstraint,
            heightConstraint,
        ])
        
        atmosphereContainer.clipsToBounds = true
        atmosphereContainer.isUserInteractionEnabled = false
        atmosphereContainer.accessibilityIdentifier = "NFTAtmosphere"
        atmosphereContainer.addSubview(atmosphereEdgeView)
        atmosphereContainer.addSubview(atmosphereView)
        addSubview(atmosphereContainer)

        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        #if DEBUG
        if showDebugMarker {
            debugMarker.backgroundColor = .red
            debugMarker.translatesAutoresizingMaskIntoConstraints = false
            imageContainer.addSubview(debugMarker)
            NSLayoutConstraint.activate([
                debugMarker.centerXAnchor.constraint(equalTo: centerXAnchor),
                debugMarker.centerYAnchor.constraint(equalTo: centerYAnchor),
                debugMarker.widthAnchor.constraint(equalToConstant: 8),
                debugMarker.heightAnchor.constraint(equalToConstant: 8)
            ])
            addSubview(debugMarker)
        }
        #endif
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        // The lower band belongs to the same Core Animation tree as the artwork.
        // Its full image scales with the square, while collapse crops it away.
        // There is no display-link geometry tracking or separate opacity clock.
        let height = bounds.width * atmosphereHeightRatio
        let overlap = bounds.width / expandedWidth * NftDetailsImageProcessor.atmosphereOverlap
        atmosphereContainer.frame = CGRect(x: 0, y: bounds.width - overlap,
            width: bounds.width, height: isExpanded ? height + overlap : 0)
        atmosphereEdgeView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: overlap)
        atmosphereView.frame = CGRect(x: 0, y: overlap, width: bounds.width, height: height)
    }

    private func updateDebugMarker() {
    #if DEBUG
        if showDebugMarker {
            debugMarker.backgroundColor = isRealImage ? .green : .red
        }
    #endif
    }
    
    func selectModel(_ model: NftDetailsItemModel ) {
        guard model !== self.model else { return }

        cancelLottiePlayback()

        self.model = model
        accessibilityLabel = model.name

        processedImageSubscription = .init(model: model, event: .processedImageUpdated, tag: "Page/Preview") { [weak self] in
            guard let self, self.model === model else { return }
            DispatchQueue.main.async {
                self.applyProcessedImageState()
            }
        }
        self.applyProcessedImageState()
    }

    /// Starts loading and playing the Lottie animation for the current model. No-op if the model has no Lottie URL.
    /// Retain the renderer after playback so changing presentation never restarts it.
    func startLottiePlayback() -> Bool {
        guard let model, let url = model.item.lottieUrl else {
            return false
        }
        
        if lottieViewer == nil {
            let viewer = NftDetailsLottieViewer(cornerRadius: 0, frame: bounds)
            adoptLottieViewer(viewer)
        }
        
        lottieViewer?.setUrl(url)
        return true
    }

    func adoptLottieViewer(_ viewer: NftDetailsLottieViewer) {
        guard lottieViewer !== viewer else { return }
        cancelLottiePlayback()
        viewer.removeFromSuperview()
        viewer.playbackTransitionDelegate = self
        viewer.translatesAutoresizingMaskIntoConstraints = false
        insertSubview(viewer, belowSubview: atmosphereContainer)
        NSLayoutConstraint.activate([
            viewer.topAnchor.constraint(equalTo: imageContainer.topAnchor),
            viewer.leadingAnchor.constraint(equalTo: imageContainer.leadingAnchor),
            viewer.trailingAnchor.constraint(equalTo: imageContainer.trailingAnchor),
            viewer.heightAnchor.constraint(equalTo: imageContainer.widthAnchor),
        ])
        viewer.backgroundColor = baseColor
        viewer.setCornerRadius(imageContainer.layer.cornerRadius)
        lottieViewer = viewer
        imageContainer.alpha = viewer.isHidden ? 1 : 0
        if !viewer.isHidden { startLiveBlur() }
        setNeedsLayout()
    }

    /// Transfer ownership without changing the animation's frame or playback clock.
    func takeLottieViewer() -> NftDetailsLottieViewer? {
        let viewer = lottieViewer
        lottieViewer = nil
        viewer?.removeFromSuperview()
        liveBlurDisplayLink?.invalidate()
        liveBlurDisplayLink = nil
        endPageTransition()
        model?.liveAtmosphereImage = nil
        imageContainer.alpha = 1
        return viewer
    }

    func cancelLottiePlayback() {
        endPageTransition()
        guard lottieViewer != nil else { return }
        lottieViewer?.cancelForHostRemoval()
        lottieViewer?.removeFromSuperview()
        lottieViewer = nil
        liveBlurDisplayLink?.invalidate()
        liveBlurDisplayLink = nil
        model?.liveAtmosphereImage = nil
        imageContainer.alpha = 1
    }

    fileprivate func refreshAnimatedBlur() {
        guard let viewer = lottieViewer, window != nil,
              let snapshot = viewer.lowerBandSnapshot(height: NftDetailsImageProcessor.atmosphereSourceBandHeight * bounds.width / expandedWidth, background: baseColor),
              let source = CIImage(image: snapshot) else { return }
        let sourceScale = source.extent.width / expandedWidth
        let atmosphere = NftDetailsImageProcessor.atmosphere(from: source,
            height: expandedWidth * atmosphereHeightRatio * sourceScale, scale: sourceScale, color: baseColor, displayScale: screenScale)
        if let image = NftDetailsImageProcessor.atmosphereContext.createCGImage(atmosphere, from: atmosphere.extent) {
            let image = UIImage(cgImage: image)
            setAtmosphereImage(image)
            // While the native page is masked, the backdrop contains only the
            // other NFT. Its Metal composition need not rebuild for video ticks.
            if !isRenderingPageTransition { model?.liveAtmosphereImage = image }
        }
    }

    private func setAtmosphereImage(_ image: UIImage?) {
        let split = NftDetailsImageProcessor.atmosphereOverlap
            / (expandedWidth * atmosphereHeightRatio + NftDetailsImageProcessor.atmosphereOverlap)
        // Separate the overlap above the artwork edge from the reflected tail
        // so expansion/collapse can clip the tail without stretching the feather.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        atmosphereEdgeView.layer.contents = image?.cgImage
        atmosphereView.layer.contents = image?.cgImage
        atmosphereEdgeView.layer.contentsRect = CGRect(x: 0, y: 0, width: 1, height: split)
        atmosphereView.layer.contentsRect = CGRect(x: 0, y: split, width: 1, height: 1 - split)
        CATransaction.commit()
    }

    private func startLiveBlur() {
        liveBlurDisplayLink?.invalidate()
        // Capture after Core Animation has committed the first displayed frame.
        // Rendering the uncommitted model tree can contain opaque black tiles.
        let link = CADisplayLink(target: NftLiveBlurTarget(owner: self), selector: #selector(NftLiveBlurTarget.tick))
        link.preferredFramesPerSecond = 30
        link.add(to: .main, forMode: .common)
        liveBlurDisplayLink = link
    }

    private func updateSpinner() {
        if let model, !imageContainer.isHidden {
            switch model.processedImageState {
            case .loaded, .failed:
                spinner.stopAnimating()
            case .loading, .idle:
                spinner.startAnimating()
            }
        } else {
            spinner.stopAnimating()
        }
    }

    private func applyProcessedImageState() {
        if let model {
            switch model.processedImageState {
            case .loaded(let processed):
                baseColor = processed.atmosphereColor ?? processed.baseColor ?? .clear
                imageContainer.backgroundColor = isRealImage ? .clear : baseColor
                setImage(processed.artworkPreviewImage, processed.originalImage)
                setAtmosphereImage(model.liveAtmosphereImage ?? processed.atmosphere(
                    height: expandedWidth * atmosphereHeightRatio, pageWidth: expandedWidth)?.image)
                spinner.stopAnimating()
            case .loading, .idle:
                setImage(nil, nil)
                spinner.startAnimating()
            case .failed:
                let badImage = NftDetailsImage.noImagePlaceholderImage()
                setImage(badImage, badImage)
                spinner.stopAnimating()
            }
        }
        updateSpinner()
    }
    
    func setImageHidden(_ isHidden: Bool) {
        endPageTransition()
        imageContainer.isHidden = isHidden
        atmosphereContainer.isHidden = isHidden
        #if DEBUG
        debugMarker.isHidden = isHidden
        #endif
        isUserInteractionEnabled = !isHidden
        updateSpinner()
        if isHidden {
            cancelLottiePlayback()
        }
    }
    
    private func setImage(_ image: UIImage?, _ originalImage: UIImage?) {
        imageView.image = image
        realImageView.image = originalImage
        updateImageAspectConstraint(image)
        updateImageContainerHeight()
        setNeedsLayout()
        layoutIfNeeded()
    }
    
    func switchToRealImage(_ isRealImage: Bool, animated: Bool = false, duration: TimeInterval = NftDetailsMediaMotion.duration, completion: (() -> Void)? = nil) {
        guard self.isRealImage != isRealImage else { completion?(); return }
        self.isRealImage = isRealImage
        imageView.isHidden = false
        realImageView.isHidden = false
        let changes = {
            self.imageView.alpha = isRealImage ? 0 : 1
            self.imageContainer.backgroundColor = isRealImage ? .clear : self.baseColor
            self.atmosphereContainer.alpha = isRealImage ? 0 : 1
            // Keep a solid sharp image underneath the dissolving atmosphere.
            // Fading both layers would briefly expose the page between them.
            self.realImageView.alpha = 1
        }
        if animated {
            UIView.animate(withDuration: duration, delay: 0,
                           options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut], animations: changes,
                           completion: { _ in completion?() })
        } else {
            imageView.layer.removeAllAnimations()
            realImageView.layer.removeAllAnimations()
            atmosphereContainer.layer.removeAllAnimations()
            changes()
            completion?()
        }
        updateDebugMarker()
    }
    
    private func heightOverWidth(for image: UIImage?) -> CGFloat {
        guard let w = image?.size.width, let h = image?.size.height, w > 0 else { return 1 }
        return h / w
    }

    private func updateImageAspectConstraint(_ image: UIImage?) {
        imageAspectConstraint?.isActive = false
        imageAspectConstraint = nil
        expandedAspectRatio = heightOverWidth(for: image)

        imageAspectConstraint = imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor, multiplier: expandedAspectRatio)
        imageAspectConstraint?.priority = .required
        imageAspectConstraint?.isActive = true
    }
    
    private func updateImageContainerHeight() {
        imageContainerHeightConstraint.isActive = false
        imageContainerHeightConstraint = imageContainer.heightAnchor.constraint(
            equalTo: widthAnchor,
            multiplier: isExpanded ? expandedAspectRatio : 1.0
        )
        imageContainerHeightConstraint.isActive = true
    }

    func prepareToExpandAnimation(expandedWidth: CGFloat) {
        isExpanded = true
        self.expandedWidth = expandedWidth
        updateImageContainerHeight()
        widthConstraint.constant = expandedWidth
        heightConstraint.constant = expandedWidth
    }
    
    func prepareToCollapseAnimation(expandedWidth: CGFloat) {
        isExpanded = false
        
        widthConstraint.constant = layoutGeometry.collapsedSize.width
        heightConstraint.constant = layoutGeometry.collapsedSize.height
        updateImageContainerHeight()
    }
    
    func runCornerRadiusAnimation(duration: TimeInterval, expandedWidth: CGFloat, isExpand: Bool) {
        UIView.animate(withDuration: duration, delay: 0,
                       options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut]) {
            let radius = isExpand ? 0 : self.layoutGeometry.collapsedCornerRadius
            self.imageContainer.layer.cornerRadius = radius
            self.realImageView.layer.cornerRadius = radius
            self.lottieViewer?.setCornerRadius(radius)
        }
    }

}

extension NftDetailsItemPreview: NftDetailsLottieViewerDelegate {
    func nftDetailsLottieViewer(_ viewer: NftDetailsLottieViewer, requestFadeOutUnderlay continuePlayback: @escaping () -> Void) {
        viewer.isHidden = false
        // Keep the live reflection above the animation in the same moving preview.
        imageContainer.alpha = 0
        setNeedsLayout()
        layoutIfNeeded()
        continuePlayback()
        startLiveBlur()
    }

    func nftDetailsLottieViewer(_ viewer: NftDetailsLottieViewer, requestFadeInUnderlay finished: @escaping () -> Void) {
        liveBlurDisplayLink?.invalidate()
        liveBlurDisplayLink = nil
        model?.liveAtmosphereImage = nil
        NftDetailsLottieViewer.runDefaultFadeInUnderlay(viewer: viewer, imageView: imageContainer, finished: finished)
    }
}

@MainActor
private final class NftLiveBlurTarget: NSObject {
    weak var owner: NftDetailsItemPreview?
    init(owner: NftDetailsItemPreview) { self.owner = owner }
    @objc func tick(_ link: CADisplayLink) {
        guard let owner else { link.invalidate(); return }
        owner.refreshAnimatedBlur()
    }
}
