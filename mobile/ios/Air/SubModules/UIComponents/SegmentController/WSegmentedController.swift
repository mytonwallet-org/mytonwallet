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
public protocol WSegmentedControllerContent: UIViewController {
    var onScroll: ((_ y: CGFloat) -> Void)? { get set }
    var scrollingView: UIScrollView? { get }
    func scrollToTop(animated: Bool)
    func calculateHeight(isHosted: Bool) -> CGFloat
}

extension WSegmentedControllerContent {
    var scrollPosition: CGFloat {
        return (scrollingView?.contentOffset.y ?? 0) + (scrollingView?.contentInset.top ?? 0)
    }
}

@MainActor public protocol WSegmentedControllerDelegate: AnyObject {
    func segmentedController(scrollOffsetChangedTo progress: CGFloat)
    func segmentedControllerDidStartDragging()
    func segmentedControllerDidEndScrolling()
}

public extension WSegmentedControllerDelegate {
    func segmentedController(scrollOffsetChangedTo progress: CGFloat) {}
    func segmentedControllerDidStartDragging() {}
    func segmentedControllerDidEndScrolling() {}
}

@MainActor
public class WSegmentedController: WTouchPassView {

    public typealias Delegate = WSegmentedControllerDelegate

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

    private let barHeight: CGFloat
    private let goUnderNavBar: Bool
    private let primaryTextColor: UIColor?
    private let secondaryTextColor: UIColor?
    private let capsuleFillColor: UIColor?
    private let leadingViewControllers: [WSegmentedControllerContent]
    private let segmentedItemPageOffset: Int
    private weak var delegate: Delegate?

    private var scrollTrackingProxy: _ScrollTrackingProxy?
    private var scrollTrackingGeneration: Int = 0

    public private(set) var model: SegmentedControlModel

    public let blurView = WBlurView()
    public var segmentedControl: WSegmentedControl!

    public var separator: UIView!
    public private(set) var scrollView: UIScrollView!

    private(set) public var viewControllers: [WSegmentedControllerContent]!
    private var currentPageIndex: Int

    private var contentLeadingConstraint: NSLayoutConstraint!
    private var scrollViewWidthConstraint: NSLayoutConstraint!

