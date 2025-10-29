//
//  ExpandableNavigationView.swift
//  MyTonWalletAir
//
//  Created by Sina on 11/11/24.
//

import UIKit
import WalletContext

public class ExpandableNavigationView: WTouchPassView, WThemedView {

    @MainActor public protocol ExpandableContent {
        var stickyView: WTouchPassView { get }
        var contentView: WTouchPassView { get }
        func update(scrollOffset: CGFloat)
    }
    public let expandableContent: ExpandableContent

    private let navigationBar: WNavigationBar

    public init(navigationBar: WNavigationBar, expandableContent: ExpandableContent) {
        self.navigationBar = navigationBar
        navigationBar.blurView.alpha = 0
        self.expandableContent = expandableContent
        super.init(frame: .zero)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var stickyViewTopConstraint: NSLayoutConstraint!
    private var stickyViewHeightConstraint: NSLayoutConstraint!

    private func setupViews() {
        translatesAutoresizingMaskIntoConstraints = false

        let expandableStickyView = expandableContent.stickyView
        let expandableContentView = expandableContent.contentView

        addSubview(expandableContentView)
        addSubview(navigationBar)
        addSubview(expandableStickyView)

        stickyViewTopConstraint = expandableStickyView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: S.headerTopAdjustment)
        stickyViewHeightConstraint = expandableStickyView.heightAnchor.constraint(equalToConstant: 100)
        let expandableContentViewBottomConstraint = expandableContentView.bottomAnchor.constraint(equalTo: bottomAnchor)
        expandableContentViewBottomConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            bottomAnchor.constraint(greaterThanOrEqualTo: navigationBar.bottomAnchor, constant: 0.33),

            navigationBar.leftAnchor.constraint(equalTo: leftAnchor),
            navigationBar.rightAnchor.constraint(equalTo: rightAnchor),
            navigationBar.topAnchor.constraint(equalTo: topAnchor),

            stickyViewTopConstraint,
            stickyViewHeightConstraint,
            expandableStickyView.leftAnchor.constraint(equalTo: leftAnchor),
            expandableStickyView.rightAnchor.constraint(equalTo: rightAnchor),

            expandableContentView.leftAnchor.constraint(equalTo: leftAnchor),
            expandableContentView.rightAnchor.constraint(equalTo: rightAnchor),
            expandableContentView.topAnchor.constraint(equalTo: topAnchor, constant: -1000), // Workaround to prevent chart re-render glitches!
            expandableContentViewBottomConstraint,
        ])

        if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
            navigationBar.blurView.isHidden = true
            navigationBar.backButton?.isHidden = true
            navigationBar.trailingItem?.view.isHidden = true
            navigationBar.separatorView.isHidden = true
        }
        
        updateTheme()
    }

    public func updateTheme() {
        backgroundColor = UIColor.clear
    }

    public func update(scrollOffset: CGFloat) {
        stickyViewHeightConstraint.constant = scrollOffset <= 0 ? 112 : max(38, 112 - scrollOffset)

        expandableContent.update(scrollOffset: scrollOffset)

        navigationBar.titleStackView.alpha = min(1, max(0, (30 - scrollOffset) / 14 + 1))
        navigationBar.titleStackViewCenterYAnchor.constant = scrollOffset <= 0 ? 0 : -scrollOffset

        let blurAlpha = min(1, max(0, (scrollOffset - 260) / 16))
        navigationBar.blurView.alpha = blurAlpha
        navigationBar.separatorView.alpha = blurAlpha
    }
}
