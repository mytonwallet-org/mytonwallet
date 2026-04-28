import Kingfisher
import LottieKit
import UIKit
import WalletCore

@MainActor
final class NftMediaView: UIView {
    enum ImageState {
        case loading
        case loaded
        case unavailable
    }

    struct AnimationRenderingConfiguration: Equatable, Sendable {
        var preferredScale: CGFloat
        var maxRenderPixelDimension: CGFloat

        static let nftGridDefault = Self(
            preferredScale: 2.0,
            maxRenderPixelDimension: 500.0
        )
    }

    private let imageView = UIImageView()
    private let animationView = LottieAnimationView()

    var nft: ApiNft?
    var onStateChange: ((ImageState) -> Void)?

    var animationRenderingConfiguration = AnimationRenderingConfiguration.nftGridDefault {
        didSet {
            guard self.animationRenderingConfiguration != oldValue else {
                return
            }
            self.updateAnimationRenderingScale()
        }
    }

    var hasPlayableAnimation: Bool {
        self.animationURL != nil
    }

    private var currentRequestID = UUID()
    private var animationLoadTask: Task<Void, Never>?
    private var animationURL: URL?
    private var shouldPlayAnimationWhenReady = false
    private var isStaticImageLoading = false
    private var isStaticImageAvailable = false
    private var isAnimationLoading = false
    private var isAnimationAvailable = false
    private var isAnimationPlaybackInFlight = false

    convenience init() {
        self.init(frame: .zero)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.animationLoadTask?.cancel()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.updateAnimationRenderingScale()
    }

    func reset() {
        self.currentRequestID = UUID()
        self.nft = nil
        self.animationURL = nil
        self.shouldPlayAnimationWhenReady = false
        self.isStaticImageLoading = false
        self.isStaticImageAvailable = false
        self.isAnimationLoading = false
        self.isAnimationAvailable = false
        self.isAnimationPlaybackInFlight = false
        self.animationLoadTask?.cancel()
        self.animationLoadTask = nil
        self.imageView.kf.cancelDownloadTask()
        self.imageView.image = nil
        self.animationView.reset()
        self.updateAnimationVisibility()
    }

    func configure(nft: ApiNft?) {
        guard nft != self.nft else {
            return
        }

        self.reset()
        self.nft = nft

        let requestID = self.currentRequestID
        let imageURLs = Self.candidateImageURLs(for: nft)
        let animationURL = Self.validatedURL(from: nft?.metadata?.lottie)
        self.animationURL = animationURL

        if imageURLs.isEmpty, animationURL == nil {
            self.emitStateChange()
            return
        }

        if !imageURLs.isEmpty {
            self.isStaticImageLoading = true
            self.loadImage(from: imageURLs, at: 0, requestID: requestID)
        }

        if let animationURL {
            self.isAnimationLoading = true
            self.loadAnimation(from: animationURL, requestID: requestID)
        }

        self.emitStateChange()
    }

    func playAnimationOnce() {
        guard self.hasPlayableAnimation else {
            return
        }

        self.shouldPlayAnimationWhenReady = true
        self.updateAnimationRenderingScale()

        guard self.isAnimationAvailable else {
            return
        }

        self.isAnimationPlaybackInFlight = true
        self.shouldPlayAnimationWhenReady = false
        self.updateAnimationVisibility()
        self.animationView.playOnce { [weak self] in
            guard let self else {
                return
            }
            self.animationView.pause()
            self.animationView.seek(to: .begin)
            self.isAnimationPlaybackInFlight = false
            self.updateAnimationVisibility()
        }
    }

    func stopAnimationPlayback() {
        self.shouldPlayAnimationWhenReady = false
        self.isAnimationPlaybackInFlight = false
        self.animationView.pause()
        if self.isAnimationAvailable {
            self.animationView.seek(to: .begin)
        }
        self.updateAnimationVisibility()
    }

    private func setup() {
        self.translatesAutoresizingMaskIntoConstraints = false
        self.clipsToBounds = true

        self.imageView.translatesAutoresizingMaskIntoConstraints = false
        self.imageView.contentMode = .scaleAspectFit
        self.imageView.isUserInteractionEnabled = false
        self.addSubview(self.imageView)

        self.animationView.translatesAutoresizingMaskIntoConstraints = false
        self.animationView.contentMode = .scaleAspectFit
        self.animationView.isUserInteractionEnabled = false
        self.animationView.isHidden = true
        self.addSubview(self.animationView)

        NSLayoutConstraint.activate([
            self.imageView.topAnchor.constraint(equalTo: self.topAnchor),
            self.imageView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            self.imageView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            self.imageView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            self.animationView.topAnchor.constraint(equalTo: self.topAnchor),
            self.animationView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            self.animationView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            self.animationView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
        ])
    }

