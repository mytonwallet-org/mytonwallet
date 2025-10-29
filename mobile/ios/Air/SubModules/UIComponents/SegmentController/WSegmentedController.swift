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
    private let constraintToTopSafeArea: Bool
    private let primaryTextColor: UIColor?
    private let secondaryTextColor: UIColor?
    private let capsuleFillColor: UIColor?
    private var animator: ValueAnimator?
    public var delegate: Delegate?

    public private(set) var model: SegmentedControlModel

    public let blurView = WBlurView()
    public var newSegmentedControl: WSegmentedControl!

    public var separator: UIView!
    public private(set) var scrollView: UIScrollView!

    private(set) public var viewControllers: [WSegmentedControllerContent]!

    private var contentLeadingConstraint: NSLayoutConstraint!
    private var scrollViewWidthConstraint: NSLayoutConstraint!

    public init(viewControllers: [WSegmentedControllerContent],
                items: [SegmentedControlItem]? = nil,
                defaultIndex: Int = 0,
                barHeight: CGFloat = 44,
                goUnderNavBar: Bool = true,
                animationSpeed: AnimationSpeed = .fast,
                constraintToTopSafeArea: Bool = true,
                primaryTextColor: UIColor? = nil,
                secondaryTextColor: UIColor? = nil,
                capsuleFillColor: UIColor? = nil,
                delegate: Delegate? = nil) {
        self.barHeight = barHeight
        self.goUnderNavBar = goUnderNavBar
        self.constraintToTopSafeArea = constraintToTopSafeArea
        self.animationSpeed = animationSpeed
        self.primaryTextColor = primaryTextColor
        self.secondaryTextColor = secondaryTextColor
        self.capsuleFillColor = capsuleFillColor
        self.model = .init(items: items ?? [])
        self.delegate = delegate
        super.init(frame: .zero)
        setupViews(viewControllers: viewControllers)
        setupModel(viewControllers: viewControllers, selectedIndex: defaultIndex)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupModel(viewControllers: [WSegmentedControllerContent], selectedIndex: Int) {
        if !model.items.isEmpty {
            model.selection = .init(item1: model.items[selectedIndex].id)
        } else {
            var items: [SegmentedControlItem] = []
            var selectedId: String?
            for (idx, vc) in viewControllers.enumerated() {
                let item = SegmentedControlItem(
                    index: idx,
                    id: vc.title ?? "\(idx + 1)",
                    content: AnyView(Text(vc.title ?? "\(idx + 1)"))
                )
                items.append(item)
                if idx == selectedIndex {
                    selectedId = item.id
                }
            }
            model.setItems(items)
            if let selectedId {
                model.selection = .init(item1: selectedId)
            }
        }
        model.primaryColor = primaryTextColor ?? WTheme.primaryLabel
        model.secondaryColor = secondaryTextColor ?? WTheme.secondaryLabel
        model.capsuleColor = capsuleFillColor ?? WTheme.thumbBackground
        model.onSelect = { [weak self] item in
            self?.handleSegmentChange(to: item.index, animated: true)
        }
    }

    private func setupViews(viewControllers: [WSegmentedControllerContent]) {
        self.viewControllers = viewControllers

        var constraints = [NSLayoutConstraint]()

        // ScrollView is only used to position other views and have bounces. It's empty and views are its sibilings to prevent swipe to dismiss issues.
        scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.canCancelContentTouches = true
        scrollView.delaysContentTouches = false
        scrollView.decelerationRate = .init(rawValue: 0.998)
        scrollView.delegate = self
        scrollView.isHidden = true
//        scrollView.isPagingEnabled = true
        addSubview(scrollView)

        // Add all view-controllers
        for (i, viewController) in viewControllers.enumerated() {
            viewController.view.translatesAutoresizingMaskIntoConstraints = false
            self.viewControllers[i].onScroll = { [weak self] y in
                guard let self else {return}
                onInnerScroll(y: y, animated: true)
            }
            addSubview(viewController.view)
            constraints.append(contentsOf: [
                viewController.view.widthAnchor.constraint(equalTo: widthAnchor),
                viewController.view.heightAnchor.constraint(equalTo: scrollView.heightAnchor),
            ])
            if i == 0 {
                contentLeadingConstraint = leadingAnchor.constraint(equalTo: viewController.view.leadingAnchor)
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
            separator.topAnchor.constraint(equalTo: constraintToTopSafeArea ? safeAreaLayoutGuide.topAnchor : topAnchor,
                                           constant: barHeight),
            separator.leftAnchor.constraint(equalTo: leftAnchor),
            separator.rightAnchor.constraint(equalTo: rightAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.33),
            scrollView.contentLayoutGuide.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            scrollView.contentLayoutGuide.topAnchor.constraint(equalTo: scrollView.topAnchor),
            scrollView.contentLayoutGuide.heightAnchor.constraint(lessThanOrEqualTo: scrollView.heightAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor, constant: goUnderNavBar ? 0 : 44),
            scrollView.leftAnchor.constraint(equalTo: leftAnchor),
            scrollView.rightAnchor.constraint(equalTo: rightAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollViewWidthConstraint
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

        newSegmentedControl = WSegmentedControl(model: model)
        newSegmentedControl.translatesAutoresizingMaskIntoConstraints = false
        addSubview(newSegmentedControl)

        NSLayoutConstraint.activate([
            newSegmentedControl.centerXAnchor.constraint(equalTo: centerXAnchor),
            newSegmentedControl.topAnchor.constraint(
                equalTo: constraintToTopSafeArea ? safeAreaLayoutGuide.topAnchor : topAnchor,
                constant: barHeight == 56 ? 16 : (barHeight - 24) / 2 + 3
            ),
            newSegmentedControl.heightAnchor.constraint(equalToConstant: 24),
            newSegmentedControl.widthAnchor.constraint(equalTo: widthAnchor)
        ])

        DispatchQueue.main.async { [self] in
            if let selectedIndex {
                self.handleSegmentChange(to: selectedIndex, animated: false)
            }
        }
    }

    @MainActor
    public func replace(viewControllers: [WSegmentedControllerContent], items: [SegmentedControlItem], force: Bool = false) {
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
                addSubview(viewController.view)
                constraints.append(contentsOf: [
                    viewController.view.widthAnchor.constraint(equalTo: widthAnchor),
                    viewController.view.heightAnchor.constraint(equalTo: scrollView.heightAnchor),
                ])
                if i == 0 {
                    contentLeadingConstraint = leadingAnchor.constraint(equalTo: viewController.view.leadingAnchor)
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

            NSLayoutConstraint.activate(constraints)

            scrollViewWidthConstraint?.isActive = false
            scrollViewWidthConstraint = scrollView.contentLayoutGuide.widthAnchor.constraint(equalTo: scrollView.widthAnchor, multiplier: CGFloat(viewControllers.count))
            scrollViewWidthConstraint.isActive = true

            bringSubviewToFront(scrollView)
            bringSubviewToFront(separator)
            bringSubviewToFront(blurView)
            bringSubviewToFront(newSegmentedControl)
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

    @objc func handleSegmentChange(to index: Int, animated: Bool) {
        let targetPoint = CGPoint(x: CGFloat(index) * scrollView.frame.width, y: 0)
        if animated {
            self.animator?.invalidate()
            let animator = ValueAnimator(startValue: scrollView.contentOffset.x, endValue: targetPoint.x, duration: animationSpeed.duration)
            animator.addUpdateBlock { progress, value in
                self.scrollView.contentOffset = CGPoint(x: value, y: self.scrollView.contentOffset.y)
            }
            self.animator = animator
            animator.start()
        } else {
            scrollView.setContentOffset(targetPoint, animated: false)
            updatePanGesture(index: index)
        }
        self.viewControllers[index].view.addGestureRecognizer(scrollView.panGestureRecognizer)
        updateNavBar(index: index, animated: animated)
    }

    private func onInnerScroll(y: CGFloat, animated: Bool) {
        if y > 0, separator.alpha == 0 {
            if animated {
                UIView.animate(withDuration: 0.3) { [weak self] in
                    guard let self else {return}
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
        return newSegmentedControl?.model.selectedItem?.index
    }

    public func switchTo(tabIndex: Int) {
        newSegmentedControl.model.setRawProgress(CGFloat(tabIndex))
    }

    public func updatePanGesture(index: Int) {
        viewControllers[index].view.addGestureRecognizer(scrollView.panGestureRecognizer)
    }
    public var panGestureEnabled: Bool {
        get {
            return scrollView.isScrollEnabled
        }
        set {
            scrollView.isScrollEnabled = newValue
        }
    }

    private func updateNavBar(index: Int, animated: Bool) {
        onInnerScroll(y: viewControllers[index].scrollPosition, animated: animated)
    }
}

extension WSegmentedController: UIScrollViewDelegate {
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let progress = scrollView.contentOffset.x / scrollView.frame.width
        newSegmentedControl.model.setRawProgress(progress)
        delegate?.segmentedController(scrollOffsetChangedTo: progress)
        contentLeadingConstraint?.constant = scrollView.contentOffset.x
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
        let pageWidth = scrollView.frame.width
        let pageCount = viewControllers.count
        let velocity = scrollView.panGestureRecognizer.velocity(in: scrollView)
        let currentPage = scrollView.contentOffset.x / pageWidth

        var targetPage: Int
        if abs(velocity.x) > 10 {
            targetPage = velocity.x > 0 ? Int(floor(currentPage)) : Int(ceil(currentPage))
        } else {
            targetPage = Int(round(currentPage))
        }
        targetPage = max(0, min(targetPage, pageCount - 1))
        let targetX = CGFloat(targetPage) * scrollView.frame.width

        let isBouncingWithVelocity = velocity.x != 0 && (scrollView.contentOffset.x < 0 || (targetPage == pageCount - 1 && scrollView.contentOffset.x > targetX))
        if !isBouncingWithVelocity {
            targetContentOffset.pointee.x = scrollView.contentOffset.x
            let deltaX = max(1, abs(targetX - scrollView.contentOffset.x))
            self.animator?.invalidate()
            let animator = ValueAnimator(startValue: scrollView.contentOffset.x, endValue: targetX, duration: animationSpeed.duration, initialVelocity: abs(velocity.x / deltaX))
            animator.addUpdateBlock { progress, value in
                scrollView.contentOffset = CGPoint(x: value, y: scrollView.contentOffset.y)
            }
            animator.addCompletionBlock { [weak self] in
                self?.delegate?.segmentedControllerDidEndScrolling()
                self?.updateNavBar(index: targetPage, animated: true)
            }
            self.animator = animator
            animator.start()
        }
        updatePanGesture(index: targetPage)
    }
}
