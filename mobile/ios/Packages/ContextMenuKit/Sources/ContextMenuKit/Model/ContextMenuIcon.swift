import UIKit

public enum ContextMenuIconRenderingMode {
    case automatic
    case template
    case original
}

public enum ContextMenuIcon {
    case image(UIImage, renderingMode: ContextMenuIconRenderingMode = .template)
    case placeholder

    public static func system(
        _ name: String,
        configuration: UIImage.SymbolConfiguration? = nil,
        renderingMode: ContextMenuIconRenderingMode = .template
    ) -> ContextMenuIcon? {
        let image = UIImage(systemName: name, withConfiguration: configuration)
        return image.map { .image($0, renderingMode: renderingMode) }
    }

    public static func custom(
        _ name: String,
        bundle: Bundle? = nil,
        renderingMode: ContextMenuIconRenderingMode = .template,
        compatibleWith traitCollection: UITraitCollection? = nil
    ) -> ContextMenuIcon? {
        let image = UIImage(named: name, in: bundle, compatibleWith: traitCollection)
        return image.map { .image($0, renderingMode: renderingMode) }
    }
}

extension ContextMenuIcon {
    var resolvedImage: UIImage? {
        switch self {
        case let .image(image, renderingMode):
            switch renderingMode {
            case .automatic:
                return image
            case .template:
                return image.withRenderingMode(.alwaysTemplate)
            case .original:
                return image.withRenderingMode(.alwaysOriginal)
            }
        case .placeholder:
            return nil
        }
    }

    var reservesSpace: Bool {
        true
    }
}
