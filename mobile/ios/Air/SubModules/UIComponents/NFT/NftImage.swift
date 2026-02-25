
import Kingfisher
import SwiftUI
import WalletCore
import WalletContext
import Lottie

private let log = Log("NftImage")


public struct NftImage: View {
    
    public var nft: ApiNft
    public var animateIfPossible: Bool
    public var playOnce: Bool
    public var loadFullSize: Bool
    
    @State private var lottieAnimation: LottieAnimation?
    private var _modeIfPlaying: LottiePlaybackMode {
        playOnce ? .playing(.fromProgress(0, toProgress: 1, loopMode: .playOnce))
                 : .playing(.fromProgress(0, toProgress: 1, loopMode: .loop))
    }
    private var playbackState: LottiePlaybackMode { animateIfPossible ? _modeIfPlaying : .paused }
    
    public init(nft: ApiNft, animateIfPossible: Bool, playOnce: Bool = false, loadFullSize: Bool = false) {
        self.nft = nft
        self.animateIfPossible = animateIfPossible
        self.playOnce = playOnce
        self.loadFullSize = loadFullSize
    }
    
    private var imageUrl: URL? {
        if loadFullSize, let image = nft.image {
            return URL(string: image)
        } else if let thumbnail = nft.thumbnail {
            return URL(string: thumbnail)
        }
        return nil
    }
    private var thumbnailUrl: URL? {
        if let thumbnail = nft.thumbnail {
            return URL(string: thumbnail)
        }
        return nil
    }
    
    public var body: some View {
        KFImage(imageUrl)
            .backgroundDecode()
            .fade(duration: loadFullSize ? 0 : 0.15)
            .loadDiskFileSynchronously(false)
            .placeholder({
                if loadFullSize {
                    KFImage(thumbnailUrl)
                        .resizable()
                        .loadDiskFileSynchronously(false)
                        .placeholder {
                            ProgressView()
                        }
                        .aspectRatio(contentMode: .fit)
                }
            })
            .onFailureImage(UIImage.airBundle("NftError"))
            .resizable()
            .scaledToFit()
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if animateIfPossible {
                    LottieView(animation: lottieAnimation)
                        .playbackMode(playbackState)
                }
            }
            .task(id: nft.metadata?.lottie?.nilIfEmpty, priority: .medium) {
                do {
                    if let lottie = nft.metadata?.lottie?.nilIfEmpty, let url = URL(string: lottie) {
                        self.lottieAnimation = try await loadAnimation(url: url)
                    } else {
                        self.lottieAnimation = nil
                    }
                } catch {
                    log.info("failed to download from \(nft.metadata?.lottie as Any, .public) \(error, .public)")
                }
            }
    }
    
    nonisolated func loadAnimation(url: URL) async throws -> LottieAnimation {
        let animation = try await LottieAnimation.loadedFrom(url: url, animationCache: DefaultAnimationCache.sharedCache).orThrow("failed to load animation")
        try Task.checkCancellation()
        return animation
    }
}
