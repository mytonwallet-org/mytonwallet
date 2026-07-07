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
        
    /// In fact this sets UILabel of standard font size as the content view.
    public func setTitle(_ title: String, fixedColor: Bool = false) {
        if let oldLabel = contentView as? UILabel {
            oldLabel.text = title
            setNeedsLayout()
            return
        }
        
        let label: UILabel = fixedColor ? FixedColorLabel() : UILabel()
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.text = title
        label.textColor = .label
        label.numberOfLines = 1
        setContentView(label)
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
