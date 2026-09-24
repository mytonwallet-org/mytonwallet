import AVFoundation
import Kingfisher
import UIKit

final class MintCardMediaView: UIView {
    static let imageOptions: KingfisherOptionsInfo = [
        .processor(DownsamplingImageProcessor(size: CGSize(width: 1024, height: 1024))),
        .scaleFactor(1), .cacheOriginalImage, .backgroundDecode,
    ]

    private let poster = UIImageView()
    private let playerLayer = AVPlayerLayer()
    private var info: MintCardTypeInfo?
    private var loadedPosterType: String?
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var readinessObservation: NSKeyValueObservation?
    private var wantsPlayback = false
    private var loadingTask: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        poster.contentMode = .scaleAspectFill
        addSubview(poster)
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.isHidden = true
        layer.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ info: MintCardTypeInfo) {
        guard self.info?.type != info.type else { return }
        stop()
        self.info = info
        loadedPosterType = nil
        poster.kf.cancelDownloadTask()
        poster.image = nil
        backgroundColor = info.posterBackground
        loadPosterIfNeeded()
    }

    func setPlaybackActive(_ active: Bool) {
        wantsPlayback = active
        guard active, window != nil, let info, let url = info.videoURL else {
            loadingTask?.cancel()
            loadingTask = nil
            player?.pause()
            return
        }
        if let player { player.play(); return }
        guard loadingTask == nil else { return }
        loadingTask = Task { @MainActor [weak self] in
            let cachedURL = await MintCardVideoCache.shared.fileURL(for: info.type)
            guard !Task.isCancelled, let self, wantsPlayback, window != nil, self.info?.type == info.type else { return }
            loadingTask = nil
            let player = AVQueuePlayer()
            player.isMuted = true
            self.player = player
            playerLayer.player = player
            readinessObservation = playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    playerLayer.isHidden = !playerLayer.isReadyForDisplay
                }
            }
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: cachedURL ?? url))
            player.play()
        }
    }

    func stop() {
        wantsPlayback = false
        loadingTask?.cancel()
        loadingTask = nil
        player?.pause()
        readinessObservation = nil
        looper?.disableLooping()
        looper = nil
        player?.removeAllItems()
        playerLayer.player = nil
        playerLayer.isHidden = true
        player = nil
    }

    private func loadPosterIfNeeded() {
        guard window != nil, let info, loadedPosterType != info.type.rawValue else { return }
        loadedPosterType = info.type.rawValue
        poster.kf.setImage(with: info.posterURL, options: Self.imageOptions)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stop()
            poster.kf.cancelDownloadTask()
            loadedPosterType = nil
        } else {
            loadPosterIfNeeded()
            setPlaybackActive(wantsPlayback)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // The 1080 × 1500 movies place the card at their center. Align it with
        // the design's card/chevron center while covering the full square hero.
        let mediaHeight = bounds.width * 1500 / 1080
        let mediaFrame = CGRect(x: 0, y: bounds.width * 164 / 402 - mediaHeight / 2,
                                width: bounds.width, height: mediaHeight)
        poster.frame = mediaFrame
        playerLayer.frame = mediaFrame
        CATransaction.commit()
    }
}
