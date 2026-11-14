import SwiftUI
import UIKit
import UIComponents

/// Scrolling cards above persistent actions, shared by asset pages and trade sheets.
final class AssetDetailsView: UIView {
    let scrollView = UIScrollView()
    let content: UIStackView
    private let notice = NativeTradeNoticeView(frame: .zero)
    private let actionContent = UIStackView()

    convenience init(sections: [UIView], buttons: [WButton], background: UIColor = .air.groupedBackground) {
        let actions = buttons.isEmpty ? nil : WActionButtonBar(buttons: buttons)
        actions?.heightAnchor.constraint(equalToConstant: WButton.height(for: .primary)).isActive = true
        self.init(sections: sections, footer: actions, background: background)
    }

    init(sections: [UIView], footer: UIView?, background: UIColor) {
        content = UIStackView(arrangedSubviews: sections)
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
        bottomEdgeEffect.update(content: background, blur: true, alpha: 0.85, edge: .bottom, edgeSize: 48)
        bottomEdgeEffect.isHidden = footer == nil
        actionContent.axis = .vertical
        actionContent.spacing = 12
        actionContent.translatesAutoresizingMaskIntoConstraints = false
        actionContent.addArrangedSubview(notice)
        if let footer { actionContent.addArrangedSubview(footer) }
        actionContent.isHidden = footer == nil
        notice.isHidden = true
        addSubview(bottomEdgeEffect)
        addSubview(actionContent)
        let contentWidth = content.widthAnchor.constraint(equalTo: safeAreaLayoutGuide.widthAnchor, constant: -32)
        contentWidth.priority = .defaultHigh
        let actionsWidth = actionContent.widthAnchor.constraint(equalTo: safeAreaLayoutGuide.widthAnchor, constant: -72)
        actionsWidth.priority = .defaultHigh
        let actionsBottom = actionContent.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -2)
        actionsBottom.priority = .defaultHigh
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
            actionContent.bottomAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.bottomAnchor, constant: -2),
            actionContent.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -36),
            actionsBottom,
            bottomEdgeEffect.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomEdgeEffect.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomEdgeEffect.topAnchor.constraint(equalTo: actionContent.topAnchor, constant: -16),
            bottomEdgeEffect.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// Fills `parent` edge to edge.
    func install(in parent: UIView) {
        parent.addSubview(self)
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: parent.topAnchor),
            bottomAnchor.constraint(equalTo: parent.bottomAnchor),
            leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            trailingAnchor.constraint(equalTo: parent.trailingAnchor),
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

    func setActionNotice(_ message: String?, isInformational: Bool = false) {
        notice.isHidden = message == nil
        if let message { notice.update(.init(title: "", message: message, isInformational: isInformational), animated: false) }
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

    /// Hosted SwiftUI sections size to their content and leave safe areas to this view.
    static func prepare<Content: View>(_ hosting: UIHostingController<Content>) {
        hosting.sizingOptions = .intrinsicContentSize
        if #available(iOS 16.4, *) { hosting.safeAreaRegions = [] }
        else { hosting.disableSafeArea() }
    }
}

extension View {
    /// Keeps a hosted section at the top of its host while the two heights differ. The host can still have the
    /// previous height when the content is measured, and the content animates to a height the host already has;
    /// either way centered content would jump by half the change. The host's intrinsic height stays the content's.
    func alignedToHostTop() -> some View {
        fixedSize(horizontal: false, vertical: true)
            .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
    }
}
