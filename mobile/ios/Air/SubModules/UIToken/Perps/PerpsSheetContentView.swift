import SwiftUI
import UIKit
import UIComponents

/// Native scrolling and safe-area handling shared by review and receipt sheets.
final class PerpsSheetContentView: UIView {
    let scrollView = UIScrollView()
    private let footer: UIView?
    private var footerGradient: EdgeGradientView?
    private var footerBottom: NSLayoutConstraint?

    init(content: UIView, footer: UIView? = nil, footerBackground: UIColor = .clear) {
        self.footer = footer
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.contentInsetAdjustmentBehavior = .automatic
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.delaysContentTouches = false
        if #available(iOS 26, *) {
            scrollView.topEdgeEffect.isHidden = true
            scrollView.bottomEdgeEffect.isHidden = true
        }
        addSubview(scrollView)
        scrollView.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        let width = content.widthAnchor.constraint(equalTo: safeAreaLayoutGuide.widthAnchor)
        width.priority = .defaultHigh
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.contentLayoutGuide.widthAnchor.constraint(equalTo: safeAreaLayoutGuide.widthAnchor),
            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            content.centerXAnchor.constraint(equalTo: safeAreaLayoutGuide.centerXAnchor),
            content.widthAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.widthAnchor),
            content.widthAnchor.constraint(lessThanOrEqualToConstant: 560),
            width,
        ])
        if let footer {
            let background = EdgeGradientView()
            background.direction = .bottom
            background.color = footerBackground
            footerGradient = background
            background.translatesAutoresizingMaskIntoConstraints = false
            background.isUserInteractionEnabled = false
            footer.translatesAutoresizingMaskIntoConstraints = false
            addSubview(background)
            addSubview(footer)
            let width = footer.widthAnchor.constraint(equalTo: safeAreaLayoutGuide.widthAnchor, constant: -72)
            width.priority = .defaultHigh
            let bottom = footer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -36)
            footerBottom = bottom
            NSLayoutConstraint.activate([
                footer.centerXAnchor.constraint(equalTo: safeAreaLayoutGuide.centerXAnchor),
                footer.widthAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.widthAnchor, constant: -72),
                footer.widthAnchor.constraint(lessThanOrEqualToConstant: 488),
                width, bottom,
                background.topAnchor.constraint(equalTo: footer.topAnchor, constant: -24),
                background.bottomAnchor.constraint(equalTo: bottomAnchor),
                background.leadingAnchor.constraint(equalTo: leadingAnchor),
                background.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])
        }
    }

    override func layoutSubviews() {
        footerBottom?.constant = -max(36, safeAreaInsets.bottom)
        super.layoutSubviews()
        footerGradient?.solidEdgeLength = footer.map { bounds.maxY - $0.frame.minY } ?? 0
        let bottom = footer.map { max(0, bounds.maxY - $0.frame.minY - safeAreaInsets.bottom) + 24 } ?? 0
        if abs(scrollView.contentInset.bottom - bottom) > 0.5 {
            scrollView.contentInset.bottom = bottom
        }
    }

    static func prepare<Content: View>(_ hosting: UIHostingController<Content>) {
        hosting.sizingOptions = .intrinsicContentSize
        if #available(iOS 16.4, *) { hosting.safeAreaRegions = [] }
        else { hosting.disableSafeArea() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}
