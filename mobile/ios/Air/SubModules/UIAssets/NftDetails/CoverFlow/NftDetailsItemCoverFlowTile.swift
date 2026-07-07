import UIKit
import Kingfisher
import WalletContext

protocol NftDetailsItemCoverFlowTileDelegate: AnyObject {
    func nftDetailsItemCoverFlowTile(_ tile: NftDetailsItemCoverFlowTile, didSelectModel model: NftDetailsItemModel, longTap: Bool)
    func nftDetailsItemCoverFlowTileGetActiveState(_ tile: NftDetailsItemCoverFlowTile) -> Bool
}

class NftDetailsItemCoverFlowTile: UIView {
    private var model: NftDetailsItemModel?
    private var lottieViewer: NftDetailsLottieViewer?
    private var selectionSubscription: NftDetailsItemModel.Subscription?
    private var cornerRadius: CGFloat?
    private var retryCount = 0
    private var retryWorkItem: DispatchWorkItem?
    private let maxRetryCount = 20
    private var imageLoadSucceeded = false

    private let imageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.backgroundColor = .air.groupedItem
        iv.clipsToBounds = true
        iv.layer.masksToBounds = true
        return iv
    }()

    private let spinner: UIActivityIndicatorView = {
        let s = UIActivityIndicatorView(style: .medium)
        s.hidesWhenStopped = true
        s.color = .secondaryLabel
        return s
    }()

    private let forSaleTagView = NftForSaleTagView()
    private var forSaleTagTopConstraint: NSLayoutConstraint?
    private var forSaleTagTrailingConstraint: NSLayoutConstraint?

    private var processedImageSubscription: NftDetailsItemModel.Subscription?
    private var displayStateSubscription: NftDetailsItemModel.Subscription?

    weak var delegate: NftDetailsItemCoverFlowTileDelegate?
    weak var thumbnailDownloader: ImageDownloader?
    var colorResolver: NftDetailsColorResolver?

    init() {
        super.init(frame: .square(100))

        layer.masksToBounds = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowOpacity = 0.06
        layer.shadowRadius = 4

        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        
        spinner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(spinner)

        forSaleTagView.style = .compact
        addSubview(forSaleTagView)
        let forSaleTagTopConstraint = forSaleTagView.topAnchor.constraint(equalTo: topAnchor, constant: -NftForSaleTagView.Style.compact.topOverlap)
        let forSaleTagTrailingConstraint = forSaleTagView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -NftForSaleTagView.Style.compact.trailingInset)
        self.forSaleTagTopConstraint = forSaleTagTopConstraint
        self.forSaleTagTrailingConstraint = forSaleTagTrailingConstraint

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),

            spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor),

            forSaleTagTopConstraint,
            forSaleTagTrailingConstraint,
        ])

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
        
        let longTapRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongTap))
        longTapRecognizer.minimumPressDuration = 0.25
        addGestureRecognizer(longTapRecognizer)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStopLottieAnimationsNotification),
            name: .nftDetailsStopLottieAnimations,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleTap() {
        guard let model else { return }
        delegate?.nftDetailsItemCoverFlowTile(self, didSelectModel: model, longTap: false)
    }

    @objc private func handleLongTap() {
        guard let model else { return }
        delegate?.nftDetailsItemCoverFlowTile(self, didSelectModel: model, longTap: true)
    }

    @objc private func handleStopLottieAnimationsNotification() {
        removeLottieViewer()
    }

    func prepareForCollectionViewReuse() {
        cancelRetry()
        imageLoadSucceeded = false
        spinner.stopAnimating()
        spinner.color = .secondaryLabel
        imageView.image = nil
        imageView.backgroundColor = .air.groupedItem
        forSaleTagView.isHidden = true
        forSaleTagTrailingConstraint?.constant = -NftForSaleTagView.Style.compact.trailingInset

        // Reset visibility driven by external state. The selected tile is hidden behind the preview via
        // `setSelectedTileVisible` (tile `alpha = 0`), and lottie playback fades the underlay image
        // (`imageView.alpha = 0`). Neither is reset by the steps above, so a recycled cell could come
        // back fully transparent. `removeLottieViewer` also restores `imageView.alpha`.
        removeLottieViewer()
        alpha = 1
        imageView.alpha = 1
    }
    
    private func cancelRetry() {
        retryWorkItem?.cancel()
        retryWorkItem = nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, let model = model {
            startOrResumeThumbnailLoad(for: model)
        }
    }

    private func startOrResumeThumbnailLoad(for model: NftDetailsItemModel) {
        guard self.model === model else { return }
        cancelRetry()

        if let url = model.item.coverflowImageUrl {
            spinner.startAnimating()
            
            var options: KingfisherOptionsInfo = [
                .targetCache(.default),
                .originalCache(.default),
                .alsoPrefetchToMemory,
                .cacheOriginalImage,
                .transition(.fade(0.22)),
            ]
            if let d = thumbnailDownloader {
                options.append(.downloader(d))
            }
            
            imageView.kf.setImage(
                with: .network(url),
                placeholder: nil,
                options: options,
                completionHandler: { [weak self] result in
                    guard let self, self.model === model else { return }
                    DispatchQueue.main.async {
                        switch result {
                        case .success:
                            self.imageLoadSucceeded = true
                            self.spinner.stopAnimating()
                            self.imageView.backgroundColor = nil
                        case let .failure(error):
                            if error.isTaskCancelled || error.isNotCurrentTask {
                               return // let's ignore this, still show loading
                            }
                            if error.isNotFound {
                                self.updateAsFailedDownload()
                                return
                            }
                            self.scheduleRetry(for: model)
                        }
                    }
                }
            )
        } else {
            updateAsFailedDownload()
        }
    }
    
    private func scheduleRetry(for model: NftDetailsItemModel) {
        guard self.model === model, !imageLoadSucceeded else { return }
        guard retryCount < maxRetryCount else {
            updateAsFailedDownload()
            return
        }
        retryCount += 1
        let delay = min(Double(retryCount) * 2.0, 15.0)
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.model === model, !self.imageLoadSucceeded else { return }
            self.startOrResumeThumbnailLoad(for: model)
        }
        retryWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func showPlaceholderImage(_ image: UIImage?) {
        spinner.stopAnimating()
        UIView.transition(with: imageView, duration: 0.22, options: .transitionCrossDissolve) {
            self.imageView.image = image
            self.imageView.backgroundColor = nil
        }
    }

    private func updateAsFailedDownload() {
        showPlaceholderImage(NftDetailsImage.noImagePlaceholderImage())
    }

    private func applySpinnerStyle(for backgroundColor: UIColor?) {
        guard let color = backgroundColor else {
            spinner.color = .secondaryLabel
            return
        }
        spinner.color = color.isLightColor
            ? UIColor(white: 0.15, alpha: 0.7)  
            : UIColor(white: 1.0,  alpha: 0.8)
    }

    private func updateOverlays(for model: NftDetailsItemModel, animated: Bool = false) {
        forSaleTagView.isHidden = !model.isOnSale
        bringSubviewToFront(forSaleTagView)
    }

    func configure(with model: NftDetailsItemModel, tileCornerRadius: CGFloat) {
        if tileCornerRadius != cornerRadius {
            assert(cornerRadius == nil, "Set it only once")
            cornerRadius = tileCornerRadius
            layer.cornerRadius = tileCornerRadius
            imageView.layer.cornerRadius = tileCornerRadius
        }

        if self.model !== model {
            cancelRetry()
            retryCount = 0
            imageLoadSucceeded = false
            removeLottieViewer()

            self.model = model
            imageView.alpha = 1
            imageView.image = nil

            let color = colorResolver?.currentBaseColor(for: model) ?? UIColor.air.groupedItem
            imageView.backgroundColor = color
            applySpinnerStyle(for: color)

            applySelectionDrivenLottie(for: model)
            selectionSubscription = .init(model: model, event: .selectionStatusChanged, tag: "CoverFlowTile") { [weak self] in
                guard let self, self.model === model else { return }
                DispatchQueue.main.async {
                    self.applySelectionDrivenLottie(for: model)
                }
            }
            processedImageSubscription = .init(model: model, event: .processedImageUpdated, tag: "CoverFlowTile/Color") { [weak self] in
                guard let self, self.model === model else { return }
                DispatchQueue.main.async {
                    self.updateOverlays(for: model)
                }
            }
            displayStateSubscription = .init(model: model, event: .displayStateChanged, tag: "CoverFlowTile/DisplayState") { [weak self] in
                guard let self, self.model === model else { return }
                DispatchQueue.main.async {
                    self.updateOverlays(for: model, animated: true)
                }
            }
            setNeedsLayout()
        }
        
        updateOverlays(for: model)

        if window != nil {
            startOrResumeThumbnailLoad(for: model)
        }
    }

    private func removeLottieViewer() {
        lottieViewer?.cancelForHostRemoval()
        lottieViewer?.removeFromSuperview()
        lottieViewer = nil
        imageView.alpha = 1
    }

    private func applySelectionDrivenLottie(for model: NftDetailsItemModel) {
        guard self.model === model else { return }
        if model.isSelected, let url = model.item.lottieUrl, delegate?.nftDetailsItemCoverFlowTileGetActiveState(self) == true {
            if lottieViewer == nil {
                let viewer = NftDetailsLottieViewer(cornerRadius: layer.cornerRadius, frame: imageView.frame)
                viewer.playbackTransitionDelegate = self
                viewer.embedAbove(imageView)
                lottieViewer = viewer
            }
            lottieViewer?.setUrl(url, playAlways: true)
        } else {
            removeLottieViewer()
        }
        bringSubviewToFront(forSaleTagView)
    }
}

extension NftDetailsItemCoverFlowTile: NftDetailsLottieViewerDelegate {
    func nftDetailsLottieViewer(_ viewer: NftDetailsLottieViewer, requestFadeOutUnderlay continuePlayback: @escaping () -> Void) {
        NftDetailsLottieViewer.runDefaultFadeOutUnderlay(viewer: viewer, imageView: imageView, continuePlayback: continuePlayback)
    }

    func nftDetailsLottieViewer(_ viewer: NftDetailsLottieViewer, requestFadeInUnderlay finished: @escaping () -> Void) {
        NftDetailsLottieViewer.runDefaultFadeInUnderlay(viewer: viewer, imageView: imageView, finished: finished)
    }
}
