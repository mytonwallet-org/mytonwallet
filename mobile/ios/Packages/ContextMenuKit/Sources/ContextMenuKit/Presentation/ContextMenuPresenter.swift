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
        let resolvedPresentationReference = presentationReference ?? ContextMenuPresentationReference.from(view: sourceView)
        let overlayView = ContextMenuOverlayView(
            configuration: configuration,
            sourceRectInWindow: resolvedPresentationReference.anchorRectInWindow,
            portalSourceView: resolvedPresentationReference.portalSourceView,
            portalMaskRectInWindow: resolvedPresentationReference.portalMaskRectInWindow,
            portalMask: resolvedPresentationReference.portalMask,
            portalShowsBackdropCutout: resolvedPresentationReference.portalShowsBackdropCutout
        )
        overlayView.frame = window.bounds
        overlayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(overlayView)
        overlayView.activatePresentationIfNeeded()
        return overlayView
    }
}
