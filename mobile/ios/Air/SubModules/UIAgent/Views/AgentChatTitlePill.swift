import UIKit
import UIComponents
import WalletContext

/// The chat's title on a capsule of Liquid Glass, as Telegram's chat header has it. The capsule hugs the title and
/// follows its width on the glass spring when the title changes. The glass is interactive, so it swells and stretches
/// under the finger as the header's round buttons do.
@MainActor
public final class AgentChatTitlePill: UIView {
    static let horizontalPadding: CGFloat = 16
    static let height: CGFloat = 44

    /// The title inside the glass
    public let contentView: UIView
    private let glassView = WGlassView(cornerRadius: nil)

    init(titleView: UIView) {
        contentView = titleView
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: Self.height))
        // The blur that stands in for the glass leaves the touches to the pill
        if glassView.effect is UIBlurEffect {
            glassView.isUserInteractionEnabled = false
        }
        addSubview(glassView)
        titleView.translatesAutoresizingMaskIntoConstraints = true
        glassView.contentView.addSubview(titleView)
        (titleView as? AgentChatTitleView)?.onFittingWidthChange = { [weak self] in
            self?.handleTitleWidthChange()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var contentWidth: CGFloat {
        (contentView as? AgentChatTitleView)?.fittingWidth ?? ceil(contentView.intrinsicContentSize.width)
    }

    /// A copy of the title for a transition that draws the glass itself; nil for a title that isn't laid out
    public func makeContentCopy() -> UIView? {
        guard let title = contentView as? AgentChatTitleView, title.bounds.width > 0, title.bounds.height > 0 else {
            return nil
        }
        return title.makeTransitionCopy()
    }

    public override var intrinsicContentSize: CGSize {
        CGSize(width: contentWidth + 2 * Self.horizontalPadding, height: Self.height)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        glassView.frame = bounds
        contentView.frame = bounds.insetBy(dx: Self.horizontalPadding, dy: 0)
    }

    private func handleTitleWidthChange() {
        invalidateIntrinsicContentSize()
        guard let header = superview else { return }
        header.setNeedsLayout()
        guard window != nil, UIView.areAnimationsEnabled, !UIAccessibility.isReduceMotionEnabled else {
            header.layoutIfNeeded()
            return
        }
        let animations = { header.layoutIfNeeded() }
        if #available(iOS 17.0, *) {
            UIView.animate(springDuration: 0.416, bounce: 0.25, initialSpringVelocity: 0, delay: 0, options: [.allowUserInteraction], animations: animations)
        } else {
            UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0, options: [.allowUserInteraction], animations: animations)
        }
    }
}
