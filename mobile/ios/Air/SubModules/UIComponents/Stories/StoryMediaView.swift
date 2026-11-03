import AVFoundation
import UIKit

/// The still image remains visible until the video has a frame to display.
final class StoryMediaView: UIView {
    private let imageView = UIImageView()
    private let videoLayer = AVPlayerLayer()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var observations: [NSKeyValueObservation] = []
    private var itemObservation: NSKeyValueObservation?
    private(set) var isPlaybackRequested = false

    init(page: StoryPage) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        imageView.image = page.image
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        addSubview(imageView)
        videoLayer.videoGravity = .resizeAspectFill
        videoLayer.opacity = 0
        layer.addSublayer(videoLayer)

        if let url = page.videoURL,
           url.isFileURL || ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
            let player = AVQueuePlayer()
            player.isMuted = true
            let item = AVPlayerItem(url: url)
            self.player = player
            looper = AVPlayerLooper(player: player, templateItem: item)
            videoLayer.player = player
            observations.append(videoLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.updateVideoVisibility() }
            })
            observations.append(player.observe(\.status, options: [.new]) { [weak self] player, _ in
                guard player.status == .failed else { return }
                Task { @MainActor [weak self] in self?.stopVideo() }
            })
            observations.append(player.observe(\.currentItem, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.observeCurrentItem() }
            })
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoLayer.frame = bounds
        CATransaction.commit()
    }

    func setPlaying(_ playing: Bool, reduceMotion: Bool = UIAccessibility.isReduceMotionEnabled) {
        isPlaybackRequested = playing && !reduceMotion
        if isPlaybackRequested { player?.play() } else { player?.pause() }
    }

    private func updateVideoVisibility() {
        setVideoVisible(videoLayer.isReadyForDisplay)
        if isPlaybackRequested { player?.play() }
    }

    private func observeCurrentItem() {
        itemObservation = player?.currentItem?.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor [weak self] in self?.stopVideo() }
        }
    }

    private func setVideoVisible(_ visible: Bool) {
        let opacity: Float = visible ? 1 : 0
        guard videoLayer.opacity != opacity else { return }
        let previous = videoLayer.presentation()?.opacity ?? videoLayer.opacity
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoLayer.opacity = opacity
        CATransaction.commit()
        if TradeMotion.enabled {
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = previous
            animation.toValue = opacity
            animation.duration = 0.2
            videoLayer.add(animation, forKey: "storyVideoVisibility")
        }
    }

    private func stopVideo() {
        player?.pause()
        setVideoVisible(false)
        videoLayer.player = nil
        looper = nil
        player = nil
        itemObservation = nil
        observations.removeAll()
    }
}

final class StoryProgressView: UIView {
    private let tracks: [CALayer]
    private let fills: [CALayer]
    private var index = 0
    private var progress: CGFloat = 0

    init(count: Int) {
        tracks = (0..<count).map { _ in CALayer() }
        fills = (0..<count).map { _ in CALayer() }
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        for (track, fill) in zip(tracks, fills) {
            track.backgroundColor = UIColor.white.withAlphaComponent(0.35).cgColor
            track.cornerRadius = 1.5
            fill.backgroundColor = UIColor.white.cgColor
            fill.cornerRadius = 1.5
            track.addSublayer(fill)
            layer.addSublayer(track)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(index: Int, progress: CGFloat) {
        self.index = index
        self.progress = progress
        setNeedsLayout()
        layoutIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !tracks.isEmpty else { return }
        let gap: CGFloat = 4
        let width = max(0, (bounds.width - CGFloat(tracks.count - 1) * gap) / CGFloat(tracks.count))
        let isRTL = effectiveUserInterfaceLayoutDirection == .rightToLeft
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for i in tracks.indices {
            let visualIndex = isRTL ? tracks.count - 1 - i : i
            tracks[i].frame = CGRect(x: CGFloat(visualIndex) * (width + gap), y: 0, width: width, height: bounds.height)
            let fraction = i < index ? 1 : i == index ? progress : 0
            let fillWidth = width * fraction
            fills[i].frame = CGRect(x: isRTL ? width - fillWidth : 0, y: 0, width: fillWidth, height: bounds.height)
        }
        CATransaction.commit()
    }
}

/// The same broad alpha ramp used by the native NFT page sweep, without image readback.
final class StorySweepMaskView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }

    init(size: CGSize, isRTL: Bool) {
        super.init(frame: CGRect(origin: .zero, size: CGSize(width: size.width * 4, height: size.height)))
        let gradient = layer as! CAGradientLayer
        gradient.colors = [UIColor.clear.cgColor, UIColor.white.cgColor, UIColor.white.cgColor]
        gradient.locations = [0, 0.75, 1]
        gradient.startPoint = CGPoint(x: isRTL ? 1 : 0, y: 0.5)
        gradient.endPoint = CGPoint(x: isRTL ? 0 : 1, y: 0.5)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
