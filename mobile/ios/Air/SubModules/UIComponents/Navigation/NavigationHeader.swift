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
public class NavigationHeader2: UILabel {
    private let contentHeight = 44.0
    private var centerXConstraint: NSLayoutConstraint!
    private var centerYConstraint: NSLayoutConstraint!
    private var widthConstraint: NSLayoutConstraint!
    private var heightConstraint: NSLayoutConstraint!

    public private(set) var contentView: UIView?
    
    override public init(frame: CGRect) {
        super.init(frame: frame)

        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        isUserInteractionEnabled = true
        accessibilityElementsHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

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
            
    public override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.layoutFittingExpandedSize.width, height: contentHeight)
    }
        
    public override func sizeThatFits(_ size: CGSize) -> CGSize {
        return CGSize(width: 1000, height: contentHeight)
    }
            
    public override func didMoveToWindow() {
        super.didMoveToWindow()
        layoutContent()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        layoutContent()
    }
    
    private func layoutContent() {
        let navBar: UIView? = {
            var ancestor = superview
            while let view = ancestor {
                if view is UINavigationBar { return view }
                ancestor = view.superview
            }
            return nil
        }()
        
        guard let navBar, let contentView, bounds.width > 0 else { return }
        
        let contentSize = contentView.intrinsicContentSize
        let width = min(bounds.width, ceil(contentSize.width))
        let navMidInContainer = navBar.convert(CGPoint(x: navBar.bounds.midX, y: 0), to: self).x
        let offset = navMidInContainer - bounds.midX
        let halfSlack = max(0, bounds.width - width) / 2
        centerXConstraint.constant = offset.clamped(to: -halfSlack...halfSlack)
        widthConstraint.constant = CGFloat(width)
    }
}
