import UIKit

struct NftDetailsContentPalette {
    let baseColor: UIColor
    let subtleBackgroundColor: UIColor
    let edgeColor: UIColor
    let secondaryTextColor: UIColor
    let highlightColor: UIColor
    
    static let lightBase = NftDetailsContentPalette(
            baseColor: .black,
            subtleBackgroundColor: .black.withAlphaComponent(0.04),
            edgeColor: .white.withAlphaComponent(0.7),
            secondaryTextColor: .black.withAlphaComponent(0.75),
            highlightColor: .black.withAlphaComponent(0.2),
        )

    static let darkBase = NftDetailsContentPalette(
            baseColor: .white,
            subtleBackgroundColor: .white.withAlphaComponent(0.06),
            edgeColor: .white.withAlphaComponent(0.3),
            secondaryTextColor: .white.withAlphaComponent(0.75),
            highlightColor: .white.withAlphaComponent(0.6),
        )
}

@MainActor
class NftDetailsColorResolver {
    private let colorCache: NftDetailsColorCache

    private static var defaultBackgroundColor: UIColor { .air.sheetBackground }
    
    private(set) var fallbackColor: UIColor

    init(colorCache: NftDetailsColorCache) {
        self.colorCache = colorCache
        fallbackColor = Self.defaultBackgroundColor
    }

    func update(traitCollection: UITraitCollection) {
        fallbackColor = Self.defaultBackgroundColor.resolvedColor(with: traitCollection)
    }

    func currentBaseColor(for model: NftDetailsItemModel) -> UIColor? {
        if case .loaded(let processed) = model.processedImageState {
            return processed.baseColor
        }
        let (_, cached) = colorCache.color(forKey: model.id)
        return cached
    }

    func effectiveBaseColor(for model: NftDetailsItemModel) -> UIColor {
        currentBaseColor(for: model) ?? fallbackColor
    }

    func contentPalette(for model: NftDetailsItemModel) -> NftDetailsContentPalette {
        let c = effectiveBaseColor(for: model)
        return c.isLightColor ? .lightBase : .darkBase
    }
}

/// Page subviews should adopt this protocol to respond to NFT theme changes
protocol NftDetailsContentColorConsumer: UIView {
    
    /// Return `true` to process subviews as well, `false` otherwise
    func applyContentColorPalette(_ palette: NftDetailsContentPalette) -> Bool
}
