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

    public init(
        sourceViewProvider: (() -> UIView?)? = nil,
        mask: ContextMenuSourcePortalMask = .attachmentRect,
        showsBackdropCutout: Bool = false
    ) {
        self.sourceViewProvider = sourceViewProvider
        self.mask = mask
        self.showsBackdropCutout = showsBackdropCutout
    }
}
