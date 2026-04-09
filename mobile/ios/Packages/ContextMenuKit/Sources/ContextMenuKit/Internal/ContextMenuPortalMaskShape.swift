import SwiftUI
import UIKit

@MainActor
enum ContextMenuPortalMaskShape {
    static func path(for mask: ContextMenuSourcePortalMask, in rect: CGRect) -> CGPath {
        switch mask {
        case .attachmentRect:
            return CGPath(rect: rect, transform: nil)
        case let .roundedAttachmentRect(cornerRadius, cornerCurve):
            return RoundedRectangle(cornerRadius: cornerRadius, style: cornerCurve.roundedCornerStyle)
                .path(in: rect)
                .cgPath
        case let .customAttachmentPath(pathProvider):
            return pathProvider(rect)
        }
    }
}

private extension ContextMenuCornerCurve {
    var roundedCornerStyle: RoundedCornerStyle {
        switch self {
        case .circular:
            return .circular
        case .continuous:
            return .continuous
        }
    }
}
