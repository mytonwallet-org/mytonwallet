import ContextMenuKit
import SwiftUI
import UIKit
import WalletContext

@MainActor
public final class WSegmentedPagerView: WTouchPassView, UIScrollViewDelegate {
    private enum Layout {
        static let barHeight: CGFloat = 44
        static let segmentedControlHeight: CGFloat = 24
        static let segmentedControlTopInset: CGFloat = 9
        static let segmentedControlFullHeight: CGFloat = segmentedControlHeight + segmentedControlTopInset
    }

    private enum TransitionDirection {
        case reverse
        case forward

        var step: Int {
            switch self {
            case .reverse: -1
            case .forward: 1
            }
        }
    }

    private struct ProgrammaticTransition {
        let sourceIndex: Int
        let targetIndex: Int
        let bridgeOffsetX: CGFloat?
        let animatedOffsetX: CGFloat
    }

    public let model: SegmentedControlModel
    public let segmentedControl: WSegmentedControl

    private let scrollView = UIScrollView()
    private let transitionPageView = UIView()

    private var items: [WSegmentedPagerItem]
    private var currentIndex: Int = 0
    private var pageContainers: [Int: UIView] = [:]
    private var transitionContent: (any WSegmentedControllerContent)?
    private var isInteractiveTransitionActive = false
    private var interactiveDirection: TransitionDirection?
    private var lastViewportProgress: CGFloat = 0
    private var pendingProgrammaticTransition: ProgrammaticTransition?

    public var onScrollProgressChanged: ((CGFloat) -> Void)?
    public var onWillStartTransition: (() -> Void)?
    public var onDidStartDragging: (() -> Void)?
    public var onDidEndScrolling: (() -> Void)?

    public init(items: [WSegmentedPagerItem], onScrollProgressChanged: ((CGFloat) -> Void)? = nil) {
        self.items = items
        self.model = SegmentedControlModel(items: items.map(\.segmentedControlItem))
        self.segmentedControl = WSegmentedControl(model: model)
        self.onScrollProgressChanged = onScrollProgressChanged

        super.init(frame: .zero)
        if let first = items.first {
            model.selection = .init(item1: first.id)
        }
        setupModel()
        setupViews()
        syncVisiblePages(around: 0)
        reportSettledProgress()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { nil }

    public var viewControllers: [WSegmentedControllerContent] {
        items.map(\.viewController)
    }

    public var selectedIndex: Int? {
        items.indices.contains(currentIndex) ? currentIndex : nil
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        updateScrollLayout()
    }

    private func updateScrollLayout() {
        let viewportSize = scrollView.bounds.size
        guard viewportSize.width > 0 else { return }

        scrollView.contentSize = CGSize(width: viewportSize.width * CGFloat(max(items.count, 1)), height: viewportSize.height)

        if pendingProgrammaticTransition == nil, !scrollView.isDragging, !scrollView.isDecelerating {
            scrollView.contentOffset = realContentOffset(for: currentIndex)
        }

        layoutPageContainers()
        layoutTransitionPageView()
        syncVisiblePages(around: currentViewportProgress())
    }

    public func replace(items: [WSegmentedPagerItem], force: Bool = false) {
        let oldItems = self.items
        let oldSelectedId = effectiveSelectedItemID
        let oldViewControllers = oldItems.map(\.viewController)
        let newViewControllers = items.map(\.viewController)

        if items == oldItems
            && zip(newViewControllers, oldViewControllers).allSatisfy({
                ObjectIdentifier($0 as AnyObject) == ObjectIdentifier($1 as AnyObject)
            })
            && !force {
            return
        }

        clearTransientState()

        self.items = items
        model.setItems(items.map(\.segmentedControlItem))
        if items.isEmpty {
            model.selection = nil
        }

        if let oldSelectedId {
            currentIndex = items.firstIndex(where: { $0.id == oldSelectedId }) ?? 0
        } else {
            currentIndex = 0
        }
        syncSettledState(at: clampedIndex(currentIndex), updateLayout: true)
    }

    public func handleSegmentChange(to index: Int, animated: Bool) {
        guard items.indices.contains(index) else { return }
        guard scrollView.bounds.width > 0 else {
            selectIndex(index)
            onDidEndScrolling?()
            return
        }
        guard index != currentIndex else {
            reportSettledProgress()
            onDidEndScrolling?()
            return
        }

        onWillStartTransition?()

        stopProgrammaticScrollIfNeeded()
        settleInteractiveScrollIfNeeded()

        if !animated {
            selectIndex(index)
            onDidEndScrolling?()
            return
        }

        withAnimation(.spring(duration: 0.25)) {
            model.setRawProgress(CGFloat(index))
        }
        reportScrollProgress(CGFloat(index))
        startProgrammaticTransition(to: index)
    }

    public func scrollToTop(animated: Bool) {
        guard items.indices.contains(currentIndex) else { return }
        items[currentIndex].viewController.scrollToTop(animated: animated)
    }

    private func setupModel() {
        model.primaryColor = UIColor.label
        model.secondaryColor = .air.secondaryLabel
        model.capsuleColor = .air.thumbBackground
        model.onSelect = { [weak self] item in
            guard let self, let index = self.model.getItemIndexById(itemId: item.id) else { return }
            self.handleSegmentChange(to: index, animated: true)
        }
    }

    private func setupViews() {
        translatesAutoresizingMaskIntoConstraints = false

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.isPagingEnabled = true
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = true
        scrollView.isDirectionalLockEnabled = true
        scrollView.decelerationRate = .fast
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.alwaysBounceVertical = false
        if #available(iOS 17.4, *) {
            scrollView.bouncesVertically = false
        }
        if #available(iOS 26.0, *) {
            scrollView.topEdgeEffect.isHidden = true
        }
        scrollView.delegate = self
        addSubview(scrollView)

