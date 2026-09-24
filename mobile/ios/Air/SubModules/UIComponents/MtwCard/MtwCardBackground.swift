//
//  MtwCardBackground.swift
//  MyTonWalletAir
//
//  Created by nikstar on 18.11.2025.
//

import SwiftUI
import WalletCore
import WalletContext

public struct MtwCardBackground: View {
    
    var nft: ApiNft?
    var hideBorder: Bool
    var borderWidthMultiplier: CGFloat
    var isAnimationEnabled: Bool
    var resolution: CardBackgroundResolution
    @State private var resolved: (metadata: ApiNftMetadata?, seed: CardBackgroundSeed)?
    
    public init(nft: ApiNft?, hideBorder: Bool = false, borderWidthMultiplier: CGFloat = 1, isAnimationEnabled: Bool = false, resolution: CardBackgroundResolution = .full) {
        self.nft = nft
        self.hideBorder = hideBorder
        self.borderWidthMultiplier = borderWidthMultiplier
        self.isAnimationEnabled = isAnimationEnabled
        self.resolution = resolution
    }
    
    public var body: some View {
        Color.air.groupedBackground
            .overlay {
                ZStack {
                    if let nft, nft.isMtwCard {
                        // A neutral placeholder avoids swapping between two generations
                        // of the same card while its seed is being resolved.
                        (nft.metadata?.mtwCardTextType == .dark ? Color(white: 0.8) : Color(white: 0.15))
                        if let resolved, resolved.metadata == nft.metadata {
                            AnimatedCardBackground(seed: resolved.seed, isAnimationEnabled: isAnimationEnabled, resolution: resolution)
                                .aspectRatio(400.0 / 232, contentMode: .fill)
                        }
                    } else {
                        if isAnimationEnabled, resolution == .full {
                            DefaultCardBackground(isAnimationEnabled: true, resolution: resolution)
                                .aspectRatio(400.0 / 232, contentMode: .fill)
                        } else {
                            Image(uiImage: .homeCard).resizable().aspectRatio(contentMode: .fill)
                                .transition(.opacity.animation(.smooth(duration: 0.15)))
                        }
                    }
                }
            }
            .overlay {
                if !hideBorder {
                    MtwCardBorder(nft: nft, borderWidthMultiplier: borderWidthMultiplier)
                }
            }
            .clipped()
            .task(id: nft?.metadata) {
                guard let nft, nft.isMtwCard else { resolved = nil; return }
                guard let seed = try? await CardBackgroundNftSource.seed(for: nft), !Task.isCancelled else { return }
                resolved = (nft.metadata, seed)
            }
    }
}

public extension UIImage {
    @MainActor static let homeCard: UIImage = {
        let surface = CardSurfaceConfiguration.current
        let image = CardDefaultBackground.artwork(surface.defaultArtwork).image
        return surface.radialBrush ? CardBrushTexture.applying(to: image) : image
    }()
}

private struct DefaultCardBackground: UIViewRepresentable {
    let isAnimationEnabled: Bool
    let resolution: CardBackgroundResolution

    func makeUIView(context: Context) -> MtwCardBackgroundView { MtwCardBackgroundView() }

    func updateUIView(_ view: MtwCardBackgroundView, context: Context) {
        view.configure(nft: nil, hideBorder: true, isAnimationEnabled: isAnimationEnabled, resolution: resolution)
    }
}
