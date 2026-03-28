import UIKit
import Kingfisher
import WalletContext

protocol NftDetailsItemCoverFlowTileDelegate: AnyObject {
    func nftDetailsItemCoverFlowTile(_ tile: NftDetailsItemCoverFlowTile, didSelectModel model: NftDetailsItemModel, longTap: Bool)
    func nftDetailsItemCoverFlowTileGetActiveState(_ tile: NftDetailsItemCoverFlowTile) -> Bool
}

class NftDetailsItemCoverFlowTile: UIView {
    private var currentModel: NftDetailsItemModel?
    private var selectionSubscription: NftDetailsItemModel.Subscription?
    private var lottieViewer: NftDetailsLottieViewer?

    private let imageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.backgroundColor = .air.groupedItem
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 12
        iv.layer.masksToBounds = true
        return iv
    }()

    private let spinner: UIActivityIndicatorView = {
        let s = UIActivityIndicatorView(style: .medium)
        s.translatesAutoresizingMaskIntoConstraints = false
        s.hidesWhenStopped = true
        s.color = .secondaryLabel
        return s
    }()
    
    weak var delegate: NftDetailsItemCoverFlowTileDelegate?
   
    init() {
        super.init(frame: .square(100))
        
        layer.cornerRadius = 12
        layer.masksToBounds = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowOpacity = 0.06
        layer.shadowRadius = 4

        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
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
        guard let currentModel else { return }
        delegate?.nftDetailsItemCoverFlowTile(self, didSelectModel: currentModel, longTap: false)
    }

    @objc private func handleLongTap() {
        guard let currentModel else { return }
        delegate?.nftDetailsItemCoverFlowTile(self, didSelectModel: currentModel, longTap: true)
    }

    func prepareForCollectionViewReuse() {
        cancelActiveThumbnailTask()
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        
        if newWindow == nil {
            cancelActiveThumbnailTask()
        } else {
            if let model = currentModel {
                startOrResumeThumbnailLoad(for: model)
            }
        }
    }

    private func cancelActiveThumbnailTask() {
        imageView.kf.cancelDownloadTask()
        spinner.stopAnimating()
    }

    private func isThumbnailLoadCancellation(_ error: Error) -> Bool {
        (error as? KingfisherError)?.isTaskCancelled == true
    }

    private func startOrResumeThumbnailLoad(for model: NftDetailsItemModel) {
        guard currentModel === model else { return }

        if let urlString = model.item.thumbnailUrl?.nilIfEmpty, let url = URL(string: urlString) {
            guard window != nil else {
                imageView.backgroundColor = .systemGray4
                return
            }
            spinner.startAnimating()
            imageView.kf.setImage(
                with: .network(url),
                placeholder: nil,
                options: [.alsoPrefetchToMemory, .cacheOriginalImage],
                completionHandler: { [weak self] result in
                    guard let self, self.currentModel === model else { return }
                    DispatchQueue.main.async {
                        switch result {
                        case .success:
                            self.spinner.stopAnimating()
                            self.imageView.backgroundColor = nil
                        case let .failure(error):
                            // for cancellation it is better to keep show the spinner rather than error image
                            if !self.isThumbnailLoadCancellation(error) {
                                self.spinner.stopAnimating()
                                self.imageView.image = NftDetailsImage.errorPlaceholderImage()
                                self.imageView.backgroundColor = nil
                            }
                        }
                    }
                }
            )
        } else {
            spinner.stopAnimating()
            imageView.image = NftDetailsImage.errorPlaceholderImage()
            imageView.backgroundColor = nil
        }
    }

    func configure(with model: NftDetailsItemModel) {
        let modelChanged = model !== currentModel
        if modelChanged {
            removeLottieViewer()
            cancelActiveThumbnailTask()

            currentModel = model
            imageView.alpha = 1
            imageView.image = nil
            imageView.backgroundColor = .systemGray4

            applySelectionDrivenLottie(for: model)
            selectionSubscription = .init(model: model, event: .selectionStatusChanged, tag: "CoverFlowTile") { [weak self] in
                guard let self, self.currentModel === model else { return }
                DispatchQueue.main.async {
                    self.applySelectionDrivenLottie(for: model)
                }
            }

            setNeedsLayout()
        }

        if currentModel === model {
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
        guard currentModel === model else { return }
        if model.isSelected, let url = model.lottieUrl, delegate?.nftDetailsItemCoverFlowTileGetActiveState(self) == true {
            if lottieViewer == nil {
                let viewer = NftDetailsLottieViewer(cornerRadius: 12, frame: imageView.frame, tag: "TILE(\(model.name))")
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