        transitionPageView.backgroundColor = .clear
        transitionPageView.clipsToBounds = true
        transitionPageView.isHidden = true
        scrollView.addSubview(transitionPageView)

        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        addSubview(segmentedControl)

        NSLayoutConstraint.activate([
            segmentedControl.centerXAnchor.constraint(equalTo: centerXAnchor),
            segmentedControl.topAnchor.constraint(
                equalTo: topAnchor,
                constant: (Layout.barHeight - Layout.segmentedControlHeight) / 2.0 + 3.0 - Layout.segmentedControlTopInset
            ),
            segmentedControl.heightAnchor.constraint(equalToConstant: Layout.segmentedControlFullHeight),
            segmentedControl.widthAnchor.constraint(equalTo: widthAnchor),

            scrollView.topAnchor.constraint(equalTo: topAnchor, constant: Layout.barHeight),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private var effectiveSelectedItemID: String? {
        guard let selection = model.selection else { return nil }
        if let item2 = selection.item2, let progress = selection.progress, progress > 0.5 {
            return item2
        }
        return selection.item1
    }

    private func selectIndex(_ index: Int) {
        guard items.indices.contains(index) else {
            model.selection = nil
            reportScrollProgress(0)
            return
        }

        clearTransientState()
        syncSettledState(at: index, updateLayout: true)
    }

    private func reportSettledProgress() {
        guard items.indices.contains(currentIndex) else {
            reportScrollProgress(0)
            return
        }
        if items.count >= 2 {
            model.setRawProgress(CGFloat(currentIndex))
        } else {
            model.selection = .init(item1: items[currentIndex].id)
        }
        reportScrollProgress(CGFloat(currentIndex))
    }

    private func reportScrollProgress(_ progress: CGFloat) {
        onScrollProgressChanged?(progress)
    }

    private func clampedIndex(_ index: Int) -> Int {
        max(0, min(max(items.count - 1, 0), index))
    }

    private func clearTransitionPageView() {
        transitionContent = nil
        host(nil, in: transitionPageView)
        transitionPageView.isHidden = true
    }

    private func clearTransientState() {
        pendingProgrammaticTransition = nil
        isInteractiveTransitionActive = false
        interactiveDirection = nil
        clearTransitionPageView()
    }

    private func updateSettledIndex(_ index: Int) {
        currentIndex = index
        lastViewportProgress = CGFloat(index)
    }

    private func syncSettledState(at index: Int, updateLayout: Bool = false) {
        updateSettledIndex(index)
        if updateLayout {
            updateScrollLayout()
        }
        syncVisiblePages(around: CGFloat(index))
        reportSettledProgress()
    }

    private func startProgrammaticTransition(to targetIndex: Int) {
        let width = scrollView.bounds.width
        guard width > 0 else {
            selectIndex(targetIndex)
            return
        }

        let realOffsetX = CGFloat(targetIndex) * width
        if abs(targetIndex - currentIndex) == 1 {
            pendingProgrammaticTransition = .init(
                sourceIndex: currentIndex,
                targetIndex: targetIndex,
                bridgeOffsetX: nil,
                animatedOffsetX: realOffsetX,
            )
            scrollView.setContentOffset(CGPoint(x: realOffsetX, y: 0), animated: true)
            return
        }

        let direction: TransitionDirection = targetIndex > currentIndex ? .forward : .reverse
        let sourceIndex = currentIndex
        let bridgeIndex = sourceIndex + direction.step
        let bridgeOffsetX = CGFloat(bridgeIndex) * width

        pendingProgrammaticTransition = .init(
            sourceIndex: sourceIndex,
            targetIndex: targetIndex,
            bridgeOffsetX: bridgeOffsetX,
            animatedOffsetX: realOffsetX
        )
        transitionContent = viewController(at: sourceIndex)
        host(transitionContent, in: transitionPageView)
        layoutTransitionPageView()
        syncVisiblePages(around: CGFloat(bridgeIndex))
        scrollView.setContentOffset(CGPoint(x: bridgeOffsetX, y: 0), animated: false)
        scrollView.setContentOffset(CGPoint(x: realOffsetX, y: 0), animated: true)
    }

    private func visiblePageIndices(around progress: CGFloat) -> [Int] {
        guard !items.isEmpty else { return [] }

        if let pendingProgrammaticTransition {
            let indices = if pendingProgrammaticTransition.bridgeOffsetX != nil {
                [pendingProgrammaticTransition.targetIndex]
            } else {
                [pendingProgrammaticTransition.sourceIndex, pendingProgrammaticTransition.targetIndex]
            }
            return Array(Set(indices)).sorted()
        }

        if isInteractiveTransitionActive {
            return interactiveVisiblePageIndices(around: progress)
        }

        let settledIndex = nearestIndex(for: progress)
        return [settledIndex]
    }

    private func syncVisiblePages(around progress: CGFloat) {
        let neededIndices = Set(visiblePageIndices(around: progress))
        let obsoleteIndices = pageContainers.keys.filter { !neededIndices.contains($0) }
        for index in obsoleteIndices {
            guard let container = pageContainers.removeValue(forKey: index) else { continue }
            host(nil, in: container)
            container.removeFromSuperview()
        }

        for index in neededIndices.sorted() {
            let container = pageContainers[index] ?? makePageContainer(for: index)
            container.frame = frame(for: index)
            host(viewController(at: index), in: container)
        }

        layoutPageContainers()
        if !transitionPageView.isHidden {
            scrollView.bringSubviewToFront(transitionPageView)
        }
    }

    private func makePageContainer(for index: Int) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear
        container.clipsToBounds = true
        container.frame = frame(for: index)
        scrollView.addSubview(container)
        pageContainers[index] = container
        return container
    }

    private func frame(for index: Int) -> CGRect {
        CGRect(
            x: CGFloat(index) * scrollView.bounds.width,
            y: 0,
            width: scrollView.bounds.width,
            height: scrollView.bounds.height
        )
    }

    private func layoutPageContainers() {
        for (index, container) in pageContainers {
            let targetFrame = frame(for: index)
            if container.frame != targetFrame {
                container.frame = targetFrame
            }
            if let content = viewController(at: index), content.view.superview === container {
                layoutHostedView(content, in: container)
            }
        }
    }

    private func layoutTransitionPageView() {
        guard let pendingProgrammaticTransition else {
            transitionPageView.isHidden = true
            return
        }
        guard let bridgeOffsetX = pendingProgrammaticTransition.bridgeOffsetX else {
            transitionPageView.isHidden = true
            return
        }

        transitionPageView.isHidden = false
        transitionPageView.frame = CGRect(
            x: bridgeOffsetX,
            y: 0,
            width: scrollView.bounds.width,
            height: scrollView.bounds.height
        )
        if let transitionContent, transitionContent.view.superview === transitionPageView {
            layoutHostedView(transitionContent, in: transitionPageView)
        }
        scrollView.bringSubviewToFront(transitionPageView)
    }

    private func viewController(at index: Int?) -> (any WSegmentedControllerContent)? {
        guard let index, items.indices.contains(index) else { return nil }
        return items[index].viewController
    }

    private func layoutHostedView(_ viewController: any WSegmentedControllerContent, in container: UIView) {
        let hostedView = viewController.view!
        let width = container.bounds.width
        guard width > 0 else { return }

        if hostedView.bounds.width != width {
            hostedView.frame = CGRect(
                x: 0,
                y: 0,
                width: width,
                height: max(hostedView.bounds.height, 1)
            )
            hostedView.setNeedsLayout()
            hostedView.layoutIfNeeded()
        }

        let targetFrame = CGRect(
            x: 0,
            y: 0,
            width: width,
            height: max(1, viewController.calculateHeight(isHosted: true))
        )
        if hostedView.frame != targetFrame {
            hostedView.frame = targetFrame
            hostedView.setNeedsLayout()
            hostedView.layoutIfNeeded()
        }
    }

    private func interactiveVisiblePageIndices(around progress: CGFloat) -> [Int] {
        guard !items.isEmpty else { return [] }

        let lowerIndex = max(0, min(items.count - 1, Int(floor(progress))))
        let upperIndex = max(0, min(items.count - 1, Int(ceil(progress))))
        var result = Set([lowerIndex, upperIndex])

        if let interactiveDirection {
            switch interactiveDirection {
            case .reverse:
                if lowerIndex > 0 {
                    result.insert(lowerIndex - 1)
                }
            case .forward:
                if upperIndex + 1 < items.count {
                    result.insert(upperIndex + 1)
                }
            }
        } else {
            let nearestIndex = nearestIndex(for: progress)
            if nearestIndex > 0 {
                result.insert(nearestIndex - 1)
            }
            if nearestIndex + 1 < items.count {
                result.insert(nearestIndex + 1)
            }
        }

        return result.sorted()
    }

    private func updateInteractiveDirection(for progress: CGFloat) {
        let delta = progress - lastViewportProgress
        if delta > 0.001 {
            interactiveDirection = .forward
        } else if delta < -0.001 {
            interactiveDirection = .reverse
        }
        lastViewportProgress = progress
    }

    private func host(_ viewController: (any WSegmentedControllerContent)?, in container: UIView) {
        if let viewController, viewController.view.superview === container {
            layoutHostedView(viewController, in: container)
            container.isHidden = false
            return
        }

        container.subviews.forEach { $0.removeFromSuperview() }
        container.isHidden = viewController == nil

        guard let viewController else { return }

        let hostedView = viewController.view!
        hostedView.removeFromSuperview()
        hostedView.autoresizingMask = [.flexibleWidth]
        container.addSubview(hostedView)
        layoutHostedView(viewController, in: container)
    }

    private func realContentOffset(for index: Int) -> CGPoint {
        CGPoint(x: CGFloat(index) * scrollView.bounds.width, y: 0)
    }

    private func currentViewportProgress() -> CGFloat {
        guard scrollView.bounds.width > 0, !items.isEmpty else { return CGFloat(currentIndex) }
        return clamp(scrollView.contentOffset.x / scrollView.bounds.width, min: 0, max: CGFloat(items.count - 1))
    }

    private func nearestIndex(for progress: CGFloat) -> Int {
        guard !items.isEmpty else { return 0 }
        return max(0, min(items.count - 1, Int(round(progress))))
    }

    private func applyCurrentScrollProgress(_ progress: CGFloat) {
        if items.count >= 2 {
            model.setRawProgress(progress)
        } else if let first = items.first {
            model.selection = .init(item1: first.id)
        }
        reportScrollProgress(progress)
    }

    private func stopProgrammaticScrollIfNeeded() {
        guard let pendingProgrammaticTransition else { return }

        scrollView.setContentOffset(scrollView.contentOffset, animated: false)

        let shouldFinishToTarget: Bool
        if let bridgeOffsetX = pendingProgrammaticTransition.bridgeOffsetX {
            let bridgeDistance = abs(scrollView.contentOffset.x - bridgeOffsetX)
            let targetDistance = abs(scrollView.contentOffset.x - pendingProgrammaticTransition.animatedOffsetX)
            shouldFinishToTarget = targetDistance < bridgeDistance
        } else {
            let currentDistance = abs(scrollView.contentOffset.x - realContentOffset(for: pendingProgrammaticTransition.sourceIndex).x)
            let targetDistance = abs(scrollView.contentOffset.x - pendingProgrammaticTransition.animatedOffsetX)
            shouldFinishToTarget = targetDistance < currentDistance
        }

        clearTransientState()

        if shouldFinishToTarget {
            scrollView.contentOffset = realContentOffset(for: pendingProgrammaticTransition.targetIndex)
            syncSettledState(at: pendingProgrammaticTransition.targetIndex)
        } else {
            scrollView.contentOffset = realContentOffset(for: pendingProgrammaticTransition.sourceIndex)
            syncSettledState(at: pendingProgrammaticTransition.sourceIndex)
        }
    }

    private func settleInteractiveScrollIfNeeded() {
        guard scrollView.isDragging || scrollView.isDecelerating else { return }

        scrollView.setContentOffset(scrollView.contentOffset, animated: false)
        clearTransientState()
        syncSettledState(at: nearestIndex(for: currentViewportProgress()))
    }

    private func finishInteractiveTransition() {
        clearTransientState()
        syncSettledState(at: nearestIndex(for: currentViewportProgress()))
        onDidEndScrolling?()
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let progress = currentViewportProgress()
        if isInteractiveTransitionActive {
            updateInteractiveDirection(for: progress)
        }
        syncVisiblePages(around: progress)
        guard scrollView.isDragging || scrollView.isDecelerating else { return }
        applyCurrentScrollProgress(progress)
    }

    public func scrollViewWillBeginDragging(_: UIScrollView) {
        stopProgrammaticScrollIfNeeded()
        isInteractiveTransitionActive = true
        interactiveDirection = nil
        lastViewportProgress = currentViewportProgress()
        syncVisiblePages(around: lastViewportProgress)
        onDidStartDragging?()
    }

    public func scrollViewWillEndDragging(_ scrollView: UIScrollView,
                                          withVelocity _: CGPoint,
                                          targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        guard scrollView.bounds.width > 0 else { return }

        let width = scrollView.bounds.width
        let delta = targetContentOffset.pointee.x - scrollView.contentOffset.x
        if delta > width {
            targetContentOffset.pointee.x = scrollView.contentOffset.x + width
        } else if delta < -width {
            targetContentOffset.pointee.x = scrollView.contentOffset.x - width
        }

        let maxOffsetX = max(0, scrollView.contentSize.width - width)
        let clampedOffsetX = max(0, min(maxOffsetX, targetContentOffset.pointee.x))
        targetContentOffset.pointee.x = round(clampedOffsetX / width) * width
    }

    public func scrollViewDidEndDragging(_: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            finishInteractiveTransition()
        }
    }

