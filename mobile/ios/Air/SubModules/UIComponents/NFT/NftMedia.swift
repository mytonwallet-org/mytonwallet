import SwiftUI
import UIKit
import WalletCore

public struct NftMedia: UIViewRepresentable {
    public var nft: ApiNft?
    public var playAnimationOnce: Bool
    public var mediaContentMode: UIView.ContentMode
    public var animationRenderingConfiguration: NftMediaView.AnimationRenderingConfiguration
    public var disablesAnimationPlaybackInLowPowerMode: Bool

    public init(
        nft: ApiNft?,
        playAnimationOnce: Bool,
        mediaContentMode: UIView.ContentMode = .scaleAspectFit,
        animationRenderingConfiguration: NftMediaView.AnimationRenderingConfiguration = .nftGridDefault,
        disablesAnimationPlaybackInLowPowerMode: Bool = false
    ) {
        self.nft = nft
        self.playAnimationOnce = playAnimationOnce
        self.mediaContentMode = mediaContentMode
        self.animationRenderingConfiguration = animationRenderingConfiguration
        self.disablesAnimationPlaybackInLowPowerMode = disablesAnimationPlaybackInLowPowerMode
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeUIView(context: Context) -> NftMediaView {
        let view = NftMediaView()
        view.translatesAutoresizingMaskIntoConstraints = true
        apply(to: view, context: context)
        return view
    }

    public func updateUIView(_ uiView: NftMediaView, context: Context) {
        apply(to: uiView, context: context)
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, uiView: NftMediaView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite else {
            return nil
        }
        return CGSize(width: width, height: width)
    }

    public static func dismantleUIView(_ uiView: NftMediaView, coordinator: Coordinator) {
        uiView.stopAnimationPlayback()
    }

    private func apply(to view: NftMediaView, context: Context) {
        view.mediaContentMode = mediaContentMode
        view.animationRenderingConfiguration = animationRenderingConfiguration
        view.disablesAnimationPlaybackInLowPowerMode = disablesAnimationPlaybackInLowPowerMode
        view.configure(nft: nft)

        guard let playbackKey else {
            return
        }
        guard context.coordinator.playedPlaybackKey != playbackKey else {
            return
        }
        context.coordinator.playedPlaybackKey = playbackKey
        view.playAnimationOnce()
    }

    private var playbackKey: String? {
        guard playAnimationOnce, let nft else {
            return nil
        }
        return "\(nft.id)|\(nft.metadata?.lottie ?? "")"
    }

    public final class Coordinator {
        fileprivate var playedPlaybackKey: String?
    }
}
