import UIKit
import UIComponents

/// Shared scrolling cards and persistent actions for asset detail screens.
final class AssetDetailsView: UIView {
    let scrollView = UIScrollView()
    let content: UIStackView
    private let actions: WActionButtonBar
    private let notice = NativeTradeNoticeView(frame: .zero)
    private let actionContent = UIStackView()

    init(sections: [UIView], buttons: [WButton]) {
        content = UIStackView(arrangedSubviews: sections)
        actions = WActionButtonBar(buttons: buttons)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .automatic
        scrollView.delaysContentTouches = false
        if #available(iOS 26, *) {
            scrollView.topEdgeEffect.isHidden = true
            scrollView.bottomEdgeEffect.isHidden = true
        }
        addSubview(scrollView)
        content.axis = .vertical
        content.spacing = 16
        content.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(content)

        let bottomEdgeEffect = EdgeEffectView()
        bottomEdgeEffect.translatesAutoresizingMaskIntoConstraints = false
        bottomEdgeEffect.update(content: .air.groupedBackground, blur: true, alpha: 0.85, edge: .bottom, edgeSize: 48)
        bottomEdgeEffect.isHidden = buttons.isEmpty
        actionContent.axis = .vertical
        actionContent.spacing = 12
        actionContent.translatesAutoresizingMaskIntoConstraints = false
        actionContent.addArrangedSubview(notice)
        actionContent.addArrangedSubview(actions)
        actionContent.isHidden = buttons.isEmpty
        notice.isHidden = true
        addSubview(bottomEdgeEffect)
        addSubview(actionContent)
        let contentWidth = content.widthAnchor.constraint(equalTo: safeAreaLayoutGuide.widthAnchor, constant: -32)
        contentWidth.priority = .defaultHigh
        let actionsWidth = actionContent.widthAnchor.constraint(equalTo: safeAreaLayoutGuide.widthAnchor, constant: -72)
        actionsWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 8),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16),
            content.centerXAnchor.constraint(equalTo: safeAreaLayoutGuide.centerXAnchor),
            content.widthAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.widthAnchor, constant: -32),
            content.widthAnchor.constraint(lessThanOrEqualToConstant: 500),
            scrollView.contentLayoutGuide.widthAnchor.constraint(equalTo: safeAreaLayoutGuide.widthAnchor),
            contentWidth,
            actionsWidth,
            actionContent.widthAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.widthAnchor, constant: -72),
            actionContent.widthAnchor.constraint(lessThanOrEqualToConstant: 500),
            actionContent.centerXAnchor.constraint(equalTo: safeAreaLayoutGuide.centerXAnchor),
            actionContent.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -2),
            actions.heightAnchor.constraint(equalToConstant: WButton.height(for: .primary)),
            bottomEdgeEffect.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomEdgeEffect.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomEdgeEffect.topAnchor.constraint(equalTo: actionContent.topAnchor, constant: -16),
            bottomEdgeEffect.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // UIKit supplies the safe-area inset; reserve only the overlapping actions and their gap.
        let bottomInset = actionContent.isHidden ? 0 : max(0, bounds.maxY - actionContent.frame.minY - safeAreaInsets.bottom) + 12
        if abs(scrollView.contentInset.bottom - bottomInset) > 0.5 {
            scrollView.contentInset.bottom = bottomInset
        }
    }

    func setActionNotice(_ message: String?) {
        notice.isHidden = message == nil
        if let message { notice.update(.init(title: "", message: message), animated: false) }
        setNeedsLayout()
    }

    func layoutKeepingScrollPosition() {
        let savedOffset = scrollView.contentOffset
        UIView.performWithoutAnimation {
            layoutIfNeeded()
            let maximumOffset = max(-scrollView.adjustedContentInset.top,
                                    scrollView.contentSize.height + scrollView.adjustedContentInset.bottom - scrollView.bounds.height)
            scrollView.contentOffset = CGPoint(x: savedOffset.x, y: min(savedOffset.y, maximumOffset))
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}
