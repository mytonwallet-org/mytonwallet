//
//  WSegmentedController.swift
//  UIComponents
//
//  Created by Sina on 6/25/24.
//

import SwiftUI
import UIKit
import WalletContext

@MainActor
public protocol WSegmentedControllerContent: AnyObject {
    var onScroll: ((_ y: CGFloat) -> Void)? { get set }
    var onScrollStart: (() -> Void)? { get set }
    var onScrollEnd: (() -> Void)? { get set }
    var view: UIView! { get }
    var title: String? { get set }
    var scrollingView: UIScrollView? { get }
    func scrollToTop(animated: Bool)
    var calculatedHeight: CGFloat { get }
}

public extension WSegmentedControllerContent {
    var calculatedHeight: CGFloat { 0 }
}

extension WSegmentedControllerContent {
    var scrollPosition: CGFloat {
        return (scrollingView?.contentOffset.y ?? 0) + (scrollingView?.contentInset.top ?? 0)
    }
}

@MainActor
public class WSegmentedController: WTouchPassView {

    @MainActor public protocol Delegate: AnyObject {
        func segmentedController(scrollOffsetChangedTo progress: CGFloat)
        func segmentedControllerDidStartDragging()
        func segmentedControllerDidEndScrolling()
    }

    public enum AnimationSpeed {
        case fast
        case medium
        case slow

        var duration: CGFloat {
            switch self {
            case .fast:
                0.3
            case .medium:
                0.4
            case .slow:
                0.5
            }
        }
    }
    public var animationSpeed: AnimationSpeed

    private static let notSelectedDefaultAttr = [
        NSAttributedString.Key.font: UIFont.systemFont(ofSize: 17, weight: .semibold),
        NSAttributedString.Key.foregroundColor: WTheme.secondaryLabel
    ]
    private static let selectedDefaultAttr = [
        NSAttributedString.Key.font: UIFont.systemFont(ofSize: 17, weight: .semibold),
        NSAttributedString.Key.foregroundColor: WTheme.primaryLabel
    ]

    private let barHeight: CGFloat
    private let goUnderNavBar: Bool
    private let primaryTextColor: UIColor?
    private let secondaryTextColor: UIColor?
    private let capsuleFillColor: UIColor?
    public var delegate: Delegate?

    public private(set) var model: SegmentedControlModel

    public let blurView = WBlurView()
    public var segmentedControl: WSegmentedControl!

    public var separator: UIView!
    public private(set) var scrollView: UIScrollView!

    private(set) public var viewControllers: [WSegmentedControllerContent]!

    private var contentLeadingConstraint: NSLayoutConstraint!
    private var scrollViewWidthConstraint: NSLayoutConstraint!

    public init(items: [SegmentedControlItem],
                defaultItemId: String? = nil,
                barHeight: CGFloat = 44,
                goUnderNavBar: Bool = true,
                animationSpeed: AnimationSpeed = .fast,
                primaryTextColor: UIColor? = nil,
                secondaryTextColor: UIColor? = nil,
                capsuleFillColor: UIColor? = nil,
                delegate: Delegate? = nil) {
        self.barHeight = barHeight
        self.goUnderNavBar = goUnderNavBar
        self.animationSpeed = animationSpeed
        self.primaryTextColor = primaryTextColor
        self.secondaryTextColor = secondaryTextColor
        self.capsuleFillColor = capsuleFillColor
        self.model = .init(items: items)
        self.delegate = delegate
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let viewControllers = items.map(\.viewController)
        self.viewControllers = viewControllers
        setupViews(viewControllers: viewControllers)
        setupModel(viewControllers: viewControllers, selectedId: defaultItemId)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupModel(viewControllers: [WSegmentedControllerContent], selectedId: String?) {
        if !model.items.isEmpty {
            if let selectedId {
                model.selection = .init(item1: selectedId)
            } else {
                model.selection = .init(item1: model.items[0].id)
            }
        }
        model.primaryColor = primaryTextColor ?? WTheme.primaryLabel
        model.secondaryColor = secondaryTextColor ?? WTheme.secondaryLabel
        model.capsuleColor = capsuleFillColor ?? WTheme.thumbBackground
        model.onSelect = { [weak self] item in
            guard let self else { return }
            if let index = model.getItemIndexById(itemId: item.id) {
                handleSegmentChange(to: index, animated: true)
            }
        }
    }

    private func setupViews(viewControllers: [WSegmentedControllerContent]) {
        self.viewControllers = viewControllers

        var constraints = [NSLayoutConstraint]()

        scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.canCancelContentTouches = true
        scrollView.delaysContentTouches = false
        scrollView.decelerationRate = .fast
        scrollView.delegate = self
        scrollView.isPagingEnabled = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.alwaysBounceVertical = false
        if #available(iOS 17.4, *) {
            scrollView.bouncesVertically = false
        }
        if #available(iOS 26.0, *) {
            scrollView.topEdgeEffect.isHidden = true
        }
        addSubview(scrollView)

