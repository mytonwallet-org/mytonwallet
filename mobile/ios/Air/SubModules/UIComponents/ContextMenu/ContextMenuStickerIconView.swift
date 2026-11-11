import ContextMenuKit
import LottieKit
import UIKit
import WalletContext

/// A menu row icon drawn by a TGS animation whose last frame is the icon, in the row's tint color
public final class ContextMenuStickerIconView: UIView, ContextMenuAnimatedIconView {
    // Classic plays its tab icons at double speed
    private static let playbackSpeed = 2.0

    private let animationView = LottieAnimationView()

    /// Nil when the bundle has no `<animationName>.tgs` or it can't be read
    public init?(animationName: String) {
        guard let path = AirBundle.path(forResource: animationName, ofType: "tgs") else {
            return nil
        }
        super.init(frame: .zero)
        animationView.playbackSpeed = Self.playbackSpeed
        // Frames come in the file's colors; as templates they take the tint color, as the icon image does
        animationView.onFrameRendered = { [weak animationView] _ in
            guard let animationView, let image = animationView.image, image.renderingMode != .alwaysTemplate else {
                return
            }
            animationView.image = image.withRenderingMode(.alwaysTemplate)
        }
        addSubview(animationView)
        do {
            try animationView.setAnimationSynchronously(source: .file(path: path), playbackMode: .still(position: .end))
        } catch {
            return nil
        }
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        animationView.frame = bounds
    }

    public func playHighlightAnimation() {
        animationView.playOnce()
    }
}