    public init(items: [SegmentedControlItem],
                leadingViewControllers: [WSegmentedControllerContent] = [],
                defaultItemId: String? = nil,
                barHeight: CGFloat = 44,
                goUnderNavBar: Bool = true,
                animationSpeed: AnimationSpeed = .fast,
                primaryTextColor: UIColor? = nil,
                secondaryTextColor: UIColor? = nil,
                capsuleFillColor: UIColor? = nil,
                style: SegmentedControlStyle = .regular,
                delegate: Delegate? = nil) {
        self.barHeight = barHeight
        self.goUnderNavBar = goUnderNavBar
        self.animationSpeed = animationSpeed
        self.primaryTextColor = primaryTextColor
        self.secondaryTextColor = secondaryTextColor
        self.capsuleFillColor = capsuleFillColor
        self.leadingViewControllers = leadingViewControllers
        self.segmentedItemPageOffset = leadingViewControllers.count
        self.model = .init(items: items, style: style)
        self.delegate = delegate
        let selectedSegmentIndex = defaultItemId.flatMap { id in
            items.firstIndex(where: { $0.id == id })
        } ?? 0
        self.currentPageIndex = leadingViewControllers.count + selectedSegmentIndex
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let viewControllers = leadingViewControllers + items.map(\.viewController)
        self.viewControllers = viewControllers
        setupViews(viewControllers: viewControllers)
        setupModel(selectedId: defaultItemId)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupModel(selectedId: String?) {
        if !model.items.isEmpty {
            if let selectedId {
                model.selection = .init(item1: selectedId)
            } else {
                model.selection = .init(item1: model.items[0].id)
            }
        }
        model.primaryColor = primaryTextColor ?? UIColor.label
        model.secondaryColor = secondaryTextColor ?? UIColor.air.secondaryLabel
        model.capsuleColor = capsuleFillColor ?? UIColor.air.thumbBackground
        model.onSelect = { [weak self] item in
            guard let self else { return }
            if let index = model.getItemIndexById(itemId: item.id) {
                setSelectedIndex(to: index + segmentedItemPageOffset, animated: true)
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
                viewController.view.topAnchor.constraint(equalTo: scrollView.topAnchor),
            ])
            viewController.scrollToTop(animated: false)
        }
        constraints.append(contentsOf: makePageArrangementConstraints(for: viewControllers))

        bringSubviewToFront(scrollView)

        separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = UIColor.air.separator
        separator.alpha = 0
        addSubview(separator)
        scrollViewWidthConstraint = scrollView.contentLayoutGuide.widthAnchor.constraint(equalTo: scrollView.widthAnchor, multiplier: CGFloat(viewControllers.count))

        constraints.append(contentsOf: [
            separator.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor,
                                           constant: barHeight),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.33),
            scrollView.topAnchor.constraint(equalTo: topAnchor, constant: goUnderNavBar ? 0 : barHeight),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.contentLayoutGuide.heightAnchor.constraint(equalTo: scrollView.heightAnchor),
            scrollViewWidthConstraint,
        ])

        blurView.alpha = 0
        addSubview(blurView)
        NSLayoutConstraint.activate([
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.bottomAnchor.constraint(equalTo: separator.topAnchor),
        ])

        NSLayoutConstraint.activate(constraints)

        segmentedControl = WSegmentedControl(model: model)
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        addSubview(segmentedControl)

        let constants = model.constants
        let segmentedControlTopConstant: CGFloat
        switch model.style {
        case .rootHeader, .compactRootHeader:
            segmentedControlTopConstant = (barHeight - constants.fullHeightWithBackground) / 2
        default:
            segmentedControlTopConstant = (barHeight - constants.height) / 2.0 + 3.0 - constants.topInset
        }
        NSLayoutConstraint.activate([
            segmentedControl.centerXAnchor.constraint(equalTo: centerXAnchor),
            segmentedControl.topAnchor.constraint(equalTo: topAnchor, constant: segmentedControlTopConstant),
            segmentedControl.heightAnchor.constraint(equalToConstant: constants.fullHeightWithBackground),
            segmentedControl.widthAnchor.constraint(equalTo: widthAnchor)
        ])

        DispatchQueue.main.async { [self] in
            if let selectedIndex {
                self.setSelectedIndex(to: selectedIndex, animated: false)
            }
        }
    }

    public func replace(items: [SegmentedControlItem], force: Bool = false) {
        let viewControllers = leadingViewControllers + items.map(\.viewController)
        
        // Remember current selection and try to restore it later. For the very first time
        // if effectively would be resolved to the first item in the list
        let oldSelectedID = model.selection?.effectiveSelectedItemID
        
        UIView.performWithoutAnimation {
            let oldViewControllers = self.viewControllers ?? []
            let oldItems = model.items

            if items == oldItems && zip(viewControllers, oldViewControllers).allSatisfy({ $0 === $1 }) && !force {
                return
            }

            var newSelected = segmentedItemPageOffset

            self.viewControllers = viewControllers

            var constraints = [NSLayoutConstraint]()

            for vc in oldViewControllers {
                vc.view.removeFromSuperview()
            }

            for (i, viewController) in viewControllers.enumerated() {
                let itemIndex = i - segmentedItemPageOffset
                if items.indices.contains(itemIndex), items[itemIndex].id == oldSelectedID {
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
                    viewController.view.topAnchor.constraint(equalTo: scrollView.topAnchor),
                ])
                viewController.scrollToTop(animated: false)
            }
            constraints.append(contentsOf: makePageArrangementConstraints(for: viewControllers))
            
            NSLayoutConstraint.activate(constraints)
            
            scrollViewWidthConstraint?.isActive = false
            scrollViewWidthConstraint = scrollView.contentLayoutGuide.widthAnchor.constraint(equalTo: scrollView.widthAnchor, multiplier: CGFloat(viewControllers.count))
            scrollViewWidthConstraint.isActive = true
            
            syncContentOffsetWitgSelectedItemIndex(newSelected)

            bringSubviewToFront(scrollView)
            bringSubviewToFront(separator)
            bringSubviewToFront(blurView)
            bringSubviewToFront(segmentedControl)
            setNeedsLayout()
            layoutIfNeeded()

            DispatchQueue.main.async {
                UIView.performWithoutAnimation {
                    self.model.setItems(items)
                    if let selectedItemIndex = items.indices.contains(newSelected - self.segmentedItemPageOffset)
                        ? newSelected - self.segmentedItemPageOffset
                        : nil {
                        self.model.onSelect(items[selectedItemIndex])
                    }
                    self.setSelectedIndex(to: newSelected, animated: false)
                    self.delegate?.segmentedController(scrollOffsetChangedTo: CGFloat(newSelected))

                    self.setNeedsLayout()
                    self.layoutIfNeeded()
                }
            }
        }
    }
    
    private func syncContentOffsetWitgSelectedItemIndex(_ selectedItemIndex: Int) {
        let viewportWidth = scrollView.frame.width
        if viewportWidth > 0 {
            let targetPointX = contentOffsetX(forLogicalProgress: CGFloat(selectedItemIndex), viewportWidth: viewportWidth)
            let progress = CGFloat(selectedItemIndex)
            currentPageIndex = selectedItemIndex
            updateSegmentedControlProgress(pageProgress: progress)
            delegate?.segmentedController(scrollOffsetChangedTo: progress)
            scrollView.setContentOffset(CGPoint(x: targetPointX, y: 0), animated: false)
        }
    }

    private var lastWidthForRecalculation: CGFloat = 0
    
    public override func layoutSubviews() {
        super.layoutSubviews()

        let viewportWidth = scrollView.frame.width
        guard viewportWidth > 0,
            viewportWidth != lastWidthForRecalculation,
            !scrollView.isDragging,
            !scrollView.isDecelerating,
            let selection = model.selection,
            let index = model.getItemIndexById(itemId: selection.effectiveSelectedItemID) else {
            return
        }

        lastWidthForRecalculation = viewportWidth
        syncContentOffsetWitgSelectedItemIndex(index + segmentedItemPageOffset)
    }

    @objc public func setSelectedIndex(to index: Int, animated: Bool) {
        guard viewControllers.indices.contains(index) else {
            assertionFailure()
            return
        }
        
        let targetPoint = CGPoint(
            x: contentOffsetX(forLogicalProgress: CGFloat(index), viewportWidth: scrollView.frame.width),
            y: 0
        )
        let progress = CGFloat(index)
        currentPageIndex = index
        let needsMovement = abs(scrollView.contentOffset.x - targetPoint.x) > 0.5
        if animated && needsMovement {
            delegate?.segmentedControllerDidStartDragging()
            let generation = startScrollTracking()
            UIView.animateAdaptive(duration: animationSpeed.duration) { [self] in
                scrollView.setContentOffset(targetPoint, animated: false)
            } completion: { [weak self] _ in
                guard let self, scrollTrackingGeneration == generation else { return }
                stopScrollTracking(generation: generation)
                updateSegmentedControlProgress(pageProgress: progress)
                delegate?.segmentedController(scrollOffsetChangedTo: progress)
                delegate?.segmentedControllerDidEndScrolling()
            }
        } else {
            scrollView.setContentOffset(targetPoint, animated: false)
            updateSegmentedControlProgress(pageProgress: progress)
            delegate?.segmentedController(scrollOffsetChangedTo: progress)
            if animated {
                delegate?.segmentedControllerDidEndScrolling()
            }
        }
        updateNavBar(index: index, animated: animated)
    }

    private func startScrollTracking() -> Int {
        scrollTrackingGeneration &+= 1
        scrollTrackingProxy?.stop()
        scrollTrackingProxy = _ScrollTrackingProxy(self)
        return scrollTrackingGeneration
    }

    private func stopScrollTracking(generation: Int) {
        guard scrollTrackingGeneration == generation else { return }
        scrollTrackingProxy?.stop()
        scrollTrackingProxy = nil
    }

    fileprivate func updateModelFromScrollPresentation() {
        let frameWidth = scrollView.frame.width
        guard frameWidth > 0 else { return }
        let layer = scrollView.layer.presentation() ?? scrollView.layer
        let progress = logicalProgress(forContentOffsetX: layer.bounds.origin.x, viewportWidth: frameWidth)
        currentPageIndex = min(
            max(Int(progress.rounded()), 0),
            max(viewControllers.count - 1, 0)
        )
        updateSegmentedControlProgress(pageProgress: progress)
        delegate?.segmentedController(scrollOffsetChangedTo: progress)
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

    public func scrollToTop(animated: Bool) {
        if let selectedIndex {
            viewControllers?[selectedIndex].scrollToTop(animated: animated)
        }
    }

    public var selectedIndex: Int? {
        viewControllers.indices.contains(currentPageIndex) ? currentPageIndex : nil
    }

    private func updateNavBar(index: Int, animated: Bool) {
        onInnerScroll(y: viewControllers[index].scrollPosition, animated: animated)
    }

    private func makePageArrangementConstraints(for viewControllers: [WSegmentedControllerContent]) -> [NSLayoutConstraint] {
        guard !viewControllers.isEmpty else { return [] }

        let indices = Array(viewControllers.indices)
        let physicalIndices = usesRightToLeftPageLayout ? Array(indices.reversed()) : indices
        var constraints: [NSLayoutConstraint] = []

        for (position, index) in physicalIndices.enumerated() {
            let view = viewControllers[index].view!
            if position == 0 {
                contentLeadingConstraint = view.leftAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leftAnchor)
                constraints.append(contentLeadingConstraint)
            } else {
                let previousView = viewControllers[physicalIndices[position - 1]].view!
                constraints.append(view.leftAnchor.constraint(equalTo: previousView.rightAnchor))
            }

            if position == physicalIndices.count - 1 {
                constraints.append(view.rightAnchor.constraint(equalTo: scrollView.contentLayoutGuide.rightAnchor))
            }
        }

        return constraints
    }

    private var maxPageProgress: CGFloat {
        CGFloat(max((viewControllers?.count ?? 0) - 1, 0))
    }

    private var usesRightToLeftPageLayout: Bool {
        effectiveUserInterfaceLayoutDirection == .rightToLeft
    }

    private func contentOffsetX(forLogicalProgress progress: CGFloat, viewportWidth: CGFloat) -> CGFloat {
        let physicalProgress = usesRightToLeftPageLayout ? maxPageProgress - progress : progress
        return physicalProgress * viewportWidth
    }

    private func logicalProgress(forContentOffsetX offsetX: CGFloat, viewportWidth: CGFloat) -> CGFloat {
        guard viewportWidth > 0 else { return 0 }
        let physicalProgress = clamp(offsetX / viewportWidth, min: 0, max: maxPageProgress)
        return usesRightToLeftPageLayout ? maxPageProgress - physicalProgress : physicalProgress
    }

    private func scrollPositionAlpha(for progress: CGFloat) -> CGFloat {
        guard !viewControllers.isEmpty else { return 0 }

        let lowerIndex = min(viewControllers.count - 1, max(0, Int(floor(progress))))
        let upperIndex = min(viewControllers.count - 1, lowerIndex + 1)
        let fraction = progress - CGFloat(lowerIndex)
        let lowerAlpha: CGFloat = viewControllers[lowerIndex].scrollPosition > 0 ? 1 : 0
        let upperAlpha: CGFloat = viewControllers[upperIndex].scrollPosition > 0 ? 1 : 0
        return lowerAlpha * (1 - fraction) + upperAlpha * fraction
    }
}