        // Add all view-controllers
        for (i, viewController) in viewControllers.enumerated() {
            viewController.view.translatesAutoresizingMaskIntoConstraints = false
            self.viewControllers[i].onScroll = { [weak self] y in
                guard let self else {return}
                onInnerScroll(y: y, animated: true)
            }
            scrollView.addSubview(viewController.view)
            constraints.append(contentsOf: [
                viewController.view.widthAnchor.constraint(equalTo: widthAnchor),
                viewController.view.heightAnchor.constraint(equalTo: scrollView.heightAnchor),
            ])
            if i == 0 {
                contentLeadingConstraint = scrollView.contentLayoutGuide.leadingAnchor.constraint(equalTo: viewController.view.leadingAnchor)
                constraints.append(contentsOf: [
                    viewController.view.topAnchor.constraint(equalTo: scrollView.topAnchor),
                    contentLeadingConstraint,
                ])
            } else {
                let prevView = viewControllers[i - 1].view!
                constraints.append(contentsOf: [
                    viewController.view.topAnchor.constraint(equalTo: prevView.topAnchor),
                    viewController.view.leadingAnchor.constraint(equalTo: prevView.trailingAnchor),
                ])
            }
        
            viewController.scrollToTop(animated: false)
        }

        bringSubviewToFront(scrollView)

        separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = WTheme.separator
        separator.alpha = 0
        addSubview(separator)
        scrollViewWidthConstraint = scrollView.contentLayoutGuide.widthAnchor.constraint(equalTo: scrollView.widthAnchor, multiplier: CGFloat(viewControllers.count))

        constraints.append(contentsOf: [
            separator.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor,
                                           constant: barHeight),
            separator.leftAnchor.constraint(equalTo: leftAnchor),
            separator.rightAnchor.constraint(equalTo: rightAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.33),
            scrollView.topAnchor.constraint(equalTo: topAnchor, constant: goUnderNavBar ? 0 : 44),
            scrollView.leftAnchor.constraint(equalTo: leftAnchor),
            scrollView.rightAnchor.constraint(equalTo: rightAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.contentLayoutGuide.heightAnchor.constraint(equalTo: scrollView.heightAnchor),
            scrollViewWidthConstraint,
        ])

        blurView.alpha = 0
        addSubview(blurView)
        NSLayoutConstraint.activate([
            blurView.leftAnchor.constraint(equalTo: leftAnchor),
            blurView.rightAnchor.constraint(equalTo: rightAnchor),
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.bottomAnchor.constraint(equalTo: separator.topAnchor),
        ])

        NSLayoutConstraint.activate(constraints)

        segmentedControl = WSegmentedControl(model: model)
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        addSubview(segmentedControl)

        NSLayoutConstraint.activate([
            segmentedControl.centerXAnchor.constraint(equalTo: centerXAnchor),
            segmentedControl.topAnchor.constraint(
                equalTo: topAnchor,
                constant: (barHeight - 24) / 2 + 3
            ),
            segmentedControl.heightAnchor.constraint(equalToConstant: SegmentedControlConstants.height),
            segmentedControl.widthAnchor.constraint(equalTo: widthAnchor)
        ])

