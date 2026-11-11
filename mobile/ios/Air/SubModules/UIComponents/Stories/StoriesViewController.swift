import UIKit
import WalletContext

private let STORY_CARD_CORNER_RADIUS: CGFloat = 24
private let STORY_REGULAR_MINIMUM_DIMENSION: CGFloat = 600

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
    private var preparedMedia: (index: Int, view: StoryMediaView)?
    private var mediaAnimator: UIViewPropertyAnimator?
    private let progressView: StoryProgressView
    private let contentBlock = UIView()
    private let copyScrollView = UIScrollView()
    private let copyStack = UIStackView()
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let nextButton = WInteractiveGlassButton(style: .secondary)
    private var actionAnimator: UIViewPropertyAnimator?
    private let closeButton = WInteractiveGlassButton(style: .secondary)
    private var blockHeight: NSLayoutConstraint!
    private var copyBottomConstraint: NSLayoutConstraint!
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

    var isCardLayout: Bool {
        let traits = viewIfLoaded?.window?.traitCollection ?? presentingViewController?.view.window?.traitCollection ?? traitCollection
        let size = viewIfLoaded?.window?.bounds.size ?? presentingViewController?.view.window?.bounds.size ?? viewIfLoaded?.bounds.size ?? .zero
        return traits.userInterfaceIdiom == .pad || min(size.width, size.height) >= STORY_REGULAR_MINIMUM_DIMENSION
    }

    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        isCardLayout ? .all : .portrait
    }

    public override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        isCardLayout ? super.preferredInterfaceOrientationForPresentation : .portrait
    }

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

        for child in [progressView, contentBlock] {
            child.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(child)
        }
        view.addSubview(closeButton)
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
        copyBottomConstraint = copyScrollView.bottomAnchor.constraint(equalTo: contentBlock.bottomAnchor, constant: -76)
        NSLayoutConstraint.activate([
            progressView.leadingAnchor.constraint(equalTo: contentSafeArea.leadingAnchor, constant: 24),
            progressView.trailingAnchor.constraint(equalTo: contentSafeArea.trailingAnchor, constant: -24),
            progressView.topAnchor.constraint(equalTo: contentSafeArea.topAnchor, constant: 4),
            progressView.heightAnchor.constraint(equalToConstant: 3),
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
            copyBottomConstraint,
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
        let insets: UIEdgeInsets
        if isCardLayout {
            insets = .init(top: 20, left: 0, bottom: 16, right: 0)
        } else {
            insets = view.window?.safeAreaInsets ?? view.safeAreaInsets
        }
        for (constraint, value) in zip(safeAreaConstraints, [insets.left, insets.top, -insets.right, -insets.bottom]) {
            constraint.constant = value
        }
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateContentSafeArea()
        updateCloseButtonLayout()
        if !isDragging, dragReturnAnimator == nil { updatePresentationAppearance() }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = view.bounds
        CATransaction.commit()
        let mediaFrame = CGRect(x: contentSafeArea.layoutFrame.minX, y: 0,
                                width: contentSafeArea.layoutFrame.width, height: view.bounds.height)
        backgroundView?.frame = mediaFrame
        mediaContainer.frame = mediaFrame
        for subview in mediaContainer.subviews { subview.frame = mediaContainer.bounds }
        let width = max(1, contentSafeArea.layoutFrame.width - 48)
        let copyHeight = copyStack.systemLayoutSizeFitting(CGSize(width: width, height: 0),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        let hasAction = pages.indices.contains(playback.index) && pages[playback.index].buttonTitle != nil
        let mediaHeight = preferredContentSize.width > 0
            ? mediaFrame.width * preferredContentSize.height / preferredContentSize.width : mediaFrame.height
        // Reclaim unused button space when aspect-fill cropping brings the artwork closer to the copy
        let reclaimedHeight = !isCardLayout && !hasAction ? min(76, max(0, (mediaHeight - mediaFrame.height) / 2)) : 0
        let actionHeight: CGFloat = isCardLayout && !hasAction ? 0 : 76 - reclaimedHeight
        copyBottomConstraint.constant = -actionHeight
        let available = max(76, contentSafeArea.layoutFrame.height - 97)
        let targetHeight = min(available, max(233 - reclaimedHeight, ceil(copyHeight) + actionHeight))
        if blockHeight.constant != targetHeight { blockHeight.constant = targetHeight }
    }

    private func updateCloseButtonLayout() {
        if #available(iOS 27.1, *), !isCardLayout {
            let edge: NSDirectionalRectEdge
            switch traitCollection.verticalBarEdge {
            case .leading: edge = .leading
            case .trailing: edge = .trailing
            default: edge = []
            }
            if !edge.isEmpty {
                let region = view.layoutGuide(for: .bar(onEdge: edge, extent: 48)).layoutFrame
                if !region.isEmpty {
                    closeButton.frame = CGRect(x: region.midX - 24, y: max(region.minY, view.bounds.minY + 24), width: 48, height: 48)
                    return
                }
            }
        }
        let safeFrame = contentSafeArea.layoutFrame
        let isRtl = view.effectiveUserInterfaceLayoutDirection == .rightToLeft
        closeButton.frame = CGRect(x: isRtl ? safeFrame.minX + 24 : safeFrame.maxX - 68,
                                   y: safeFrame.minY + 23, width: 44, height: 44)
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let source = presentationSource, let anchor = source.resolve(in: view) { source.hide(anchor) }
        isClosing = false
        setPaused(false, for: .hidden)
        setPaused(false, for: .dismissal)
        if displayLink == nil {
            let link = CADisplayLink(target: StoriesClockTarget(controller: self), selector: #selector(StoriesClockTarget.tick(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
        environmentChanged()
        prepareNextMedia()
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
        apply(playback.advance(by: interval, isWaitingForMedia: media?.isWaitingForFirstFrame == true))
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
        let next = preparedMedia?.index == playback.index ? preparedMedia!.view : StoryMediaView(page: pages[playback.index])
        if preparedMedia?.view !== next { preparedMedia?.view.removeFromSuperview() }
        preparedMedia = nil
        next.frame = mediaContainer.bounds
        next.alpha = 1
        mediaContainer.addSubview(next)
        media = next
        next.preparePlayback()
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
            animator.addCompletion { [weak self, weak next, weak previous, index = playback.index] _ in
                next?.mask = nil
                previous?.removeFromSuperview()
                if self?.playback.index == index { self?.prepareNextMedia() }
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

    private func prepareNextMedia() {
        let index = playback.index + 1
        guard pages.indices.contains(index), preparedMedia?.index != index, let media,
              !UIAccessibility.isReduceMotionEnabled, !playback.pauseReasons.contains(.hidden) else { return }
        preparedMedia?.view.removeFromSuperview()
        let next = StoryMediaView(page: pages[index])
        next.frame = mediaContainer.bounds
        next.alpha = 0
        mediaContainer.insertSubview(next, belowSubview: media)
        preparedMedia = (index, next)
        next.preparePlayback()
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
        finishActionTransition()
        let title = pages[playback.index].buttonTitle
        let isVisible = title != nil
        let wasVisible = !nextButton.isHidden
        if let title { nextButton.setTitle(title, animated: animated && wasVisible) }
        nextButton.accessibilityLabel = title
        nextButton.isUserInteractionEnabled = isVisible
        nextButton.accessibilityElementsHidden = !isVisible
        guard wasVisible != isVisible else { return }
        let changes = { self.nextButton.setGlassMaterialized(isVisible) }
        guard animated, TradeMotion.enabled, nextButton.window != nil else {
            UIView.performWithoutAnimation(changes)
            nextButton.isHidden = !isVisible
            return
        }
        nextButton.isHidden = false
        nextButton.layoutIfNeeded()
        let animator = UIViewPropertyAnimator(duration: TimeInterval(GlassMotion.materialize.response), curve: .easeInOut, animations: changes)
        animator.addCompletion { [weak self] _ in
            self?.nextButton.isHidden = !isVisible
            self?.actionAnimator = nil
        }
        actionAnimator = animator
        animator.startAnimation()
    }

    func finishActionTransition() {
        actionAnimator?.stopAnimation(false)
        actionAnimator?.finishAnimation(at: .end)
        actionAnimator = nil
    }

    var transitionActionButton: WInteractiveGlassButton { nextButton }

    func liftTransitionAction(into container: UIView) -> () -> Void {
        finishActionTransition()
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
        updatePresentationAppearance()
        dismissalCornerRadius = 0
        dismissalVelocity = 0
        isDragging = false
    }

    func updatePresentationAppearance() {
        let radius = isCardLayout ? STORY_CARD_CORNER_RADIUS : 0
        view.clipsToBounds = isCardLayout
        view.layer.cornerCurve = .continuous
        view.layer.cornerRadius = radius
        if #available(iOS 26, *) { view.cornerConfiguration = .corners(radius: .fixed(radius)) }
    }

    var presentationCornerRadius: CGFloat {
        isCardLayout ? STORY_CARD_CORNER_RADIUS : StoriesTransition.deviceCornerRadius(for: view)
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
            dismissalCornerRadius = presentationCornerRadius
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

    public func presentationController(forPresented presented: UIViewController, presenting: UIViewController?,
                                       source: UIViewController) -> UIPresentationController? {
        StoriesPresentationController(presentedViewController: presented, presenting: presenting)
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
