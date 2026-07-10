//
//  NavigationHeader.swift
//  MyTonWalletAir
//
//  Created by nikstar on 10.11.2025.
//

import SwiftUI
import UIKit

public struct NavigationHeader<Title: View, Subtitle: View>: View {
    
    var title: Title
    var subtitle: Subtitle
    
    public init(@ViewBuilder title: () -> Title, @ViewBuilder subtitle: () -> Subtitle) {
        self.title = title()
        self.subtitle = subtitle()
    }
    
    public var body: some View {
        VStack(spacing: 2) {
            _title
            _subtitle
        }
        .frame(minWidth: 240, idealWidth: 240)
    }
    
    var _title: some View {
        title
            .font(.system(size: 17, weight: .semibold))
            .lineLimit(1)
    }
    
    var _subtitle: some View {
        subtitle
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(.secondary)
            .allowsTightening(true)
            .lineLimit(1)
            .offset(y: 1)
    }
}

extension NavigationHeader where Subtitle == EmptyView {
    public init(@ViewBuilder title: () -> Title) {
        self.title = title()
        self.subtitle = EmptyView()
    }
}

/// Inherits UILabel to make native iOS26 blur work
open class NavigationHeader2: UILabel {
    private let contentHeight = 44.0
    private var centerXConstraint: NSLayoutConstraint!
    private var centerYConstraint: NSLayoutConstraint!
    private var widthConstraint: NSLayoutConstraint!
    private var heightConstraint: NSLayoutConstraint!
    private var tapRecognizer: UITapGestureRecognizer?
    private var prevSize: CGSize?
    private var _visibilityAlpha: CGFloat? = nil

    public private(set) var contentView: UIView?
    public weak var viewToRedirectTouchesTo: UIView?
    public var onMovedToWindow: ((UIWindow?) -> Void)?
    public var onSizeChanged: (() -> Void)?

    override public init(frame: CGRect) {
        super.init(frame: frame)

        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        isUserInteractionEnabled = true
        accessibilityElementsHidden = true
        textColor = .clear // this is important for native iOS26 blur color management
    }

    @available(*, unavailable)
    required public init?(coder: NSCoder) { fatalError() }
    
    public var distanceFromNavigationBarBottomToContentCenter: CGFloat {
        guard let navBar = navigationBar else { return contentHeight / 2 }
        return navBar.bounds.maxY - convert(bounds.center, to: navBar).y
    }

    public static func makeTitleLabel(_ title: String, fixedColor: Bool = false) -> UILabel {
        let label: UILabel = fixedColor ? FixedColorLabel() : UILabel()
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.text = title
        label.textColor = .label
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        return label
    }
        
    /// In fact this sets UILabel of standard font size as the content view.
    public func setTitle(_ title: String, fixedColor: Bool = false) {
        if let oldLabel = contentView as? UILabel {
            oldLabel.text = title
            setNeedsLayout()
            return
        }

        setContentView(Self.makeTitleLabel(title, fixedColor: fixedColor))
    }

    public func setTitleAnimated(_ title: String) {
        UIView.transition(with: self, duration: 0.25, options: .transitionCrossDissolve) {
            self.setTitle(title)
        }
    }
    
    /// Set this to override UIKit's alpha auto-management (e.g. scroll-driven fades or during transitions).
    /// Set to nil to restore normal UIKit control.
    public var visibilityAlpha: CGFloat? {
        get { _visibilityAlpha }
        set {
            _visibilityAlpha = newValue
            super.alpha = newValue ?? 1.0
        }
    }
    
    override public var alpha: CGFloat {
        get { super.alpha }
        set {
            // When we own the alpha, ignore UIKit's writes (transitions, bar animations)
            guard _visibilityAlpha == nil else { return }
            super.alpha = newValue
        }
    }

    public func setContentView(_ view: UIView) {
        guard contentView !== view else { return }
        
        NSLayoutConstraint.deactivate([centerXConstraint, widthConstraint, centerYConstraint, heightConstraint].compactMap { $0 })
        contentView?.removeFromSuperview()

        contentView = view
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        centerXConstraint = view.centerXAnchor.constraint(equalTo: centerXAnchor)
        centerYConstraint = view.centerYAnchor.constraint(equalTo: centerYAnchor)
        widthConstraint = view.widthAnchor.constraint(equalToConstant: view.frame.width)
        heightConstraint = view.heightAnchor.constraint(lessThanOrEqualToConstant: contentHeight)
        NSLayoutConstraint.activate([
            centerYConstraint,
            centerXConstraint,
            widthConstraint,
            heightConstraint
        ])
        
        setNeedsLayout()
    }