    private func loadImage(from urls: [URL], at index: Int, requestID: UUID) {
        let url = urls[index]
        self.imageView.kf.setImage(
            with: .network(url),
            placeholder: nil,
            options: [.alsoPrefetchToMemory, .cacheOriginalImage]
        ) { [weak self] result in
            guard let self, self.currentRequestID == requestID else {
                return
            }

            switch result {
            case .success:
                self.isStaticImageLoading = false
                self.isStaticImageAvailable = true
                self.updateAnimationVisibility()
                self.emitStateChange()
            case .failure(let error):
                if error.isTaskCancelled {
                    return
                }

                let nextIndex = index + 1
                if urls.indices.contains(nextIndex) {
                    self.loadImage(from: urls, at: nextIndex, requestID: requestID)
                } else {
                    self.isStaticImageLoading = false
                    self.isStaticImageAvailable = false
                    self.imageView.image = nil
                    self.updateAnimationVisibility()
                    self.emitStateChange()
                }
            }
        }
    }

    private func loadAnimation(from url: URL, requestID: UUID) {
        self.animationLoadTask = Task { [weak self] in
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                try Task.checkCancellation()

                if let httpResponse = response as? HTTPURLResponse,
                   !(200 ... 299).contains(httpResponse.statusCode) {
                    throw URLError(.badServerResponse)
                }

                guard let self,
                      self.currentRequestID == requestID,
                      self.animationURL == url else {
                    return
                }

                try await self.animationView.setAnimation(
                    source: .data(data, cacheKey: url.absoluteString),
                    playbackMode: .still(position: .begin)
                )

                guard self.currentRequestID == requestID,
                      self.animationURL == url else {
                    return
                }

                self.animationLoadTask = nil
                self.isAnimationLoading = false
                self.isAnimationAvailable = true
                self.updateAnimationVisibility()
                self.emitStateChange()

                if self.shouldPlayAnimationWhenReady {
                    self.playAnimationOnce()
                }
            } catch is CancellationError {
            } catch {
                guard let self,
                      self.currentRequestID == requestID,
                      self.animationURL == url else {
                    return
                }

                self.animationLoadTask = nil
                self.isAnimationLoading = false
                self.isAnimationAvailable = false
                self.updateAnimationVisibility()
                self.emitStateChange()
            }
        }
    }

    private func updateAnimationRenderingScale() {
        let bounds = self.bounds.size
        let maxPointDimension = max(bounds.width, bounds.height)
        guard maxPointDimension > 0 else {
            return
        }

        let cappedScale = self.animationRenderingConfiguration.maxRenderPixelDimension / maxPointDimension
        self.animationView.renderingScale = max(
            1.0,
            min(self.animationRenderingConfiguration.preferredScale, cappedScale)
        )
    }

    private func emitStateChange() {
        if self.isStaticImageAvailable || self.isAnimationAvailable {
            self.onStateChange?(.loaded)
        } else if self.isStaticImageLoading || self.isAnimationLoading {
            self.onStateChange?(.loading)
        } else {
            self.onStateChange?(.unavailable)
        }
    }

    private func updateAnimationVisibility() {
        self.animationView.isHidden = !self.isAnimationAvailable
            || (!self.isAnimationPlaybackInFlight && self.isStaticImageAvailable)
    }

    private static func candidateImageURLs(for nft: ApiNft?) -> [URL] {
        var seen = Set<String>()
        return [nft?.thumbnail, nft?.image]
            .compactMap(validatedURL(from:))
            .filter { seen.insert($0.absoluteString).inserted }
    }

    private static func validatedURL(from rawValue: String?) -> URL? {
        guard let rawValue else {
            return nil
        }

        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty,
              let url = URL(string: trimmedValue),
              url.scheme?.isEmpty == false else {
            return nil
        }

        return url
    }
}

#if DEBUG
@available(iOS 18, *)
#Preview {
    let view = NftMediaView()
    view.configure(nft: ApiNft.sample)
    return view
}
#endif
