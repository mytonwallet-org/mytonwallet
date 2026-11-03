import UIKit
import WalletContext

public final class StoriesViewController: UIViewController, UIGestureRecognizerDelegate, UIScrollViewDelegate, UIViewControllerTransitioningDelegate {
    public static var defaultBackgroundColors: [UIColor] {
        [UIColor(red: 0, green: 0.718, blue: 1, alpha: 1),
         UIColor(red: 0.039, green: 0.447, blue: 0.957, alpha: 1),
         UIColor(red: 0, green: 0.408, blue: 0.933, alpha: 1)]
    }

    public let pages: [StoryPage]
    public var presentationSource: StoriesPresentationSource?
    private let backgroundView: UIView?
    private let backgroundColors: [UIColor]
    private let onCompletion: (() -> Void)?
    private(set) var playback: StoryPlaybackState
    private let gradient = CAGradientLayer()
    private let mediaContainer = UIView()
    private var media: StoryMediaView?
    private var mediaAnimator: UIViewPropertyAnimator?
    private let progressView: StoryProgressView
    private let contentBlock = UIView()
    private let copyScrollView = UIScrollView()
    private let copyStack = UIStackView()
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let nextButton = WInteractiveGlassButton(style: .secondary)
    private let closeButton = WInteractiveGlassButton(style: .secondary)
    private var blockHeight: NSLayoutConstraint!
    private var displayLink: CADisplayLink?
    private var previousTimestamp: CFTimeInterval?
    private var dragReturnAnimator: UIViewPropertyAnimator?
    private(set) var dismissalVelocity: CGFloat = 0
    private(set) var dismissalCornerRadius: CGFloat = 0
    private var isDragging = false
    private let contentSafeArea = UILayoutGuide()
    private var safeAreaConstraints: [NSLayoutConstraint] = []
    private var completionDelivered = false
    private var isClosing = false

    public init(pages: [StoryPage], backgroundView: UIView? = nil,
                backgroundColors: [UIColor] = StoriesViewController.defaultBackgroundColors,
                onCompletion: (() -> Void)? = nil) {
        self.pages = pages
        self.backgroundView = backgroundView
        self.backgroundColors = backgroundColors.isEmpty ? Self.defaultBackgroundColors : backgroundColors
        self.onCompletion = onCompletion
        playback = StoryPlaybackState(pages: pages)
        progressView = StoryProgressView(count: pages.count)
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .custom
        modalPresentationCapturesStatusBarAppearance = true
        transitioningDelegate = self
        overrideUserInterfaceStyle = .light
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }

