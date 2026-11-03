import UIKit

public extension UIView {
    /// Converts `rect`, the view's bounds by default, to `view`'s coordinates as both show on this frame, with the
    /// animations in flight; until the layers are first committed, their model values stand in
    func convertAsShown(_ rect: CGRect? = nil, to view: UIView) -> CGRect {
        guard let shown = layer.presentation(), let target = view.layer.presentation() else {
            return convert(rect ?? bounds, to: view)
        }
        return shown.convert(rect ?? shown.bounds, to: target)
    }

    /// Draws `rect` of the view, its bounds by default, from the layer tree rather than from the screen, on a
    /// transparent background
    func makeLayerImage(
        of rect: CGRect? = nil,
        scale: CGFloat? = nil,
        range: UIGraphicsImageRendererFormat.Range? = nil
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat.preferred()
        if let scale {
            format.scale = scale
        }
        format.opaque = false
        if let range {
            format.preferredRange = range
        }
        return UIGraphicsImageRenderer(bounds: rect ?? bounds, format: format).image { context in
            layer.render(in: context.cgContext)
        }
    }
}
