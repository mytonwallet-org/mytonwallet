import UIKit

final class NftDetailMainScrollView: UIScrollView {

    weak var contentViewToRedirect: UIView?
    weak var headerViewToRedirect: UIView?
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let headerViewToRedirect, headerViewToRedirect.isUserInteractionEnabled {
            let local = convert(point, to: headerViewToRedirect)
            if let v = headerViewToRedirect.hitTest(local, with: event) {
                return v;
            }
        }
        
        guard let contentView = contentViewToRedirect, point.y > contentView.frame.maxY else {
            return super.hitTest(point, with: event)
        }

        let pointAtBottomOfContent = CGPoint(x: contentView.bounds.midX, y: contentView.bounds.maxY - 1)
        return contentView.hitTest(pointAtBottomOfContent, with: event) ?? contentView
    }
}