    public func scrollViewDidEndDecelerating(_: UIScrollView) {
        finishInteractiveTransition()
    }

    public func scrollViewDidEndScrollingAnimation(_: UIScrollView) {
        guard let pendingProgrammaticTransition else { return }

        clearTransientState()
        syncSettledState(at: pendingProgrammaticTransition.targetIndex)
        onDidEndScrolling?()
    }
}

@MainActor
public struct WSegmentedPagerItem: Equatable {
    public let id: String
    public let title: String
    public let contextMenuProvider: SegmentedControlContextMenuProvider?
    public let hidesMenuIcon: Bool
    public let isDeletable: Bool
    public let viewController: any WSegmentedControllerContent

    public init(
        id: String,
        title: String,
        contextMenuProvider: SegmentedControlContextMenuProvider? = nil,
        hidesMenuIcon: Bool = false,
        isDeletable: Bool = true,
        viewController: any WSegmentedControllerContent
    ) {
        self.id = id
        self.title = title
        self.contextMenuProvider = contextMenuProvider
        self.hidesMenuIcon = hidesMenuIcon
        self.isDeletable = isDeletable
        self.viewController = viewController
    }

    var segmentedControlItem: SegmentedControlItem {
        SegmentedControlItem(
            id: id,
            title: title,
            contextMenuProvider: contextMenuProvider,
            hidesMenuIcon: hidesMenuIcon,
            isDeletable: isDeletable,
            viewController: viewController
        )
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.contextMenuProvider === rhs.contextMenuProvider
            && lhs.hidesMenuIcon == rhs.hidesMenuIcon
            && lhs.isDeletable == rhs.isDeletable
            && ObjectIdentifier(lhs.viewController as AnyObject) == ObjectIdentifier(rhs.viewController as AnyObject)
    }
}
