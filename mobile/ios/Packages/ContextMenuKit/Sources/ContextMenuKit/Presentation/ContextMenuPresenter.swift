import UIKit

@MainActor
enum ContextMenuPresenter {
    @discardableResult
    static func present(
        configuration: ContextMenuConfiguration,
        from sourceView: UIView,
        presentationReference: ContextMenuPresentationReference? = nil
    ) -> ContextMenuOverlayView? {
        guard let window = sourceView.window else {
            return nil
        }
        let configuration = configuration.resolved(for: sourceView)
        let resolvedPresentationReference = presentationReference ?? ContextMenuPresentationReference.from(view: sourceView)
        let sourceUserInterfaceStyle = ContextMenuVisuals.resolvedUserInterfaceStyle(for: sourceView.traitCollection)
        let overlayView = ContextMenuOverlayView(
            configuration: configuration,
            sourceRectInWindow: resolvedPresentationReference.anchorRectInWindow,
            appearanceSourceView: sourceView,
            portalSourceView: resolvedPresentationReference.portalSourceView,
            portalMaskRectInWindow: resolvedPresentationReference.portalMaskRectInWindow,
            portalMask: resolvedPresentationReference.portalMask,
            portalShowsBackdropCutout: resolvedPresentationReference.portalShowsBackdropCutout,
            sourceUserInterfaceStyle: sourceUserInterfaceStyle
        )
        overlayView.frame = window.bounds
        overlayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(overlayView)
        overlayView.activatePresentationIfNeeded()
        return overlayView
    }
}
