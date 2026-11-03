import UIKit

/// The motion of the full-screen media viewers, the NFT viewer's and the one that pages through pictures: the spring
/// that flies media in and out, and how a swipe down follows the finger and decides to close
public enum MediaViewerMotion {
    public static var duration: TimeInterval { UIAccessibility.isReduceMotionEnabled ? 0.15 : 0.32 }
    public static var collapseDuration: TimeInterval { UIAccessibility.isReduceMotionEnabled ? 0.15 : 0.28 }
    public static let damping: CGFloat = 0.94

    /// Where media dragged by `translation` stands: it follows the finger down and up, a quarter as far sideways, and
    /// shrinks a little on the way
    public static func getDismissTransform(for translation: CGPoint, in bounds: CGRect) -> CGAffineTransform {
        let progress = min(1, abs(translation.y) / max(1, bounds.height * 0.5))
        let scale = UIAccessibility.isReduceMotionEnabled ? 1 : 1 - progress * 0.08
        return CGAffineTransform(translationX: translation.x * 0.25, y: translation.y).scaledBy(x: scale, y: scale)
    }

    /// How much of the black backdrop stays as media is dragged by `translation`
    public static func getBackdropAlpha(for translation: CGPoint) -> CGFloat {
        max(0, 1 - abs(translation.y) / 200)
    }

    /// A drag that ends past a fifth of the height, or a quick throw, closes the viewer
    public static func shouldDismiss(translation: CGPoint, velocity: CGPoint, in bounds: CGRect) -> Bool {
        abs(translation.y) > bounds.height * 0.2 || (abs(velocity.y) > 800 && abs(translation.y) > 12)
    }
}