    public func setStack(of views: [UIView], spacing: CGFloat = 0, truncatingAt indices: IndexSet = [0]) {
        setContentView(_HorizontalStackView(views: views, spacing: spacing, truncatingAt: indices))
    }
        
    /// Common case: taping on transparent header for proxing to a scrolled controls underneath.
    public var onTap: ((UITapGestureRecognizer) -> Void)? {
        didSet {
            if onTap == nil {
                if let tapRecognizer {
                    removeGestureRecognizer(tapRecognizer)
                    self.tapRecognizer = nil
                }
            } else {
                if oldValue == nil {
                    let g = UITapGestureRecognizer(target: self, action: #selector(onTap(_:)))
                    addGestureRecognizer(g)
                    tapRecognizer = g
                }
            }
        }
    }
    
    @objc private func onTap(_ recognizer: UITapGestureRecognizer) {
        guard let onTap else {
            assertionFailure()
            return
        }
        onTap(recognizer)
    }
    
    open override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let view = viewToRedirectTouchesTo, view.isUserInteractionEnabled {
            let local = convert(point, to: view)
            if let v = view.hitTest(local, with: event) {
                return v
            }
        }
        return super.hitTest(point, with: event)
    }
                    
    open override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.layoutFittingExpandedSize.width, height: contentHeight)
    }
        
    open override func sizeThatFits(_ size: CGSize) -> CGSize {
        return CGSize(width: 2000, height: contentHeight)
    }
            
    open override func didMoveToWindow() {
        super.didMoveToWindow()
        layoutContent()
        onMovedToWindow?(window)
    }

    open override func layoutSubviews() {
        super.layoutSubviews()
        layoutContent()
        
        if prevSize != bounds.size {
            prevSize = bounds.size
            onSizeChanged?()
        }
    }
    
    private var navigationBar: UINavigationBar? {
        var ancestor = superview
        while let view = ancestor {
            if let n = view as? UINavigationBar {
                return n
            }
            ancestor = view.superview
        }
        return nil
    }
    
    private func layoutContent() {
        guard let navBar = navigationBar, let contentView, bounds.width > 0 else { return }
        
        let contentSize = contentView.intrinsicContentSize
        let width = min(bounds.width, ceil(contentSize.width))
        let navMidInContainer = navBar.convert(CGPoint(x: navBar.bounds.inset(by: navBar.safeAreaInsets).midX, y: 0), to: self).x
        let offset = navMidInContainer - bounds.midX
        let halfSlack = max(0, bounds.width - width) / 2
        centerXConstraint.constant = offset.clamped(to: -halfSlack...halfSlack)
        widthConstraint.constant = CGFloat(width)
    }
}

private final class _HorizontalStackView: UIView {
    private var arrangedSubviews: [UIView] = []
    private var spacing: CGFloat = 0
    private var truncatingIndices: IndexSet = [0]