@MainActor
private final class _ScrollTrackingProxy: NSObject {
    private weak var controller: WSegmentedController?
    private var displayLink: CADisplayLink?

    init(_ controller: WSegmentedController) {
        self.controller = controller
        super.init()
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard let controller else {
            stop()
            return
        }
        controller.updateModelFromScrollPresentation()
    }
}

extension WSegmentedController: UIScrollViewDelegate {
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView.frame.width > 0 else { return }
        let progress = logicalProgress(
            forContentOffsetX: scrollView.contentOffset.x,
            viewportWidth: scrollView.frame.width
        )
        currentPageIndex = min(
            max(Int(progress.rounded()), 0),
            max(viewControllers.count - 1, 0)
        )
        if scrollView.isDragging || scrollView.isDecelerating {
            updateSegmentedControlProgress(pageProgress: progress)
            delegate?.segmentedController(scrollOffsetChangedTo: progress)
        }
        let navAlpha = scrollPositionAlpha(for: progress)
        separator.alpha = navAlpha
        blurView.alpha = navAlpha
    }
    
    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        delegate?.segmentedControllerDidStartDragging()
    }
    
    public func scrollViewWillEndDragging(_ scrollView: UIScrollView,
                                          withVelocity velocity: CGPoint,
                                          targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        // sometimes, default pagination behavior skips pages (0 -> 1 -> 3 ?!)
        if (targetContentOffset.pointee.x - scrollView.contentOffset.x) > scrollView.frame.width {
            targetContentOffset.pointee.x -= scrollView.frame.width
        } else if (targetContentOffset.pointee.x - scrollView.contentOffset.x) < -scrollView.frame.width {
            targetContentOffset.pointee.x += scrollView.frame.width
        }
    }

    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            delegate?.segmentedControllerDidEndScrolling()
        }
    }

    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        delegate?.segmentedControllerDidEndScrolling()
    }
}

private extension WSegmentedController {
    func updateSegmentedControlProgress(pageProgress: CGFloat) {
        guard !model.items.isEmpty else { return }
        let visibleProgress = clamp(
            pageProgress - CGFloat(segmentedItemPageOffset),
            min: 0,
            max: CGFloat(model.items.count - 1)
        )
        segmentedControl.model.setRawProgress(visibleProgress)
    }
}
