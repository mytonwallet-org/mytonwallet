import UIKit
import Lottie

protocol NftDetailsLottieViewerDelegate: AnyObject {
    func nftDetailsLottieViewer(_ viewer: NftDetailsLottieViewer, requestFadeOutUnderlay continuePlayback: @escaping () -> Void)
    func nftDetailsLottieViewer(_ viewer: NftDetailsLottieViewer, requestFadeInUnderlay finished: @escaping () -> Void)
}

final class NftDetailsLottieViewer: UIView {

    weak var playbackTransitionDelegate: NftDetailsLottieViewerDelegate?

    func setUrl(_ url: URL?, playAlways: Bool = false) {
        if url != self.url {
            self.url = url
            applyUrl()
            return
        }

        if self.url != nil, playAlways {
            restartPreparedPlaybackIfPossible()
        }
    }
    
    private var url: URL?
    private let animationView: LottieAnimationView
    private var loadTask: Task<Void, Never>?
    private let tagString: String

    init(cornerRadius: CGFloat, frame: CGRect, tag: String) {
        tagString = tag
        animationView = LottieAnimationView(frame: .fromSize(frame.size))

        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = true
        layer.cornerRadius = cornerRadius

        let configuration = Lottie.LottieConfiguration(
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        animationView.configuration = configuration
        animationView.contentMode = .scaleAspectFit
        animationView.clipsToBounds = true
        animationView.isUserInteractionEnabled = false
        animationView.loopMode = .playOnce
        animationView.currentProgress = 0
        animationView.layer.cornerRadius = cornerRadius
        animationView.layer.masksToBounds = true

        animationView.translatesAutoresizingMaskIntoConstraints = false
        animationView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        animationView.setContentHuggingPriority(.defaultLow, for: .vertical)
        animationView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        animationView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        addSubview(animationView)

        NSLayoutConstraint.activate([
            animationView.topAnchor.constraint(equalTo: topAnchor),
            animationView.leadingAnchor.constraint(equalTo: leadingAnchor),
            animationView.trailingAnchor.constraint(equalTo: trailingAnchor),
            animationView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        isHidden = true
        alpha = 1
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

    /// Stops loading/playback and resets visibility for host teardown (cell reuse, deselection).
    func cancelForHostRemoval() {
        loadTask?.cancel()
        loadTask = nil
        animationView.stop()
        animationView.currentProgress = 0
        isHidden = true
        alpha = 1
    }

    private func applyUrl() {
        loadTask?.cancel()
        loadTask = nil
        animationView.stop()
        animationView.animation = nil

        guard let url else {
            isHidden = true
            alpha = 1
            return
        }

        isHidden = true
        alpha = 1

        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let cache = DefaultAnimationCache.sharedCache
                guard let animation = await LottieAnimation.loadedFrom(url: url, animationCache: cache) else {
                    self.isHidden = true
                    self.alpha = 1
                    return
                }
                try Task.checkCancellation()
                guard self.url == url else { return }

                self.animationView.animation = animation
                self.animationView.currentProgress = 0
                self.beginPlaybackAfterPreparation(expectedUrl: url)
            } catch is CancellationError {
            } catch {
                self.isHidden = true
                self.alpha = 1
            }
        }
    }

    private func restartPreparedPlaybackIfPossible() {
        guard let currentUrl = url, animationView.animation != nil else { return }
        guard !animationView.isAnimationPlaying else { return }
        animationView.stop()
        animationView.currentProgress = 0
        beginPlaybackAfterPreparation(expectedUrl: currentUrl)
    }

    /// Called only after `animation` is assigned and progress reset; starts delegate-driven fades, then `play`.
    private func beginPlaybackAfterPreparation(expectedUrl: URL?) {
        guard animationView.animation != nil else { return }
        if let expectedUrl, self.url != expectedUrl { return }

        animationView.currentProgress = 0

        if let delegate = playbackTransitionDelegate {
            isHidden = true
            alpha = 1
            delegate.nftDetailsLottieViewer(self, requestFadeOutUnderlay: { [weak self] in
                guard let self else { return }
                guard self.animationView.animation != nil else { return }
                if let expectedUrl, self.url != expectedUrl { return }

                self.isHidden = false
                self.alpha = 1
                self.animationView.play { [weak self] _ in
                    guard let self else { return }
                    self.animationView.stop()
                    self.animationView.currentProgress = 0
                    if let delegate = self.playbackTransitionDelegate {
                        delegate.nftDetailsLottieViewer(self, requestFadeInUnderlay: {})
                    } else {
                        self.isHidden = true
                        self.alpha = 1
                    }
                }
            })
        } else {
            isHidden = false
            alpha = 1
            animationView.play { [weak self] _ in
                guard let self else { return }
                self.animationView.stop()
                self.animationView.currentProgress = 0
                self.isHidden = true
                self.alpha = 1
            }
        }
    }
}

extension NftDetailsLottieViewer {
    /// Before playback: hide underlay and show viewer instantly, then `continuePlayback`.
    static func runDefaultFadeOutUnderlay(viewer: NftDetailsLottieViewer, imageView: UIImageView, continuePlayback: @escaping () -> Void) {
        viewer.isHidden = false
        viewer.alpha = 1
        imageView.alpha = 0
        continuePlayback()
    }

    /// After playback: hide viewer and show underlay instantly.
    static func runDefaultFadeInUnderlay(viewer: NftDetailsLottieViewer, imageView: UIImageView, finished: @escaping () -> Void) {
        viewer.alpha = 0
        imageView.alpha = 1
        viewer.isHidden = true
        viewer.alpha = 1
        finished()
    }
}
