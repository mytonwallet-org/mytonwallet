import UIKit

struct ContextMenuPresentationReference {
    var anchorRectInWindow: CGRect
    var portalSourceView: UIView?
    var portalMaskRectInWindow: CGRect?
    var portalMask: ContextMenuSourcePortalMask?
    var portalShowsBackdropCutout: Bool
    var portalAppliesRightToLeftTransformCorrection: Bool

    init(
        anchorRectInWindow: CGRect,
        portalSourceView: UIView? = nil,
        portalMaskRectInWindow: CGRect? = nil,
        portalMask: ContextMenuSourcePortalMask? = nil,
        portalShowsBackdropCutout: Bool = false,
        portalAppliesRightToLeftTransformCorrection: Bool = true
    ) {
        self.anchorRectInWindow = anchorRectInWindow
        self.portalSourceView = portalSourceView
        self.portalMaskRectInWindow = portalMaskRectInWindow
        self.portalMask = portalMask
        self.portalShowsBackdropCutout = portalShowsBackdropCutout
        self.portalAppliesRightToLeftTransformCorrection = portalAppliesRightToLeftTransformCorrection
    }

    @MainActor
    static func from(view: UIView, sourcePortal: ContextMenuSourcePortal? = nil) -> ContextMenuPresentationReference {
        let anchorRectInWindow = view.convert(view.bounds, to: nil)
        guard let sourcePortal else {
            return ContextMenuPresentationReference(anchorRectInWindow: anchorRectInWindow)
        }
        return ContextMenuPresentationReference(
            anchorRectInWindow: anchorRectInWindow,
            portalSourceView: sourcePortal.sourceViewProvider?() ?? view,
            portalMaskRectInWindow: anchorRectInWindow,
            portalMask: sourcePortal.mask,
            portalShowsBackdropCutout: sourcePortal.showsBackdropCutout,
            portalAppliesRightToLeftTransformCorrection: sourcePortal.appliesRightToLeftTransformCorrection
        )
    }
}
