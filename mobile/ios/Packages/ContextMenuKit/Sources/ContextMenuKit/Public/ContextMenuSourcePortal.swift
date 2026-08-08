import UIKit

public enum ContextMenuCornerCurve: Sendable {
    case circular
    case continuous
}

public enum ContextMenuSourcePortalMask {
    case attachmentRect
    case roundedAttachmentRect(cornerRadius: CGFloat, cornerCurve: ContextMenuCornerCurve = .circular)
    case customAttachmentPath(@MainActor (_ attachmentRect: CGRect) -> CGPath)
}

public struct ContextMenuSourcePortal {
    public var sourceViewProvider: (() -> UIView?)?
    public var mask: ContextMenuSourcePortalMask
    public var showsBackdropCutout: Bool
    /// Disable when the source resolves RTL geometry itself instead of inheriting UIKit's mirrored transform.
    public var appliesRightToLeftTransformCorrection: Bool

    public init(
        sourceViewProvider: (() -> UIView?)? = nil,
        mask: ContextMenuSourcePortalMask = .attachmentRect,
        showsBackdropCutout: Bool = false,
        appliesRightToLeftTransformCorrection: Bool = true
    ) {
        self.sourceViewProvider = sourceViewProvider
        self.mask = mask
        self.showsBackdropCutout = showsBackdropCutout
        self.appliesRightToLeftTransformCorrection = appliesRightToLeftTransformCorrection
    }
}
