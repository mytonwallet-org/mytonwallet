//
//  WSegmentedControl.swift
//  MyTonWalletAir
//
//  Created by nikstar on 15.11.2025.
//

import SwiftUI
import UIKit
import WalletContext
import Perception

public final class WSegmentedControl: HostingView {
    
    public let model: SegmentedControlModel

    public init(model: SegmentedControlModel, scrollContentMargin: CGFloat = 0) {
        self.model = model
        super.init {
            SegmentedControl(model: model, scrollContentMargin: scrollContentMargin)
        }
    }

    public func embed(in navigationItem: UINavigationItem) {
        removeFromSuperview()
        navigationItem.titleView = _NavBarContainer(segmentedControl: self)
    }
}

private class _NavBarContainer: UIView {
    private let segmentedControl: WSegmentedControl
    private var centerXConstraint: NSLayoutConstraint!
    private var centerYConstraint: NSLayoutConstraint!
    private var widthConstraint: NSLayoutConstraint!

    init(segmentedControl: WSegmentedControl) {
        self.segmentedControl = segmentedControl

        super.init(frame: .zero)
        
        autoresizingMask = [.flexibleWidth, .flexibleHeight]

        addSubview(segmentedControl)
        centerXConstraint = segmentedControl.centerXAnchor.constraint(equalTo: centerXAnchor)
        centerYConstraint = segmentedControl.centerYAnchor.constraint(equalTo: centerYAnchor)
        widthConstraint = segmentedControl.widthAnchor.constraint(equalToConstant: 200)
        NSLayoutConstraint.activate([
            centerXConstraint,
            centerYConstraint,
            widthConstraint,
        ])
        
        observeModel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func observeModel() {
        withPerceptionTracking {
            _ = segmentedControl.model.items
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.invalidateIntrinsicContentSize()
                self?.setNeedsLayout()
                self?.observeModel()
            }
        }
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.layoutFittingExpandedSize.width, height: segmentedControl.model.constants.fullHeightWithBackground)
    }
    
    override func didMoveToWindow() {
        super.didMoveToWindow()
        layoutSegmentControl()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutSegmentControl()
    }

    private func layoutSegmentControl() {
        var navBar: UIView?
        do {
            var v: UIView? = superview
            while let view = v {
                if let nb = view as? UINavigationBar {
                    navBar = nb
                    break
                }
                v = view.superview
            }
        }
        
        guard let navBar else { return }
        
        let model = segmentedControl.model
        let width = min(bounds.width, model.calculateContentWidth(includeBackground: true))
        let navMidInContainer = navBar.convert(CGPoint(x: navBar.bounds.midX, y: 0), to: self).x
        let offset = navMidInContainer - bounds.midX
        let halfSlack = max(0, bounds.width - width) / 2
        centerXConstraint.constant = offset.clamped(to: -halfSlack...halfSlack)
        centerYConstraint.constant = -model.constants.topInset / 2
        widthConstraint.constant = CGFloat(width)
    }

}
