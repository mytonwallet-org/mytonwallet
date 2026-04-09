import UIKit

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
    private var imageContainerHeightConstraint: NSLayoutConstraint!
    private var expandedAspectRatio: CGFloat = 1
    private var model: NftDetailsItemModel?
    private var processedImageSubscription: NftDetailsItemModel.Subscription?
    private var isRealImage = false
    private var lottieViewer: NftDetailsLottieViewer?
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
        realImageView.isHidden = true
        realImageView.translatesAutoresizingMaskIntoConstraints = false
        realImageView.layer.masksToBounds = true
        realImageView.layer.cornerRadius = layoutGeometry.collapsedCornerRadius
        imageContainer.addSubview(realImageView)

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

        processedImageSubscription = .init(model: model, event: .processedImageUpdated, tag: "Page/Preview") { [weak self] in
            guard let self, self.model === model else { return }
            DispatchQueue.main.async {
                self.applyProcessedImageState()
            }
        }
        self.applyProcessedImageState()
    }

    /// Starts loading and playing the Lottie animation for the current model. No-op if the model has no Lottie URL.
    /// The viewer is removed automatically after one successful playback cycle, or earlier via `cancelLottiePlayback()`.
    func startLottiePlayback() -> Bool {
        guard let model, let url = model.item.lottieUrl else {
            return false
        }
        
        if lottieViewer == nil {
            let viewer = NftDetailsLottieViewer(cornerRadius: 0, frame: bounds)
            viewer.playbackTransitionDelegate = self
            viewer.translatesAutoresizingMaskIntoConstraints = false
            insertSubview(viewer, aboveSubview: imageContainer)
            NSLayoutConstraint.activate([
                viewer.topAnchor.constraint(equalTo: imageContainer.topAnchor),
                viewer.leadingAnchor.constraint(equalTo: imageContainer.leadingAnchor),
                viewer.trailingAnchor.constraint(equalTo: imageContainer.trailingAnchor),
                viewer.heightAnchor.constraint(equalTo: imageContainer.widthAnchor),
            ])
            lottieViewer = viewer
        }
        
        lottieViewer?.setUrl(url, playAlways: true)
        return true
    }

    func cancelLottiePlayback() {
        guard lottieViewer != nil else { return }
        lottieViewer?.cancelForHostRemoval()
        lottieViewer?.removeFromSuperview()
        lottieViewer = nil
        imageContainer.alpha = 1
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
                setImage(processed.previewImage, processed.originalImage)
                spinner.stopAnimating()
            case .loading, .idle:
                setImage(nil, nil)
                spinner.startAnimating()
            case .failed:
                let badImage = NftDetailsImage.errorPlaceholderImage()
                setImage(badImage, badImage)
                spinner.stopAnimating()
            }
        }
        updateSpinner()
    }
    
    func setImageHidden(_ isHidden: Bool) {
        imageContainer.isHidden = isHidden
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
    
    func switchToRealImage(_ isRealImage: Bool) {
        self.isRealImage = isRealImage
        imageView.isHidden = isRealImage
        realImageView.isHidden = !isRealImage
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
        let expandStageThreshold = 0.5
        
        let imageContainerLayer = imageContainer.layer
        let realImageLayer = realImageView.layer
        if isExpand {
            UIView.animateKeyframes(
                withDuration: duration,
                delay: 0,
                options: [.calculationModeCubic, .beginFromCurrentState, .overrideInheritedDuration]
            ) {
                UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: expandStageThreshold) {
                    let radius = self.calcCornerRadius(expandedWidth: expandedWidth, progress: expandStageThreshold)
                    imageContainerLayer.cornerRadius = radius
                    realImageLayer.cornerRadius = radius
                }
                UIView.addKeyframe(withRelativeStartTime: expandStageThreshold, relativeDuration: 1.0 - expandStageThreshold) {
                    imageContainerLayer.cornerRadius = 0
                    realImageLayer.cornerRadius = 0
                }
            }
        } else {
            UIView.animateKeyframes(
                withDuration: duration,
                delay: 0,
                options: [.calculationModeCubic, .beginFromCurrentState, .overrideInheritedDuration]
            ) {
                UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: expandStageThreshold) {
                    let radius = self.calcCornerRadius(expandedWidth: expandedWidth, progress: expandStageThreshold)
                    imageContainerLayer.cornerRadius = radius
                    realImageLayer.cornerRadius = radius
                }
                UIView.addKeyframe(withRelativeStartTime: expandStageThreshold, relativeDuration: 1.0 - expandStageThreshold) {
                    imageContainerLayer.cornerRadius = self.layoutGeometry.collapsedCornerRadius
                    realImageLayer.cornerRadius = self.layoutGeometry.collapsedCornerRadius
                }
            }
        }
    }
    
    private func calcCornerRadius(expandedWidth: CGFloat, progress: CGFloat) -> CGFloat {
        return layoutGeometry.collapsedCornerRadius * progress * expandedWidth / layoutGeometry.collapsedSize.width
    }
}

extension NftDetailsItemPreview: NftDetailsLottieViewerDelegate {
    func nftDetailsLottieViewer(_ viewer: NftDetailsLottieViewer, requestFadeOutUnderlay continuePlayback: @escaping () -> Void) {
        viewer.isHidden = false
        imageContainer.alpha = 0
        continuePlayback()
    }

    func nftDetailsLottieViewer(_ viewer: NftDetailsLottieViewer, requestFadeInUnderlay finished: @escaping () -> Void) {
        imageContainer.alpha = 1
        finished()
        cancelLottiePlayback()
    }
}