    public override func loadView() {
        let root = StoriesRootView()
        root.onAccessibilityScroll = { [weak self] direction in
            guard let self else { return false }
            switch direction {
            case .left, .right:
                let forward = (direction == .left) != (view.effectiveUserInterfaceLayoutDirection == .rightToLeft)
                navigate(forward: forward)
                return true
            default: return false
            }
        }
        root.onAccessibilityEscape = { [weak self] in self?.close(); return true }
        view = root
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.accessibilityViewIsModal = true
        view.backgroundColor = backgroundColors.last
        gradient.colors = backgroundColors.map(\.cgColor)
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        view.layer.addSublayer(gradient)
        if let backgroundView {
            backgroundView.isUserInteractionEnabled = false
            backgroundView.accessibilityElementsHidden = true
            view.addSubview(backgroundView)
        }
        mediaContainer.isUserInteractionEnabled = false
        view.addSubview(mediaContainer)

        for child in [progressView, contentBlock, closeButton] {
            child.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(child)
        }
        closeButton.accessibilityLabel = lang("Close")
        closeButton.accessibilityIdentifier = "Stories.Close"
        progressView.accessibilityIdentifier = "Stories.Progress"
        contentBlock.accessibilityIdentifier = "Stories.Content"
        nextButton.accessibilityIdentifier = "Stories.Next"
        titleLabel.accessibilityIdentifier = "Stories.Title"
        bodyLabel.accessibilityIdentifier = "Stories.Body"

        copyScrollView.translatesAutoresizingMaskIntoConstraints = false
        copyScrollView.showsVerticalScrollIndicator = false
        copyScrollView.alwaysBounceVertical = false
        copyScrollView.contentInsetAdjustmentBehavior = .never
        copyScrollView.delegate = self
        copyScrollView.panGestureRecognizer.addTarget(self, action: #selector(copyScrollPanned(_:)))
        contentBlock.addSubview(copyScrollView)
        copyStack.axis = .vertical
        copyStack.spacing = 12
        copyStack.translatesAutoresizingMaskIntoConstraints = false
        copyScrollView.addSubview(copyStack)
        for label in [titleLabel, bodyLabel] {
            label.numberOfLines = 0
            label.textColor = .white
            copyStack.addArrangedSubview(label)
        }
        titleLabel.accessibilityTraits.insert(.header)
        titleLabel.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: lang("Previous"), target: self, selector: #selector(accessibilityPrevious)),
            UIAccessibilityCustomAction(name: lang("Next"), target: self, selector: #selector(accessibilityNext)),
        ]
        nextButton.translatesAutoresizingMaskIntoConstraints = false
        nextButton.customTintColor = .black
        nextButton.customTitleFont = WTypography.uiFont(.capsuleButton)
        nextButton.configureInteractiveGlass(tintColor: .white.withAlphaComponent(0.5), foregroundColor: .black)
        closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .medium)), for: .normal)
        closeButton.configureInteractiveGlass(tintColor: .white.withAlphaComponent(0.17), foregroundColor: .white)
        closeButton.addAction(UIAction { [weak self] _ in self?.close() }, for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(nextPressed), for: .touchUpInside)
        contentBlock.addSubview(nextButton)

        view.addLayoutGuide(contentSafeArea)
        safeAreaConstraints = [
            contentSafeArea.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentSafeArea.topAnchor.constraint(equalTo: view.topAnchor),
            contentSafeArea.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentSafeArea.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ]
        NSLayoutConstraint.activate(safeAreaConstraints)
        blockHeight = contentBlock.heightAnchor.constraint(equalToConstant: 233)
        NSLayoutConstraint.activate([
            progressView.leadingAnchor.constraint(equalTo: contentSafeArea.leadingAnchor, constant: 24),
            progressView.trailingAnchor.constraint(equalTo: contentSafeArea.trailingAnchor, constant: -24),
            progressView.topAnchor.constraint(equalTo: contentSafeArea.topAnchor, constant: 4),
            progressView.heightAnchor.constraint(equalToConstant: 3),
            closeButton.trailingAnchor.constraint(equalTo: contentSafeArea.trailingAnchor, constant: -24),
            closeButton.topAnchor.constraint(equalTo: contentSafeArea.topAnchor, constant: 23),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),
            contentBlock.leadingAnchor.constraint(equalTo: contentSafeArea.leadingAnchor, constant: 24),
            contentBlock.trailingAnchor.constraint(equalTo: contentSafeArea.trailingAnchor, constant: -24),
            contentBlock.bottomAnchor.constraint(equalTo: contentSafeArea.bottomAnchor, constant: -6),
            blockHeight,
            nextButton.leadingAnchor.constraint(equalTo: contentBlock.leadingAnchor),
            nextButton.trailingAnchor.constraint(equalTo: contentBlock.trailingAnchor),
            nextButton.bottomAnchor.constraint(equalTo: contentBlock.bottomAnchor),
            nextButton.heightAnchor.constraint(equalToConstant: 52),
            copyScrollView.leadingAnchor.constraint(equalTo: contentBlock.leadingAnchor),
            copyScrollView.trailingAnchor.constraint(equalTo: contentBlock.trailingAnchor),
            copyScrollView.topAnchor.constraint(equalTo: contentBlock.topAnchor),
            copyScrollView.bottomAnchor.constraint(equalTo: contentBlock.bottomAnchor, constant: -76),
            copyStack.leadingAnchor.constraint(equalTo: copyScrollView.contentLayoutGuide.leadingAnchor),
            copyStack.trailingAnchor.constraint(equalTo: copyScrollView.contentLayoutGuide.trailingAnchor),
            copyStack.topAnchor.constraint(equalTo: copyScrollView.contentLayoutGuide.topAnchor),
            copyStack.bottomAnchor.constraint(equalTo: copyScrollView.contentLayoutGuide.bottomAnchor),
            copyStack.widthAnchor.constraint(equalTo: copyScrollView.frameLayoutGuide.widthAnchor),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
        hold.minimumPressDuration = 0.15
        hold.allowableMovement = 20
        hold.cancelsTouchesInView = false
        let dismissPan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        for recognizer in [tap, hold, dismissPan] {
            recognizer.delegate = self
            view.addGestureRecognizer(recognizer)
        }
        for direction in [UISwipeGestureRecognizer.Direction.left, .right] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(swiped(_:)))
            swipe.direction = direction
            swipe.delegate = self
            view.addGestureRecognizer(swipe)
            tap.require(toFail: swipe)
        }
        tap.require(toFail: hold)
        tap.require(toFail: dismissPan)

        let center = NotificationCenter.default
        for name in [UIApplication.willResignActiveNotification, UIApplication.didBecomeActiveNotification,
                     UIAccessibility.voiceOverStatusDidChangeNotification, UIAccessibility.reduceMotionStatusDidChangeNotification] {
            center.addObserver(self, selector: #selector(environmentChanged), name: name, object: nil)
        }
        center.addObserver(self, selector: #selector(textSizeChanged), name: UIContentSizeCategory.didChangeNotification, object: nil)
        showCurrentPage(animated: false)
        environmentChanged()
    }

    public override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateContentSafeArea()
    }

    private func updateContentSafeArea() {
        guard safeAreaConstraints.count == 4 else { return }
        let insets = view.window?.safeAreaInsets ?? view.safeAreaInsets
        for (constraint, value) in zip(safeAreaConstraints, [insets.left, insets.top, -insets.right, -insets.bottom]) {
            constraint.constant = value
        }
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateContentSafeArea()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = view.bounds
        CATransaction.commit()
        backgroundView?.frame = view.bounds
        mediaContainer.frame = view.bounds
        for subview in mediaContainer.subviews { subview.frame = mediaContainer.bounds }
        let width = max(1, contentSafeArea.layoutFrame.width - 48)
        let copyHeight = copyStack.systemLayoutSizeFitting(CGSize(width: width, height: 0),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        let available = max(76, contentSafeArea.layoutFrame.height - 97)
        let targetHeight = min(available, max(233, ceil(copyHeight) + 76))
        if blockHeight.constant != targetHeight { blockHeight.constant = targetHeight }
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let source = presentationSource, let anchor = source.resolve(in: view) { source.hide(anchor) }
        isClosing = false
        setPaused(false, for: .hidden)
        setPaused(false, for: .dismissal)
        if displayLink == nil {
            let link = CADisplayLink(target: StoriesClockTarget(controller: self), selector: #selector(StoriesClockTarget.tick(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 60, preferred: 30)
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
        environmentChanged()
        if pages.isEmpty { close() }
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        setPaused(true, for: .hidden)
        setPaused(false, for: .scrolling)
        setPaused(false, for: .touch)
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || presentingViewController == nil { presentationSource?.restore() }
        displayLink?.invalidate()
        displayLink = nil
    }

    deinit { displayLink?.invalidate() }

    fileprivate func tick(_ link: CADisplayLink) {
        let interval = previousTimestamp.map { link.timestamp - $0 } ?? 0
        previousTimestamp = link.timestamp
        apply(playback.advance(by: interval))
        progressView.update(index: playback.index, progress: playback.progress)
    }

    private func setPaused(_ paused: Bool, for reason: StoryPlaybackState.PauseReason) {
        playback.setPaused(paused, for: reason)
        previousTimestamp = nil
        displayLink?.isPaused = playback.isPaused
        media?.setPlaying(!playback.isPaused)
    }

    @objc private func environmentChanged() {
        setPaused(UIApplication.shared.applicationState != .active, for: .background)
        setPaused(UIAccessibility.isVoiceOverRunning, for: .voiceOver)
    }

    @objc private func textSizeChanged() {
        updateCopy()
        view.setNeedsLayout()
    }

    private func showCurrentPage(animated: Bool, forward: Bool = true) {
        guard pages.indices.contains(playback.index) else { nextButton.isHidden = true; return }
        setPaused(false, for: .scrolling)
        mediaAnimator?.stopAnimation(false)
        mediaAnimator?.finishAnimation(at: .end)
        let previous = media
        previous?.setPlaying(false)
        let next = StoryMediaView(page: pages[playback.index])
        next.frame = mediaContainer.bounds
        mediaContainer.addSubview(next)
        media = next
        next.setPlaying(!playback.isPaused)
        let shouldAnimate = animated && TradeMotion.enabled && !mediaContainer.bounds.isEmpty
        if shouldAnimate, let previous {
            let isRTL = (view.effectiveUserInterfaceLayoutDirection == .rightToLeft) != !forward
            let width = next.bounds.width
            let mask = StorySweepMaskView(size: next.bounds.size, isRTL: isRTL)
            mask.frame.origin.x = isRTL ? -4 * width : width
            next.mask = mask
            let animator = UIViewPropertyAnimator(duration: 0.4, curve: .easeInOut) {
                mask.frame.origin.x = isRTL ? 0 : -3 * width
                previous.alpha = 0
            }
            animator.addCompletion { [weak next, weak previous] _ in
                next?.mask = nil
                previous?.removeFromSuperview()
            }
            mediaAnimator = animator
            animator.startAnimation()
            UIView.transition(with: copyStack, duration: 0.22, options: [.transitionCrossDissolve, .allowUserInteraction]) { self.updateCopy() }
        } else {
            previous?.removeFromSuperview()
            updateCopy()
        }
        updateButton(animated: shouldAnimate)
        copyScrollView.setContentOffset(.zero, animated: false)
        progressView.update(index: playback.index, progress: playback.progress)
        view.setNeedsLayout()
        if animated, UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .screenChanged, argument: titleLabel)
        }
    }

    private func updateCopy() {
        guard pages.indices.contains(playback.index) else { return }
        let page = pages[playback.index]
        for (label, text, style, lineHeight, tracking) in [
            (titleLabel, page.title, WTextStyle.screenTitle, 34.0, -0.65),
            (bodyLabel, page.body, WTextStyle.body, 23.0, -0.43),
        ] {
            let font = WTypography.uiFont(style, scaling: .dynamic, compatibleWith: traitCollection)
            let paragraph = NSMutableParagraphStyle()
            paragraph.minimumLineHeight = max(font.lineHeight, lineHeight * font.pointSize / (style == .screenTitle ? 28 : 17))
            paragraph.maximumLineHeight = paragraph.minimumLineHeight
            paragraph.alignment = .center
            label.attributedText = NSAttributedString(string: text, attributes: [
                .font: font, .foregroundColor: UIColor.white, .paragraphStyle: paragraph, .kern: tracking,
            ])
        }
    }

    private func updateButton(animated: Bool) {
        let title = pages[playback.index].buttonTitle
        nextButton.setTitle(title, animated: animated)
        nextButton.accessibilityLabel = title
    }

    var transitionActionButton: WInteractiveGlassButton { nextButton }

    func liftTransitionAction(into container: UIView) -> () -> Void {
        nextButton.finishTitleTransition()
        let frame = nextButton.convert(nextButton.bounds, to: container)
        let constraints = contentBlock.constraints.filter {
            ($0.firstItem as? UIView) === nextButton || ($0.secondItem as? UIView) === nextButton
        }
        NSLayoutConstraint.deactivate(constraints)
        nextButton.removeFromSuperview()
        nextButton.translatesAutoresizingMaskIntoConstraints = true
        container.addSubview(nextButton)
        nextButton.frame = frame
        return { [self] in
            nextButton.removeFromSuperview()
            nextButton.translatesAutoresizingMaskIntoConstraints = false
            contentBlock.addSubview(nextButton)
            NSLayoutConstraint.activate(constraints)
            contentBlock.layoutIfNeeded()
        }
    }

    func resetDismissalGeometry() {
        view.transform = .identity
        view.clipsToBounds = false
        view.layer.cornerRadius = 0
        if #available(iOS 26, *) { view.cornerConfiguration = .corners(radius: .fixed(0)) }
        dismissalCornerRadius = 0
        dismissalVelocity = 0
        isDragging = false
    }

    private func navigate(forward: Bool) {
        guard !isClosing, !isDragging, dragReturnAnimator == nil else { return }
        previousTimestamp = nil
        apply(forward ? playback.next() : playback.previous(), forward: forward)
    }

    private func apply(_ change: StoryPlaybackState.Change, forward: Bool = true) {
        switch change {
        case .none: break
        case .page: showCurrentPage(animated: true, forward: forward)
        case .completed:
            close()
            if !completionDelivered { completionDelivered = true; onCompletion?() }
        }
    }

    @objc private func nextPressed() { navigate(forward: true) }
    @objc private func accessibilityNext() -> Bool { navigate(forward: true); return true }
    @objc private func accessibilityPrevious() -> Bool { navigate(forward: false); return true }

    private func close() {
        guard !isClosing else { return }
        if let dragReturnAnimator {
            let transform = view.layer.presentation()?.affineTransform() ?? view.transform
            dragReturnAnimator.stopAnimation(true)
            self.dragReturnAnimator = nil
            view.transform = transform
        }
        isDragging = false
        isClosing = true
        setPaused(true, for: .dismissal)
        dismiss(animated: true)
    }

    func resumeAfterCancelledDismissal() {
        isClosing = false
        setPaused(false, for: .dismissal)
        setPaused(false, for: .hidden)
        setPaused(false, for: .touch)
        environmentChanged()
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        let isLeading = gesture.location(in: view).x < view.bounds.midX
        navigate(forward: isLeading == (view.effectiveUserInterfaceLayoutDirection == .rightToLeft))
    }

    @objc private func held(_ gesture: UILongPressGestureRecognizer) {
        setPaused(gesture.state == .began || gesture.state == .changed, for: .touch)
    }

    @objc private func swiped(_ gesture: UISwipeGestureRecognizer) {
        guard gesture.state == .ended else { return }
        let forward = (gesture.direction == .left) != (view.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        navigate(forward: forward)
    }

    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        setPaused(true, for: .scrolling)
    }

    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { setPaused(false, for: .scrolling) }
    }

    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        setPaused(false, for: .scrolling)
    }

    @objc private func copyScrollPanned(_ gesture: UIPanGestureRecognizer) {
        if gesture.state == .cancelled || gesture.state == .failed {
            setPaused(false, for: .scrolling)
        }
    }

    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view.superview)
        let distance = max(0, translation.y)
        switch gesture.state {
        case .began:
            guard !isClosing, dragReturnAnimator == nil else { return }
            isDragging = true
            setPaused(true, for: .dismissal)
            dismissalCornerRadius = StoriesTransition.deviceCornerRadius(for: view)
            view.clipsToBounds = true
            view.layer.cornerCurve = .continuous
            if #available(iOS 26, *) {
                view.cornerConfiguration = .corners(radius: .fixed(dismissalCornerRadius))
            } else { view.layer.cornerRadius = dismissalCornerRadius }
            view.transform = CGAffineTransform(translationX: 0, y: distance)
        case .changed:
            guard isDragging else { return }
            view.transform = CGAffineTransform(translationX: 0, y: distance)
        case .ended, .cancelled:
            guard isDragging else { return }
            let velocity = gesture.velocity(in: view.superview).y
            isDragging = false
            if gesture.state == .ended && (distance > view.bounds.height * 0.2 || velocity > 700) {
                dismissalVelocity = velocity
                close()
            } else {
                let animator = UIViewPropertyAnimator(duration: 0.35, dampingRatio: 0.86) {
                    self.view.transform = .identity
                }
                dragReturnAnimator = animator
                animator.addCompletion { [weak self] _ in
                    guard let self else { return }
                    resetDismissalGeometry()
                    dragReturnAnimator = nil
                    resumeAfterCancelledDismissal()
                }
                animator.startAnimation()
            }
        default: break
        }
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard !isClosing, dragReturnAnimator == nil else { return false }
        if let pan = gestureRecognizer as? UIPanGestureRecognizer {
            let translation = pan.translation(in: view.superview)
            let velocity = pan.velocity(in: view.superview)
            let direction = translation == .zero ? velocity : translation
            let shouldBegin = direction.y > abs(direction.x)
            return shouldBegin
        }
        return true
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let touched = touch.view else { return true }
        if touched.isDescendant(of: nextButton) || touched.isDescendant(of: closeButton) { return false }
        if touched.isDescendant(of: copyScrollView), copyScrollView.contentSize.height > copyScrollView.bounds.height + 1 {
            return gestureRecognizer is UILongPressGestureRecognizer || gestureRecognizer is UISwipeGestureRecognizer
        }
        return true
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                  shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer is UISwipeGestureRecognizer {
            return otherGestureRecognizer is UILongPressGestureRecognizer || otherGestureRecognizer === copyScrollView.panGestureRecognizer
        }
        if otherGestureRecognizer is UISwipeGestureRecognizer {
            return gestureRecognizer is UILongPressGestureRecognizer || gestureRecognizer === copyScrollView.panGestureRecognizer
        }
        if gestureRecognizer is UILongPressGestureRecognizer, otherGestureRecognizer is UIPanGestureRecognizer {
            return otherGestureRecognizer === copyScrollView.panGestureRecognizer || otherGestureRecognizer.view === view
        }
        if otherGestureRecognizer is UILongPressGestureRecognizer, gestureRecognizer is UIPanGestureRecognizer {
            return gestureRecognizer === copyScrollView.panGestureRecognizer || gestureRecognizer.view === view
        }
        return false
    }

    public func animationController(forPresented presented: UIViewController, presenting: UIViewController,
                                    source: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? {
        StoriesTransition(isPresenting: true)
    }

    public func animationController(forDismissed dismissed: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? {
        StoriesTransition(isPresenting: false)
    }


}

@MainActor private final class StoriesClockTarget: NSObject {
    weak var controller: StoriesViewController?
    init(controller: StoriesViewController) { self.controller = controller }
    @objc func tick(_ link: CADisplayLink) {
        guard let controller else { link.invalidate(); return }
        controller.tick(link)
    }
}

private final class StoriesRootView: UIView {
    var onAccessibilityScroll: ((UIAccessibilityScrollDirection) -> Bool)?
    var onAccessibilityEscape: (() -> Bool)?
    override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
        onAccessibilityScroll?(direction) ?? false
    }
    override func accessibilityPerformEscape() -> Bool { onAccessibilityEscape?() ?? false }
}
