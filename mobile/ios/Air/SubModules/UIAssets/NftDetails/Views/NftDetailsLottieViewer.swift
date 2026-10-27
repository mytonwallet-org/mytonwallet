import UIKit
import Lottie

protocol NftDetailsLottieViewerDelegate: AnyObject {
    func nftDetailsLottieViewer(_ viewer: NftDetailsLottieViewer, requestFadeOutUnderlay continuePlayback: @escaping () -> Void)
    func nftDetailsLottieViewer(_ viewer: NftDetailsLottieViewer, requestFadeInUnderlay finished: @escaping () -> Void)
}

final class NftDetailsLottieViewer: UIView {

    weak var playbackTransitionDelegate: NftDetailsLottieViewerDelegate?

    func setUrl(_ url: URL?) {
        if url != self.url {
            self.url = url
            applyUrl()
        }
    }
    
    private(set) var url: URL?
    private static let canvasSide: CGFloat = 512
    private let animationView: LottieAnimationView
    private var loadTask: Task<Void, Never>?
    private var loadGeneration: UInt64 = 0

    init(cornerRadius: CGFloat, frame: CGRect) {
        animationView = LottieAnimationView(frame: CGRect(x: 0, y: 0, width: Self.canvasSide, height: Self.canvasSide))
        
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = true
        layer.cornerRadius = cornerRadius

        let configuration = Lottie.LottieConfiguration(
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        animationView.configuration = configuration
        animationView.isOpaque = false
        animationView.contentMode = .scaleAspectFit
        animationView.clipsToBounds = true
        animationView.isUserInteractionEnabled = false
        animationView.loopMode = .loop
        // The same renderer moves between the carousel, expanded artwork and
        // media viewer. Briefly leaving the window must not interrupt its clock.
        animationView.backgroundBehavior = .continuePlaying
        animationView.currentProgress = 0
        animationView.layer.masksToBounds = true

        // Keep Lottie's composition at one size. Animating its Auto Layout
        // bounds makes Core Animation rebuild the composition mid-transition,
        // briefly showing a full-size frame through a thumbnail-sized clip.
        addSubview(animationView)
        layoutAnimationCanvas()

        isHidden = true
        alpha = 1
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutAnimationCanvas()
    }

    private func layoutAnimationCanvas() {
        animationView.center = CGPoint(x: bounds.midX, y: bounds.midY)
        let scale = min(bounds.width, bounds.height) / Self.canvasSide
        animationView.transform = CGAffineTransform(scaleX: scale, y: scale)
    }

    /// Rasterize only the small lower band, at a bounded resolution. The
    /// presentation layer contains the currently displayed animation pose.
    func lowerBandSnapshot(height: CGFloat, background: UIColor) -> UIImage? {
        guard bounds.width > 0, bounds.height > 0, !isHidden,
              let displayedLayer = layer.presentation(),
              abs(displayedLayer.bounds.width - bounds.width) < 0.5,
              abs(displayedLayer.bounds.height - bounds.height) < 0.5 else { return nil }
        let height = min(height, bounds.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = min(1, 256 / bounds.width)
        format.opaque = true
        // Fill complete raster rows. A fractional last row in an opaque renderer
        // otherwise becomes a dark seam when this band is reflected and stretched.
        let rasterHeight = ceil(height * format.scale) / format.scale
        return UIGraphicsImageRenderer(size: CGSize(width: bounds.width, height: rasterHeight), format: format).image { ctx in
            background.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: bounds.width, height: rasterHeight))
            ctx.cgContext.translateBy(x: 0, y: rasterHeight - bounds.height)
            displayedLayer.render(in: ctx.cgContext)
        }
    }

    /// Lottie can report intrinsic sizes; this overlay must only size from Auto Layout, not from animation content.
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
    }

    func embedAbove(_ otherView: UIView) {
        guard let superview = otherView.superview, self.superview == nil else {
            assertionFailure()
            return
        }
        translatesAutoresizingMaskIntoConstraints = false
        superview.insertSubview(self, aboveSubview: otherView)
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: otherView.topAnchor),
            leadingAnchor.constraint(equalTo: otherView.leadingAnchor),
            trailingAnchor.constraint(equalTo: otherView.trailingAnchor),
            bottomAnchor.constraint(equalTo: otherView.bottomAnchor),
        ])
    }

    func setCornerRadius(_ radius: CGFloat) {
        layer.cornerRadius = radius
    }

    /// Stops loading/playback and resets visibility for host teardown (cell reuse, deselection).
    func cancelForHostRemoval() {
        loadTask?.cancel()
        loadTask = nil
        animationView.stop()
        animationView.currentProgress = 0
        isHidden = true
        loadGeneration &+= 1
    }

    private func applyUrl() {
        loadTask?.cancel()
        loadTask = nil
        animationView.stop()
        animationView.animation = nil
        loadGeneration &+= 1

        guard let url else {
            isHidden = true
            return
        }

        isHidden = true
        let epoch = loadGeneration

        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let cache = DefaultAnimationCache.sharedCache
                guard let animation = await LottieAnimation.loadedFrom(url: url, animationCache: cache) else {
                    guard epoch == self.loadGeneration else { return }
                    self.isHidden = true
                    return
                }
                try Task.checkCancellation()
                guard epoch == self.loadGeneration else { return }
                guard self.url == url else { return }

                self.animationView.animation = animation
                self.animationView.currentProgress = 0
                self.beginPlaybackAfterPreparation(expectedUrl: url, playbackEpoch: epoch)
            } catch is CancellationError {
            } catch {
                guard epoch == self.loadGeneration else { return }
                self.isHidden = true
            }
        }
    }

    private func beginPlaybackAfterPreparation(expectedUrl: URL?, playbackEpoch: UInt64) {
        guard playbackEpoch == loadGeneration else { return }
        guard animationView.animation != nil else { return }
        if let expectedUrl, self.url != expectedUrl { return }

        if let delegate = playbackTransitionDelegate {
            isHidden = true
            delegate.nftDetailsLottieViewer(self, requestFadeOutUnderlay: { [weak self] in
                guard let self else { return }
                guard playbackEpoch == self.loadGeneration else { return }
                guard self.animationView.animation != nil else { return }
                if let expectedUrl, self.url != expectedUrl { return }

                self.isHidden = false
                self.animationView.play { [weak self] completed in
                    guard let self else { return }
                    guard completed, playbackEpoch == self.loadGeneration else { return }
                    if let delegate = self.playbackTransitionDelegate {
                        delegate.nftDetailsLottieViewer(self, requestFadeInUnderlay: {})
                    } else {
                        self.isHidden = true
                    }
                }
            })
        } else {
            guard playbackEpoch == loadGeneration else { return }
            isHidden = false
            animationView.play { [weak self] completed in
                guard let self else { return }
                guard completed, playbackEpoch == self.loadGeneration else { return }
                self.isHidden = true
            }
        }
    }
}

extension NftDetailsLottieViewer {
    /// Before playback: hide underlay and show viewer instantly, then `continuePlayback`.
    static func runDefaultFadeOutUnderlay(viewer: NftDetailsLottieViewer, imageView: UIView, continuePlayback: @escaping () -> Void) {
        viewer.isHidden = false
        viewer.alpha = 1
        imageView.alpha = 0
        continuePlayback()
    }

    /// After playback: hide viewer and show underlay instantly.
    static func runDefaultFadeInUnderlay(viewer: NftDetailsLottieViewer, imageView: UIView, finished: @escaping () -> Void) {
        viewer.alpha = 0
        imageView.alpha = 1
        viewer.isHidden = true
        viewer.alpha = 1
        finished()
    }
}
