import UIComponents
import UIKit

/// Shows rows leaving the chat, over the messages and clipped to them: each turns to dust where it stood, as Telegram's
/// deleted messages do, or, with Reduce Motion or without the effect, fades out
final class AgentMessageDissolveView: UIView {
    private static let fadeDuration: TimeInterval = 0.2

    /// Called when the last row has gone, so the chat can remove the view
    var onEmpty: (() -> Void)?

    private var dustEffectView: DustEffectView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = true
        backgroundColor = .clear
        accessibilityElementsHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Takes `image`, a row as it stood at `frame` in this view's coordinates, out of the chat. It shows with the current
    /// transaction, so the row's own cell is hidden in the same one.
    func dissolve(_ image: UIImage, at frame: CGRect) {
        if !UIAccessibility.isReduceMotionEnabled, DustEffectView.isAvailable {
            let existingDustEffectView = dustEffectView
            if (existingDustEffectView ?? makeDustEffectView()).addItem(frame: frame, image: image) {
                return
            }
            if existingDustEffectView == nil {
                removeDustEffectView()
            }
        }
        fadeOut(image, at: frame)
    }

    private func makeDustEffectView() -> DustEffectView {
        let dustEffectView = DustEffectView(frame: bounds)
        dustEffectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dustEffectView.becameEmpty = { [weak self, weak dustEffectView] in
            guard let self, let dustEffectView, self.dustEffectView === dustEffectView else { return }
            self.removeDustEffectView()
            self.notifyIfEmpty()
        }
        addSubview(dustEffectView)
        self.dustEffectView = dustEffectView
        return dustEffectView
    }

    private func removeDustEffectView() {
        dustEffectView?.removeFromSuperview()
        dustEffectView = nil
    }

    private func fadeOut(_ image: UIImage, at frame: CGRect) {
        let imageView = UIImageView(image: image)
        imageView.frame = frame
        addSubview(imageView)
        UIView.animate(withDuration: Self.fadeDuration, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            imageView.alpha = 0
        } completion: { [weak self] _ in
            imageView.removeFromSuperview()
            self?.notifyIfEmpty()
        }
    }

    private func notifyIfEmpty() {
        guard subviews.isEmpty else { return }
        onEmpty?()
    }
}
