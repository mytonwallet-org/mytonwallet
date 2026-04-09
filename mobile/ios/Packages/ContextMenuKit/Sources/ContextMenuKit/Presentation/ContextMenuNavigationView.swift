import UIKit

@MainActor
protocol ContextMenuNavigationViewDelegate: AnyObject {
    func navigationView(_ navigationView: ContextMenuNavigationView, didActivate action: ContextMenuActivation)
}

@MainActor
final class ContextMenuNavigationView: UIView, ContextMenuPageViewDelegate, UIGestureRecognizerDelegate {
    private struct PageHost {
        let page: ContextMenuPage
        let pageView: ContextMenuPageView
    }

    private let style: ContextMenuStyle
    private let customRowContext: ContextMenuCustomRowContext
    private let panelView: ContextMenuPanelView
    private let pageClipView = UIView()
    private let navigationPanRecognizer: ContextMenuInteractivePanGestureRecognizer

    private var hosts: [PageHost] = []
    private var transitionProgress: CGFloat = 0.0
    private var constrainedPanelSize: CGSize = .zero
    private var animator: UIViewPropertyAnimator?

    weak var delegate: ContextMenuNavigationViewDelegate?
    var requestLayout: (() -> Void)?

    var isShowingSubmenu: Bool {
        self.hosts.count > 1
    }

