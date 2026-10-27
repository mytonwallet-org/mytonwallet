import UIKit

/// Uses the same Gaussian-only backdrop treatment as the app's BackgroundBlurView.
/// The overlay supplies its tint separately, so neither theme adds a material fill.
@MainActor
final class ContextMenuUntintedBlurView: UIVisualEffectView {
    private let radius: CGFloat

    init(radius: CGFloat) {
        self.radius = max(0, radius)
        super.init(effect: UIBlurEffect(style: .regular))
        overrideUserInterfaceStyle = .light
        removeMaterialFill()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        removeMaterialFill()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        removeMaterialFill()
    }

    private func removeMaterialFill() {
        for subview in subviews where NSStringFromClass(type(of: subview)).contains("VisualEffectSubview") {
            subview.isHidden = true
        }
        guard let backdrop = layer.sublayers?.first, let filters = backdrop.filters else { return }
        backdrop.backgroundColor = nil
        backdrop.isOpaque = false
        backdrop.filters = filters.filter { ($0 as? NSObject)?.description == "gaussianBlur" }
        backdrop.setValue(radius as NSNumber, forKeyPath: "filters.gaussianBlur.inputRadius")
    }
}
