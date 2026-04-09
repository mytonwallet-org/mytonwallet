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
    private var cornerRadius: CGFloat = -1
    private var retryCount = 0
    private var retryWorkItem: DispatchWorkItem?
    private let maxRetryCount = 20

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
    
    weak var delegate: NftDetailsItemCoverFlowTileDelegate?
    weak var thumbnailDownloader: ImageDownloader?
    weak var colorCache: NftDetailsColorCache?

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

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),

            spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
        
        let longTapRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongTap))
        longTapRecognizer.minimumPressDuration = 0.25
        addGestureRecognizer(longTapRecognizer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func handleTap() {
        guard let model else { return }
        delegate?.nftDetailsItemCoverFlowTile(self, didSelectModel: model, longTap: false)
    }

    @objc private func handleLongTap() {
        guard let model else { return }
        delegate?.nftDetailsItemCoverFlowTile(self, didSelectModel: model, longTap: true)
    }

    func prepareForCollectionViewReuse() {
        cancelRetry()
        spinner.stopAnimating()
        spinner.color = .secondaryLabel
        imageView.image = nil
        imageView.backgroundColor = .air.groupedItem
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
                            self.spinner.stopAnimating()
                            self.imageView.backgroundColor = nil
                        case let .failure(error):
                            if error.isTaskCancelled || error.isNotCurrentTask {
                               return // let's ignore this, still show loading
                            }
                            self.scheduleRetry(for: model)
                        }
                    }
                }
            )
        } else {
            spinner.stopAnimating()
            imageView.image = NftDetailsImage.noImagePlaceholderImage()
            imageView.backgroundColor = nil
        }
    }
    
    private func scheduleRetry(for model: NftDetailsItemModel) {
        guard self.model === model, imageView.image == nil else { return }
        guard retryCount < maxRetryCount else {
            updateAsfFailedDownload()
            return
        }
        retryCount += 1
        let delay = min(Double(retryCount) * 2.0, 15.0)
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.model === model, self.imageView.image == nil else { return }
            self.startOrResumeThumbnailLoad(for: model)
        }
        retryWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func updateAsfFailedDownload() {
        spinner.stopAnimating()
        imageView.image = NftDetailsImage.errorPlaceholderImage()
        imageView.backgroundColor = nil
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

    func configure(with model: NftDetailsItemModel, tileCornerRadius: CGFloat) {
        if tileCornerRadius != cornerRadius {
            assert(cornerRadius < 0, "Set it only once: \(cornerRadius)")
            cornerRadius = tileCornerRadius
            layer.cornerRadius = tileCornerRadius
            imageView.layer.cornerRadius = tileCornerRadius
        }

        if self.model !== model {
            cancelRetry()
            retryCount = 0
            removeLottieViewer()

            self.model = model
            imageView.alpha = 1
            imageView.image = nil

            let cachedColor = colorCache?.color(forKey: model.id)
            imageView.backgroundColor = cachedColor ?? .air.groupedItem
            applySpinnerStyle(for: cachedColor)

            applySelectionDrivenLottie(for: model)
            selectionSubscription = .init(model: model, event: .selectionStatusChanged, tag: "CoverFlowTile") { [weak self] in
                guard let self, self.model === model else { return }
                DispatchQueue.main.async {
                    self.applySelectionDrivenLottie(for: model)
                }
            }
            setNeedsLayout()
        }
        
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
                let viewer = NftDetailsLottieViewer(cornerRadius: cornerRadius, frame: imageView.frame)
                viewer.playbackTransitionDelegate = self
                viewer.embedAbove(imageView)
                lottieViewer = viewer
            }
            lottieViewer?.setUrl(url, playAlways: true)
        } else {
            removeLottieViewer()
        }
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