    init(rootPage: ContextMenuPage, style: ContextMenuStyle, customRowContext: ContextMenuCustomRowContext) {
        self.style = style
        self.customRowContext = customRowContext
        self.panelView = ContextMenuPanelView(style: style)
        self.navigationPanRecognizer = ContextMenuInteractivePanGestureRecognizer(target: nil, action: nil, allowedDirections: { _ in
            [.right]
        })

        super.init(frame: .zero)

        self.addSubview(self.panelView)
        self.panelView.contentView.addSubview(self.pageClipView)
        self.pageClipView.clipsToBounds = true

        self.navigationPanRecognizer.addTarget(self, action: #selector(self.handleNavigationPan(_:)))
        self.navigationPanRecognizer.delegate = self
        self.addGestureRecognizer(self.navigationPanRecognizer)

        self.pushRootPage(rootPage)
        self.updateNavigationGestureState()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if previousTraitCollection?.userInterfaceStyle != self.traitCollection.userInterfaceStyle {
            self.requestLayout?()
        }
    }

    func preferredPanelSize(constrainedTo size: CGSize) -> CGSize {
        self.constrainedPanelSize = size

        guard let current = self.hosts.last else {
            return .zero
        }

        let currentSize = current.pageView.preferredSize(constrainedTo: size)
        guard self.hosts.count > 1 else {
            return currentSize
        }

        let previous = self.hosts[self.hosts.count - 2]
        let previousSize = previous.pageView.preferredSize(constrainedTo: size)
        return CGSize(
            width: previousSize.width * self.transitionProgress + currentSize.width * (1.0 - self.transitionProgress),
            height: previousSize.height * self.transitionProgress + currentSize.height * (1.0 - self.transitionProgress)
        )
    }

    func applyPanelLayout(panelSize: CGSize) {
        let containerSize = CGSize(
            width: panelSize.width + self.style.panelInset * 2.0,
            height: panelSize.height + self.style.panelInset * 2.0
        )
        self.panelView.frame = CGRect(origin: .zero, size: containerSize)
        self.panelView.applyLayout(panelSize: panelSize, traits: self.traitCollection)
        self.pageClipView.frame = self.panelView.contentView.bounds

        guard let currentHost = self.hosts.last else {
            return
        }

        let currentSize = currentHost.pageView.preferredSize(constrainedTo: self.constrainedPanelSize)
        let previousSize = self.hosts.count > 1
            ? self.hosts[self.hosts.count - 2].pageView.preferredSize(constrainedTo: self.constrainedPanelSize)
            : nil

        for (index, host) in self.hosts.enumerated() {
            let isCurrent = index == self.hosts.count - 1
            let isPrevious = index == self.hosts.count - 2
            host.pageView.isHidden = !(isCurrent || isPrevious)

            guard !host.pageView.isHidden else {
                host.pageView.restoreVisualState()
                continue
            }

            if isCurrent {
                host.pageView.allowsBackNavigationGesture = self.hosts.count > 1
                let width = currentSize.width
                let frame = CGRect(
                    x: (previousSize?.width ?? width) * self.transitionProgress,
                    y: 0.0,
                    width: width,
                    height: panelSize.height
                )
                host.pageView.frame = frame
                host.pageView.applyLayout(size: CGSize(width: width, height: panelSize.height))
                host.pageView.alpha = 1.0
            } else if isPrevious, let previousSize {
                host.pageView.allowsBackNavigationGesture = false
                let frame = CGRect(
                    x: -previousSize.width * (1.0 - self.transitionProgress),
                    y: 0.0,
                    width: previousSize.width,
                    height: panelSize.height
                )
                host.pageView.frame = frame
                host.pageView.applyLayout(size: CGSize(width: previousSize.width, height: panelSize.height))
                host.pageView.alpha = 0.72 + self.transitionProgress * 0.28
            }
        }
    }

    func beginExternalSelection(at windowPoint: CGPoint) {
        self.hosts.last?.pageView.beginExternalSelection(windowPoint: windowPoint)
    }

    func updateExternalSelection(at windowPoint: CGPoint) {
        self.hosts.last?.pageView.updateExternalSelection(windowPoint: windowPoint)
    }

    func endExternalSelection(performAction: Bool) {
        self.hosts.last?.pageView.endExternalSelection(performAction: performAction)
    }

    func clearSelections() {
        self.hosts.forEach { $0.pageView.restoreVisualState() }
    }

    func popToPreviousPageIfNeeded() {
        guard self.hosts.count > 1 else {
            return
        }
        self.animatePopCompletion()
    }

    func pageView(_ pageView: ContextMenuPageView, didActivate action: ContextMenuPageAction) {
        switch action {
        case let .trigger(action):
            self.delegate?.navigationView(self, didActivate: action)
        case .back:
            self.popToPreviousPageIfNeeded()
        case let .submenu(page):
            self.push(page: page)
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if otherGestureRecognizer === self.navigationPanRecognizer {
            return false
        }
        return otherGestureRecognizer is UIPanGestureRecognizer
    }

    @objc private func handleNavigationPan(_ recognizer: UIPanGestureRecognizer) {
        guard self.hosts.count > 1 else {
            return
        }

        let currentWidth = max(self.hosts.last?.pageView.bounds.width ?? 1.0, 1.0)
        switch recognizer.state {
        case .began, .changed:
            self.animator?.stopAnimation(true)
            self.animator = nil

            let translation = max(0.0, recognizer.translation(in: self).x)
            self.transitionProgress = min(1.0, translation / currentWidth)
            self.requestLayout?()
        case .ended, .cancelled:
            let translation = max(0.0, recognizer.translation(in: self).x)
            let velocity = recognizer.velocity(in: self).x
            let completionProgress = min(1.0, translation / currentWidth)
            if completionProgress > 0.2 || velocity > 520.0 {
                self.animatePopCompletion()
            } else {
                self.animateCancelPop()
            }
        default:
            break
        }
    }

    private func pushRootPage(_ rootPage: ContextMenuPage) {
        let pageView = ContextMenuPageView(page: rootPage, style: self.style, customRowContext: self.customRowContext)
        pageView.delegate = self
        self.pageClipView.addSubview(pageView)
        self.hosts = [PageHost(page: rootPage, pageView: pageView)]
    }

    private func push(page: ContextMenuPage) {
        self.animator?.stopAnimation(true)
        self.animator = nil
        self.clearSelections()

        let pageView = ContextMenuPageView(page: page, style: self.style, customRowContext: self.customRowContext)
        pageView.delegate = self
        self.pageClipView.addSubview(pageView)
        self.hosts.append(PageHost(page: page, pageView: pageView))
        self.transitionProgress = 1.0
        self.updateNavigationGestureState()
        self.requestLayout?()

        let animator = UIViewPropertyAnimator(duration: 0.45, dampingRatio: 0.82) {
            self.transitionProgress = 0.0
            self.requestLayout?()
        }
        animator.addCompletion { _ in
            self.animator = nil
        }
        self.animator = animator
        animator.startAnimation()
    }

    private func animatePopCompletion() {
        self.animator?.stopAnimation(true)
        self.animator = nil
        self.clearSelections()

        let animator = UIViewPropertyAnimator(duration: 0.45, dampingRatio: 0.82) {
            self.transitionProgress = 1.0
            self.requestLayout?()
        }
        animator.addCompletion { _ in
            guard self.hosts.count > 1 else {
                self.transitionProgress = 0.0
                self.requestLayout?()
                self.animator = nil
                self.updateNavigationGestureState()
                return
            }

            let removed = self.hosts.removeLast()
            removed.pageView.removeFromSuperview()
            self.transitionProgress = 0.0
            self.updateNavigationGestureState()
            self.requestLayout?()
            self.animator = nil
        }
        self.animator = animator
        animator.startAnimation()
    }

    private func animateCancelPop() {
        self.animator?.stopAnimation(true)
        self.animator = nil

        let animator = UIViewPropertyAnimator(duration: 0.35, dampingRatio: 0.86) {
            self.transitionProgress = 0.0
            self.requestLayout?()
        }
        animator.addCompletion { _ in
            self.animator = nil
        }
        self.animator = animator
        animator.startAnimation()
    }

    private func updateNavigationGestureState() {
        self.navigationPanRecognizer.isEnabled = self.hosts.count > 1
    }
}
