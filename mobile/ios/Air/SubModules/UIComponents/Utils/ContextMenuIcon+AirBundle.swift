import UIKit
import ContextMenuKit
import WalletContext

public extension ContextMenuIcon {
    static func airBundle(
        _ name: String,
        renderingMode: ContextMenuIconRenderingMode = .template,
        compatibleWith traitCollection: UITraitCollection? = nil
    ) -> ContextMenuIcon? {
        custom(
            name,
            bundle: AirBundle,
            renderingMode: renderingMode,
            compatibleWith: traitCollection
        )
    }
}
