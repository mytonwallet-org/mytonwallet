import UIKit

class NftDetailsItemPreview: UIView {
    private let model: NftDetailsItemModel
    private var processedImageSubscription: NftDetailsItemModel.Subscription?

    private let imageView = UIImageView()
    private var lottieViewer: NftDetailsLottieViewer?
    
    private var imageAspectRatio: CGFloat = 1
    private var heightLayoutConstraint: NSLayoutConstraint!

    private let spinner: UIActivityIndicatorView = {
        let s = UIActivityIndicatorView(style: .large)
        s.hidesWhenStopped = true
        return s
    }()
    
    override var isHidden: Bool {
        didSet {
            if isHidden != oldValue {
                if model.processedImageState.isLoading {
                    spinner.startAnimating()
                }
            }
        }
    }
    
    init(model: NftDetailsItemModel) {
        self.model = model
        
        super.init(frame: .square(100))

        clipsToBounds = false

        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        spinner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(spinner)

        heightLayoutConstraint = imageView.heightAnchor.constraint(equalToConstant: frame.size.height)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            heightLayoutConstraint,

            spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    
    var isSubscribed: Bool = false {
        didSet {
            if oldValue != isSubscribed {
                if isSubscribed {
                    applyProcessedImageState()
                    processedImageSubscription = .init(model: model, event: .processedImageUpdated, tag: "Page/Preview") { [weak self] in
                        guard let self, self.model === model else { return }
                        DispatchQueue.main.async {
                            self.applyProcessedImageState()
                        }
                    }
                } else {
                    processedImageSubscription = nil
                    imageView.image = nil
                }
            }
        }
    }
    
    override func didMoveToWindow() {
        super.didMoveToWindow()
        
        if window != nil {
            applyProcessedImageState()
        } else {
            imageView.image = nil
        }
    }

    private func removeLottieViewer() {
        lottieViewer?.cancelForHostRemoval()
        lottieViewer?.removeFromSuperview()
        lottieViewer = nil
        imageView.alpha = 1
    }

    private func applyLottieState() {
        guard let url = model.lottieUrl else {
            removeLottieViewer()
            return
        }
        if lottieViewer == nil {
            let viewer = NftDetailsLottieViewer(cornerRadius: 0, frame: imageView.frame, tag: "PREVIEW(\(model.name))")
            viewer.playbackTransitionDelegate = self
            viewer.translatesAutoresizingMaskIntoConstraints = false
            insertSubview(viewer, aboveSubview: imageView)
            NSLayoutConstraint.activate([
                viewer.topAnchor.constraint(equalTo: imageView.topAnchor),
                viewer.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
                viewer.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
                viewer.heightAnchor.constraint(equalTo: viewer.widthAnchor),
            ])
            
            lottieViewer = viewer
        }
        lottieViewer?.setUrl(url, playAlways: true)
    }
    
    func playLottieIfPossible() {
        applyLottieState()
    }

    private func applyProcessedImageState() {
        switch model.processedImageState {
        case .loaded(let processed):
            setProcessedImage(processed)
            spinner.stopAnimating()
        case .idle, .loading:
            setProcessedImage(nil)
            spinner.startAnimating()
        case .failed:
            setProcessedImage(.init(previewImage: NftDetailsImage.errorPlaceholderImage(), backgroundPattern: nil, baseColor: nil))
            spinner.stopAnimating()
        }
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setProcessedImage(_ image: NftDetailsImage.Processed?) {
        let uiImage = image?.previewImage
        imageView.alpha = 1
        imageView.image = uiImage
        if let imageSize = uiImage?.size, imageSize.width > 0 {
            imageAspectRatio = imageSize.height / imageSize.width
        } else {
            imageAspectRatio = 1
        }
        heightLayoutConstraint?.isActive = false
        heightLayoutConstraint = imageView.heightAnchor.constraint(
            equalTo: imageView.widthAnchor,
            multiplier: imageAspectRatio
        )
        heightLayoutConstraint?.isActive = true
    }
}

extension NftDetailsItemPreview: NftDetailsLottieViewerDelegate {
    func nftDetailsLottieViewer(_ viewer: NftDetailsLottieViewer, requestFadeOutUnderlay continuePlayback: @escaping () -> Void) {
        NftDetailsLottieViewer.runDefaultFadeOutUnderlay(viewer: viewer, imageView: imageView, continuePlayback: continuePlayback)
    }

    func nftDetailsLottieViewer(_ viewer: NftDetailsLottieViewer, requestFadeInUnderlay finished: @escaping () -> Void) {
        NftDetailsLottieViewer.runDefaultFadeInUnderlay(viewer: viewer, imageView: imageView, finished: finished)
    }
}