        DispatchQueue.main.async { [self] in
            if let selectedIndex {
                self.handleSegmentChange(to: selectedIndex, animated: false)
            }
        }
    }

    public func replace(items: [SegmentedControlItem], force: Bool = false) {
        let viewControllers = items.map(\.viewController)
        UIView.performWithoutAnimation {
            let oldViewControllers = self.viewControllers ?? []
            let oldSelected = selectedIndex.flatMap { oldViewControllers[$0] }
            let oldItems = model.items

            if items == oldItems && zip(viewControllers, oldViewControllers).allSatisfy({ $0 === $1 }) && !force {
                return
            }

            var newSelected = 0

            self.viewControllers = viewControllers

            var constraints = [NSLayoutConstraint]()

            for vc in oldViewControllers {
                vc.view.removeFromSuperview()
            }

            // Add all view-controllers
            for (i, viewController) in viewControllers.enumerated() {
                if viewController === oldSelected {
                    newSelected = i
                }

                viewController.view.translatesAutoresizingMaskIntoConstraints = false
                self.viewControllers[i].onScroll = { [weak self] y in
                    guard let self else {return}
                    onInnerScroll(y: y, animated: true)
                }
                scrollView.addSubview(viewController.view)
                constraints.append(contentsOf: [
                    viewController.view.widthAnchor.constraint(equalTo: widthAnchor),
                    viewController.view.heightAnchor.constraint(equalTo: scrollView.heightAnchor),
                ])
                if i == 0 {
                    contentLeadingConstraint = scrollView.contentLayoutGuide.leadingAnchor.constraint(equalTo: viewController.view.leadingAnchor)
                    constraints.append(contentsOf: [
                        viewController.view.topAnchor.constraint(equalTo: scrollView.topAnchor),
                        contentLeadingConstraint,
                    ])
                } else {
                    let prevView = viewControllers[i - 1].view!
                    constraints.append(contentsOf: [
                        viewController.view.topAnchor.constraint(equalTo: prevView.topAnchor),
                        viewController.view.leadingAnchor.constraint(equalTo: prevView.trailingAnchor),
                    ])
                }
                if i == viewControllers.count - 1 {
                    constraints.append(contentsOf: [
                        viewController.view.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
                    ])
                }
                viewController.scrollToTop(animated: false)
            }

            NSLayoutConstraint.activate(constraints)

            scrollViewWidthConstraint?.isActive = false
            scrollViewWidthConstraint = scrollView.contentLayoutGuide.widthAnchor.constraint(equalTo: scrollView.widthAnchor, multiplier: CGFloat(viewControllers.count))
            scrollViewWidthConstraint.isActive = true

            bringSubviewToFront(scrollView)
            bringSubviewToFront(separator)
            bringSubviewToFront(blurView)
            bringSubviewToFront(segmentedControl)
            setNeedsLayout()
            layoutIfNeeded()

            DispatchQueue.main.async {
                UIView.performWithoutAnimation {
                    self.model.setItems(items)
                    self.model.onSelect(items[0])
                    self.handleSegmentChange(to: 0, animated: false)
                    self.delegate?.segmentedController(scrollOffsetChangedTo: CGFloat(0))

                    self.setNeedsLayout()
                    self.layoutIfNeeded()
                }
            }
        }
    }

    @objc public func handleSegmentChange(to index: Int, animated: Bool) {
        let targetPoint = CGPoint(x: CGFloat(index) * scrollView.frame.width, y: 0)
        let progress = targetPoint.x / scrollView.frame.width
        if animated {
            withAnimation(.spring(duration: 0.25)) {
                segmentedControl.model.setRawProgress(progress)
            }
            UIView.animateAdaptive(duration: animationSpeed.duration) { [self] in
                scrollView.setContentOffset(targetPoint, animated: false)
                delegate?.segmentedController(scrollOffsetChangedTo: progress)
            }
        } else {
            scrollView.setContentOffset(targetPoint, animated: false)
            delegate?.segmentedController(scrollOffsetChangedTo: progress)
        }
        updateNavBar(index: index, animated: animated)
    }

    private func onInnerScroll(y: CGFloat, animated: Bool) {
        if y > 0, separator.alpha == 0 {
            if animated {
                UIView.animate(withDuration: 0.3) { [weak self] in
                    guard let self else { return }
                    separator.alpha = 1
                    blurView.alpha = 1
                }
            } else {
                separator.alpha = 1
                blurView.alpha = 1
            }
        } else if y <= 0, separator?.alpha ?? 0 > 0 {
            if animated {
                UIView.animate(withDuration: 0.3) { [weak self] in
                    guard let self else {return}
                    separator.alpha = 0
                    blurView.alpha = 0
                }
            } else {
                separator.alpha = 0
                blurView.alpha = 0
            }
        }
    }

    public func updateTheme() {
    }

    public func scrollToTop(animated: Bool) {
        if let selectedIndex {
            viewControllers?[selectedIndex].scrollToTop(animated: animated)
        }
    }

    public var selectedIndex: Int? {
        if let itemId =  segmentedControl?.model.selectedItem?.id {
            return model.getItemIndexById(itemId: itemId)
        }
        return nil
    }

    public func switchTo(tabIndex: Int) {
        segmentedControl.model.setRawProgress(CGFloat(tabIndex))
    }

    private func updateNavBar(index: Int, animated: Bool) {
        onInnerScroll(y: viewControllers[index].scrollPosition, animated: animated)
    }
}

extension WSegmentedController: UIScrollViewDelegate {
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView.frame.width > 0 else { return }
        let progress = scrollView.contentOffset.x / scrollView.frame.width
        if scrollView.isDragging {
            segmentedControl.model.setRawProgress(progress)
            delegate?.segmentedController(scrollOffsetChangedTo: progress)
        }
        if viewControllers.count >= 2 {
            let navAlpha = (viewControllers[0].scrollPosition > 0 ? 1 : 0) * (1 - progress) + (viewControllers[1].scrollPosition > 0 ? 1 : 0) * progress
            separator.alpha = navAlpha
            blurView.alpha = navAlpha
        }
    }
    
    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        delegate?.segmentedControllerDidStartDragging()
    }
    
    public func scrollViewWillEndDragging(_ scrollView: UIScrollView,
                                          withVelocity velocity: CGPoint,
                                          targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        // sometimes, default pagin behavior skips pages (0 -> 1 -> 3 ?!)
        if (targetContentOffset.pointee.x - scrollView.contentOffset.x) > scrollView.frame.width {
            targetContentOffset.pointee.x -= scrollView.frame.width
        } else if (targetContentOffset.pointee.x - scrollView.contentOffset.x) < -scrollView.frame.width {
            targetContentOffset.pointee.x += scrollView.frame.width
        }
        let progress = targetContentOffset.pointee.x / scrollView.frame.width
        withAnimation(.spring(duration: 0.25)) {
            segmentedControl.model.setRawProgress(progress)
        }
        UIView.animateAdaptive(duration: animationSpeed.duration) { [self] in
            scrollView.setContentOffset(targetContentOffset.pointee, animated: false)
            let progress = scrollView.contentOffset.x / scrollView.frame.width
            delegate?.segmentedController(scrollOffsetChangedTo: progress)
        }
    }
}
