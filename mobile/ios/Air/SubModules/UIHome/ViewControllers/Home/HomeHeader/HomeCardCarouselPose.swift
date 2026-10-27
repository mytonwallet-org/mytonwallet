import UIKit

/// The selected 15-degree Cover Flow, scaled from the NFT carousel to the home card.
struct HomeCardCarouselPose {
    var transform: CATransform3D
    var offset: CGFloat

    static func make(position: CGFloat, width: CGFloat, enabled: Bool) -> Self {
        guard enabled else {
            return Self(transform: CATransform3DIdentity, offset: 0)
        }
        let distance = min(1, max(-1, position * 1.7))
        let angle = -distance * 15 * .pi / 180
        let camera = 150 * width / 84
        let pivot = 0.6 * width * (position > 0 ? 1 : -1)
        var transform = CATransform3DIdentity
        transform.m34 = -1 / camera
        transform = CATransform3DTranslate(transform, pivot, 0, 0)
        transform = CATransform3DRotate(transform, angle, 0, 1, 0)
        transform = CATransform3DTranslate(transform, -pivot, 0, 0)
        // Preserve the requested gap at the projected inner edge of a settled neighbour.
        let innerX = position > 0 ? -width / 2 : width / 2
        let projectedX = (innerX * transform.m11 + transform.m41) / (innerX * transform.m14 + transform.m44)
        let offset = (innerX - projectedX) * min(1, abs(position))
        return Self(transform: transform, offset: offset)
    }
}
