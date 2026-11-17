import UIComponents
import UIKit
import WalletContext

extension SplitHomeActionItem {
    var toolbarItem: HomeToolbarItem {
        switch self {
        case .buy: .buy
        case .deposit: .fund
        case .earn: .earn
        case .scan: .scan
        case .sell: .sell
        case .send: .send
        case .swap: .trade
        }
    }

    init?(toolbarItem: HomeToolbarItem) {
        guard let item = Self.allCases.first(where: { $0.toolbarItem == toolbarItem }) else { return nil }
        self = item
    }
}

/// Follows one finger for a host that takes over a drag begun elsewhere, such as in a sheet that then goes away. On a
/// window it keeps getting the touch after the view under the finger has left the screen. It never recognizes, so it
/// takes nothing from the views and recognizers below it.
@MainActor
final class HomeToolbarTouchTracker: UIGestureRecognizer {
    /// The finger's place in its window
    var onMove: ((CGPoint) -> Void)?
    var onEnd: ((CGPoint, _ isCancelled: Bool) -> Void)?
    private(set) var trackedTouch: UITouch?
    private var touchCount = 0

    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        touchCount += touches.count
        if trackedTouch == nil { trackedTouch = touches.first }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard let trackedTouch, touches.contains(trackedTouch) else { return }
        onMove?(trackedTouch.location(in: nil))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        release(touches, isCancelled: false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        release(touches, isCancelled: true)
    }

    override func reset() {
        super.reset()
        touchCount = 0
        if let trackedTouch {
            self.trackedTouch = nil
            onEnd?(trackedTouch.location(in: nil), true)
        }
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    private func release(_ touches: Set<UITouch>, isCancelled: Bool) {
        touchCount = max(0, touchCount - touches.count)
        if let trackedTouch, touches.contains(trackedTouch) {
            self.trackedTouch = nil
            onEnd?(trackedTouch.location(in: nil), isCancelled)
        }
        // Failing ends the recognizer's turn without taking anything from the others
        if touchCount == 0 { state = .failed }
    }
}

/// An action's tile as the actions menu draws it, for the copy that leaves the menu under the finger
@MainActor
final class ActionMenuTileView: UIView {
    static let size: CGFloat = 67

    init(item: SplitHomeActionItem) {
        super.init(frame: CGRect(x: 0, y: 0, width: Self.size, height: Self.size))
        let background = UIImageView(image: .airBundle(item.actionMenuBackgroundAssetName))
        background.frame = bounds
        background.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        background.layer.cornerRadius = 24
        background.layer.cornerCurve = .continuous
        background.clipsToBounds = true
        addSubview(background)
        let glyph = UIImageView(image: .airBundle(item.actionMenuGlyphAssetName))
        glyph.bounds.size = item.actionMenuGlyphSize
        glyph.center = CGPoint(x: bounds.midX, y: bounds.midY)
        glyph.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin, .flexibleTopMargin, .flexibleBottomMargin]
        addSubview(glyph)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Says where a lifted action can go, above the actions menu
@MainActor
final class HomeToolbarDragHintView: UIView {
    private let effectView = UIVisualEffectView()
    private let label = UILabel()

    init(text: String) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        if IOS_26_MODE_ENABLED, #available(iOS 26, *) {
            effectView.effect = UIGlassEffect(style: .regular)
            effectView.cornerConfiguration = .capsule()
        } else {
            effectView.effect = UIBlurEffect(style: .systemMaterial)
            effectView.clipsToBounds = true
        }
        label.text = text
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = .label
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
        addSubview(effectView)
        effectView.contentView.addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        effectView.frame = bounds
        effectView.layer.cornerRadius = IOS_26_MODE_ENABLED ? 0 : bounds.height / 2
        label.frame = bounds.insetBy(dx: 16, dy: 0)
    }

    /// Shows the hint in `window` above `frame`, a rect in the window's coordinates
    func show(in window: UIWindow, above frame: CGRect) {
        let width = min(window.bounds.width - 32, ceil(label.intrinsicContentSize.width) + 32)
        bounds.size = CGSize(width: width, height: 38)
        center = CGPoint(x: window.bounds.midX, y: frame.minY - 16 - bounds.height / 2)
        alpha = 0
        transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        window.addSubview(self)
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0,
                       options: [.beginFromCurrentState]) {
            self.alpha = 1
            self.transform = .identity
        }
    }

    func hide() {
        UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .curveEaseIn]) {
            self.alpha = 0
            self.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        } completion: { _ in
            self.removeFromSuperview()
        }
    }
}