    init(views: [UIView] = [], spacing: CGFloat = 0, truncatingAt indices: IndexSet = [0]) {
        self.spacing = spacing
        self.truncatingIndices = indices
        super.init(frame: .zero)
        clipsToBounds = true
        setArrangedSubviews(views, spacing: spacing, truncatingAt: indices)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setArrangedSubviews(_ views: [UIView], spacing: CGFloat, truncatingAt indices: IndexSet) {
        self.spacing = spacing
        self.truncatingIndices = indices
        arrangedSubviews.forEach { $0.removeFromSuperview() }
        arrangedSubviews = views
        for view in views {
            addSubview(view)
        }
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        superview?.setNeedsLayout()
    }

    override var intrinsicContentSize: CGSize {
        let visibleEntries = visibleSubviewEntries()
        guard !visibleEntries.isEmpty else { return .zero }

        var width: CGFloat = 0
        var height: CGFloat = 0
        for (index, entry) in visibleEntries.enumerated() {
            let size = contentSize(for: entry.view)
            width += size.width
            if index > 0 {
                width += spacing
            }
            height = max(height, size.height)
        }
        return CGSize(width: width, height: height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let visibleEntries = visibleSubviewEntries()
        guard !visibleEntries.isEmpty else { return }

        let sizes = layoutSizes(for: visibleEntries)
        let isRTL = effectiveUserInterfaceLayoutDirection == .rightToLeft
        var x = isRTL ? bounds.maxX : bounds.minX

        for (index, entry) in visibleEntries.enumerated() {
            let size = sizes[index]
            let y = bounds.midY - size.height / 2

            if isRTL {
                x -= size.width
                entry.view.frame = CGRect(x: x, y: y, width: size.width, height: size.height)
                if index < visibleEntries.count - 1 {
                    x -= spacing
                }
            } else {
                entry.view.frame = CGRect(x: x, y: y, width: size.width, height: size.height)
                x += size.width
                if index < visibleEntries.count - 1 {
                    x += spacing
                }
            }
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.layoutDirection != previousTraitCollection?.layoutDirection {
            setNeedsLayout()
        }
    }

    private struct SubviewEntry {
        var index: Int
        var view: UIView
    }

    private func visibleSubviewEntries() -> [SubviewEntry] {
        arrangedSubviews.enumerated().compactMap { index, view in
            view.isHidden ? nil : SubviewEntry(index: index, view: view)
        }
    }

    private func layoutSizes(for entries: [SubviewEntry]) -> [CGSize] {
        var sizes = entries.map { contentSize(for: $0.view) }
        guard bounds.width > 0 else { return sizes }

        let spacingTotal = spacing * CGFloat(max(0, entries.count - 1))
        let totalWidth = sizes.reduce(0) { $0 + $1.width } + spacingTotal
        guard totalWidth > bounds.width else { return sizes }

        var excess = totalWidth - bounds.width
        for (sizeIndex, entry) in entries.enumerated() where truncatingIndices.contains(entry.index) {
            guard excess > 0 else { break }
            let shrinkBy = min(excess, sizes[sizeIndex].width)
            sizes[sizeIndex].width -= shrinkBy
            excess -= shrinkBy
        }
        if excess > 0 {
            for sizeIndex in entries.indices.reversed() where !truncatingIndices.contains(entries[sizeIndex].index) {
                guard excess > 0 else { break }
                let shrinkBy = min(excess, sizes[sizeIndex].width)
                sizes[sizeIndex].width -= shrinkBy
                excess -= shrinkBy
            }
        }
        return sizes
    }

    private func contentSize(for view: UIView) -> CGSize {
        let intrinsic = view.intrinsicContentSize
        var width = intrinsic.width
        var height = intrinsic.height
        let fittingWidth = CGFloat.greatestFiniteMagnitude

        if width == UIView.noIntrinsicMetric || width < 0 {
            width = view.sizeThatFits(CGSize(width: fittingWidth, height: fittingWidth)).width
        }
        if height == UIView.noIntrinsicMetric || height < 0 {
            height = view.sizeThatFits(CGSize(width: width, height: fittingWidth)).height
        }

        return CGSize(width: ceil(max(0, width)), height: ceil(max(0, height)))
    }
}

/// A label whose color ignores the iOS 26 navigation bar's content-adaptive tinting.
///
/// When a scroll view is at the root of a hosting controller, iOS 26 samples the scroll
/// content's color and flips the `userInterfaceStyle` trait on the nav bar's content so that
/// dynamic colors (e.g. `.label`) re-resolve to stay legible over whatever is underneath.
/// We defeat this by resolving the assigned dynamic color against the *window's* real trait
/// collection instead of our own (flipped) one, and re-resolving on any trait change so
/// genuine dark/light switches are still honored.
private final class FixedColorLabel: UILabel {
    private var sourceColor: UIColor?

    override init(frame: CGRect) {
        super.init(frame: frame)
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: FixedColorLabel, _) in
                view.applyResolvedColor()
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var textColor: UIColor! {
        get { super.textColor }
        set {
            sourceColor = newValue
            applyResolvedColor()
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applyResolvedColor()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyResolvedColor()
    }

    private func applyResolvedColor() {
        guard let sourceColor else { return }
        let traits = window?.traitCollection ?? traitCollection
        super.textColor = sourceColor.resolvedColor(with: traits)
    }
}
