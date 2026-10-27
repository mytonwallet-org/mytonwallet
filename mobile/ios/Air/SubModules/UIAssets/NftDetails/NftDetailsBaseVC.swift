import UIKit
import UIComponents
import WalletContext

final class NftDetailsNavigationButton: UIButton {
    override var intrinsicContentSize: CGSize { CGSize(width: 44, height: 44) }

    override func sizeThatFits(_ size: CGSize) -> CGSize { intrinsicContentSize }

    static let backTransitionIdentifier = "nft.collection.back"

    func makeNavigationItem(alignsToSystemBackButton: Bool = true, usesClearGlass: Bool = true) -> UIBarButtonItem {
        if #unavailable(iOS 26), alignsToSystemBackButton, var config = configuration {
            // A plain custom item is centered in a 44pt slot; the legacy system
            // chevron is 16pt farther left. Keep the hit area, align the symbol.
            config.contentInsets.leading -= 32
            configuration = config
        }
        translatesAutoresizingMaskIntoConstraints = false
        let container: UIView
        let contentView: UIView
        if #available(iOS 26, *) {
            let effect = UIGlassEffect(style: usesClearGlass ? .clear : .regular)
            effect.isInteractive = true
            let glassContainer = UIVisualEffectView(effect: effect)
            glassContainer.cornerConfiguration = .capsule()
            container = glassContainer
            contentView = glassContainer.contentView
        } else {
            container = UIView()
            contentView = container
        }
        container.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        container.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(self)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 44),
            container.heightAnchor.constraint(equalToConstant: 44),
            leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            topAnchor.constraint(equalTo: contentView.topAnchor),
            bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
        // Resolve the glass at its final size before the navigation bar animates
        // the item in. Otherwise its first layout animates the material separately.
        UIView.performWithoutAnimation {
            updateConfiguration()
            container.layoutIfNeeded()
        }
        let customView: UIView
        if #available(iOS 26, *) {
            customView = NftNavigationButtonSlot(material: container)
        } else { customView = container }
        let item = UIBarButtonItem(customView: customView)
        if #available(iOS 26, *) {
            item.hidesSharedBackground = true
            item.identifier = Self.backTransitionIdentifier
        }
        return item
    }
}

// UIKit can composite custom glass behind the incoming screen during a push.
// Keep the bar item in place for layout and matching, and lift only its live content.
final class NftNavigationButtonSlot: UIView {
    let material: UIView
    private weak var overlayParent: UIView?
    override var intrinsicContentSize: CGSize { CGSize(width: 44, height: 44) }

    init(material: UIView) {
        self.material = material
        super.init(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 44),
            heightAnchor.constraint(equalToConstant: 44),
        ])
        material.translatesAutoresizingMaskIntoConstraints = true
        material.frame = bounds
        material.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(material)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let overlayParent, window != nil {
            material.frame = overlayFrame(in: overlayParent)
        }
    }

    private func overlayFrame(in parent: UIView) -> CGRect {
        let center = convert(CGPoint(x: bounds.midX, y: bounds.midY), to: parent)
        return CGRect(x: center.x - 22, y: center.y - 22, width: 44, height: 44)
    }

    func lift(in parent: UIView, fadeIn: Bool = false) {
        guard overlayParent == nil else { return }
        parent.layoutIfNeeded()
        UIView.performWithoutAnimation {
            overlayParent = parent
            material.autoresizingMask = []
            material.frame = overlayFrame(in: parent)
            material.isUserInteractionEnabled = false
            material.alpha = fadeIn ? 0 : 1
            parent.addSubview(material)
        }
        material.alpha = 1
    }
    func restore() {
        guard overlayParent != nil else { return }
        UIView.performWithoutAnimation {
            overlayParent = nil
            material.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            material.frame = bounds
            addSubview(material)
            material.isUserInteractionEnabled = true
            layoutIfNeeded()
        }
    }
}

public class NftDetailsBaseVC: WViewController, ContentOverlayAppearanceProviding {
    let manager: NftDetailsManager
    public var onContentOverlayAppearanceChange: ((_ animated: Bool) -> Void)?
    private var contentStatusBarStyle: UIStatusBarStyle = .default

    public override var preferredStatusBarStyle: UIStatusBarStyle { contentStatusBarStyle }
    
    private var selectedModel: ItemModel
    private var selectedModelSubscription: ItemModel.Subscription?
    private var liveAtmosphereSubscription: ItemModel.Subscription?

    private let backgroundView: Background.View
    private let contentContainer = UIView()
    private lazy var inlinePinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handleInlinePinch(_:)))
    private let pinchTouchGuard = NftDetailsPinchTouchGuard()
    private var gesturesSuspendedForPinch: [UIGestureRecognizer] = []
    private var isPinchInteractionActive: Bool {
        pinchTouchGuard.isClaimed || headerView?.isInlineZoomActive == true
    }
    private let mainScrollView = NftDetailMainScrollView()
    private let mainScrollContentView = UIView()
    private var headerView: NftDetailsMainHeaderView?
    private var pager: NftDetailsPagerView?
    private var isLottiePlaybackEnabled = false
    
    typealias Background = NftDetailsBackground
    typealias ItemModel = NftDetailsItemModel

    private nonisolated(unsafe) var memoryWarningObserver: NSObjectProtocol?
    private var previousVCBackBarButtonItem: UIBarButtonItem? = nil
    private weak var previousBackItemOwner: UIViewController?
    private var clearNavigationButton: UIButton?
    private var navigationButtonIsModalRoot: Bool?
    private var navigationContrastLink: CADisplayLink?
    private lazy var navigationContrastTarget = NftNavigationContrastTarget(owner: self)
    private weak var previousPopGestureDelegate: UIGestureRecognizerDelegate?
    private weak var previousContentPopGestureDelegate: UIGestureRecognizerDelegate?
    private var hasCustomBackGestureDelegates = false
    
    private struct State: Equatable, CustomStringConvertible {
        var isExpanded: Bool
        var pageTransition: NftDetailsPageTransitionState<ItemModel>
        var isPreviewHidden: Bool
        
        var description: String {
            var items: [String] = []
            if isExpanded { items.append("EXPANDED") }
            if !isPreviewHidden { items.append("PREVIEW_VISIBLE") }
            return "State(\(items.joined(separator: ", ")), transition: \(pageTransition))"
        }
    }
    
    private var state: State

    init(nfts: [NftDetailsItem], selectedIndex: Int, initiallyExpanded: Bool) {
        self.manager = NftDetailsManager(items: nfts)
        self.selectedModel = manager.models[selectedIndex]
        self.state = State(
            isExpanded: initiallyExpanded,
            pageTransition: .staticPage(selectedModel),
            isPreviewHidden: true
        )
        self.backgroundView = Background.View(colorResolver: manager.colorResolver)
        
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        memoryWarningObserver.map { NotificationCenter.default.removeObserver($0) }
    }
    
    // True when this VC is the root of a modally-presented navigation controller,
    // or has been presented directly without a navigation controller.
    private var isModalRoot: Bool {
        if let navigationController {
            return navigationController.viewControllers.first === self
                && navigationController.presentingViewController?.presentedViewController === navigationController
        }
        return presentingViewController != nil
    }

    /// Dismisses the screen using the same modal-vs-navigation logic as the close/back buttons.
    func dismissSelf() {
        if isModalRoot {
            dismiss(animated: true)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }

    private func configureNavigationItems() {
        configureClearNavigationButton()
    }

    private func configureClearNavigationButton() {
        if let navigationButtonIsModalRoot, navigationButtonIsModalRoot != isModalRoot {
            // A preloaded controller may acquire its modal parent after viewDidLoad.
            if navigationButtonIsModalRoot {
                navigationItem.rightBarButtonItem = nil
            } else {
                navigationItem.leftBarButtonItem = nil
            }
            clearNavigationButton = nil
        }
        guard clearNavigationButton == nil else {
            updateClearNavigationButtonColor()
            return
        }
        let action = UIAction { [weak self] _ in
            guard let self else { return }
            if let headerView, headerView.dismissFullScreen() { return }
            dismissSelf()
        }
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: isModalRoot ? "xmark" : "chevron.backward")
        config.preferredSymbolConfigurationForImage = .init(pointSize: 17, weight: .medium)
        config.cornerStyle = .fixed
        config.background.cornerRadius = 22
        config.contentInsets = .init(top: 11, leading: 11, bottom: 11, trailing: 11)
        let button = NftDetailsNavigationButton(configuration: config, primaryAction: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = lang(isModalRoot ? "Close" : "Back")
        clearNavigationButton = button
        navigationButtonIsModalRoot = isModalRoot
        updateClearNavigationButtonColor()
        let item = button.makeNavigationItem(alignsToSystemBackButton: !isModalRoot)
        navigationItem.hidesBackButton = true
        if isModalRoot {
            navigationItem.rightBarButtonItem = item
        } else {
            navigationItem.leftBarButtonItem = item
        }
    }

    public func contentOverlayAppearance(in rectInWindow: CGRect) -> ContentOverlayAppearance {
        func background(for model: ItemModel) -> UIColor {
            let fallback = manager.colorResolver.effectiveBaseColor(for: model)
            return headerView?.navigationBackgroundColor(for: model, in: rectInWindow, fallback: fallback) ?? fallback
        }
        let backgroundColor: UIColor
        let color: UIColor
        switch state.pageTransition {
        case .staticPage(let model):
            backgroundColor = background(for: model)
            color = backgroundColor.isLightColor ? .black : .white
        case let .transition(left, right, progress):
            let leftColor = background(for: left)
            let rightColor = background(for: right)
            backgroundColor = leftColor.nftBlended(with: rightColor, fraction: progress)
            color = (leftColor.isLightColor ? UIColor.black : .white).nftBlended(
                with: rightColor.isLightColor ? .black : .white, fraction: progress)
        }
        return ContentOverlayAppearance(usesClearGlass: true, foregroundColor: color,
                                        userInterfaceStyle: backgroundColor.isLightColor ? .light : .dark)
    }

    private func updateContentStatusBarStyle(animated: Bool) {
        var rect = CGRect.zero
        if let window = viewIfLoaded?.window, let scene = window.windowScene,
           let manager = scene.statusBarManager {
            rect = window.convert(manager.statusBarFrame, from: scene.screen.coordinateSpace)
        }
        let style: UIStatusBarStyle = contentOverlayAppearance(in: rect).userInterfaceStyle == .dark ? .lightContent : .darkContent
        guard style != contentStatusBarStyle else { return }
        contentStatusBarStyle = style
        let update = {
            var controller: UIViewController = self
            while let parent = controller.parent { controller = parent }
            controller.setNeedsStatusBarAppearanceUpdate()
        }
        if animated {
            UIView.animate(withDuration: 0.25, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction], animations: update)
        } else {
            update()
        }
    }

    fileprivate func updateClearNavigationButtonColor() {
        let animated = !state.pageTransition.isTransitioning && viewIfLoaded?.window != nil && !UIAccessibility.isReduceMotionEnabled
        updateContentStatusBarStyle(animated: animated)
        onContentOverlayAppearanceChange?(animated)
        guard let button = clearNavigationButton else { return }
        let rect = button.convert(button.bounds.insetBy(dx: 10, dy: 10), to: nil)
        let color = contentOverlayAppearance(in: rect).foregroundColor ?? .label
        guard button.tintColor != color else { return }
        let update = {
            button.tintColor = color
            if var config = button.configuration {
                let symbol = UIImage(systemName: self.isModalRoot ? "xmark" : "chevron.backward",
                                     withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium))
                config.image = symbol?.withTintColor(color, renderingMode: .alwaysOriginal)
                config.baseForegroundColor = color
                button.configuration = config
            }
        }
        if state.pageTransition.isTransitioning || button.window == nil || UIAccessibility.isReduceMotionEnabled {
            update()
        } else {
            UIView.transition(with: button.imageView ?? button, duration: 0.25,
                              options: [.transitionCrossDissolve, .beginFromCurrentState, .allowAnimatedContent],
                              animations: update)
        }
    }

    private func installCustomBackGestureDelegates() {
        guard !isModalRoot, !hasCustomBackGestureDelegates,
              let navigationController = navigationController as? WNavigationController else { return }
        // UIKit's default delegates require a system back item; use the navigation controller's back-swipe policy for the custom glass button
        previousPopGestureDelegate = navigationController.interactivePopGestureRecognizer?.delegate
        if #available(iOS 26, *) {
            previousContentPopGestureDelegate = navigationController.interactiveContentPopGestureRecognizer?.delegate
        }
        navigationController.interactivePopGestureRecognizer?.delegate = navigationController
        if #available(iOS 26, *) { navigationController.interactiveContentPopGestureRecognizer?.delegate = navigationController }
        hasCustomBackGestureDelegates = true
    }

    private func restoreBackGestureDelegates() {
        guard hasCustomBackGestureDelegates else { return }
        navigationController?.interactivePopGestureRecognizer?.delegate = previousPopGestureDelegate
        if #available(iOS 26, *) {
            navigationController?.interactiveContentPopGestureRecognizer?.delegate = previousContentPopGestureDelegate
        }
        previousPopGestureDelegate = nil
        previousContentPopGestureDelegate = nil
        hasCustomBackGestureDelegates = false
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        manager.colorResolver.update(traitCollection: traitCollection)

        navigationItem.backButtonDisplayMode = .minimal

        inlinePinchGesture.delegate = self
        contentContainer.addGestureRecognizer(inlinePinchGesture)
        pinchTouchGuard.canClaim = { [weak self] in
            guard let self else { return false }
            return self.canBeginInlinePinch(at: self.pinchTouchGuard.location(in: self.contentContainer))
                || self.headerView?.isInlineZoomActive == true
        }
        pinchTouchGuard.onClaimChanged = { [weak self] _ in self?.updatePinchGestureOwnership() }
        contentContainer.addGestureRecognizer(pinchTouchGuard)
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentContainer)

        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(backgroundView)

        mainScrollView.contentViewToRedirect = mainScrollContentView
        mainScrollView.showsVerticalScrollIndicator = false
        mainScrollView.showsHorizontalScrollIndicator = false
        mainScrollView.alwaysBounceVertical = true
        mainScrollView.panGestureRecognizer.maximumNumberOfTouches = 1
        mainScrollView.contentInsetAdjustmentBehavior = .never
        mainScrollView.contentInset = .zero
        mainScrollView.delegate = self
        if #available(iOS 26.0, *) {
            mainScrollView.topEdgeEffect.isHidden = true
            mainScrollView.bottomEdgeEffect.isHidden = true
        }
        mainScrollView.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(mainScrollView)

        mainScrollContentView.translatesAutoresizingMaskIntoConstraints = false
        mainScrollView.addSubview(mainScrollContentView)
        
        NSLayoutConstraint.activate([
            contentContainer.topAnchor.constraint(equalTo: view.topAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),

            backgroundView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),

            mainScrollView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            mainScrollView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            mainScrollView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            mainScrollView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),

            mainScrollContentView.topAnchor.constraint(equalTo: mainScrollView.contentLayoutGuide.topAnchor),
            mainScrollContentView.leadingAnchor.constraint(equalTo: mainScrollView.contentLayoutGuide.leadingAnchor),
            mainScrollContentView.trailingAnchor.constraint(equalTo: mainScrollView.contentLayoutGuide.trailingAnchor),
            mainScrollContentView.bottomAnchor.constraint(equalTo: mainScrollView.contentLayoutGuide.bottomAnchor),
            mainScrollContentView.widthAnchor.constraint(equalTo: contentContainer.widthAnchor),
        ])
        
        selectModel(selectedModel, animated: false, forced: true, initiator: .none)
        configureNavigationItems()

        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleMemoryWarning()
            }
        }
    }

    @MainActor
    private func handleMemoryWarning() {
        manager.releaseImageResourcesOnMemoryWarning()
    }
    
    public override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()

        let sa = view.safeAreaInsets
        
        var scrollInset = UIEdgeInsets.zero
        scrollInset.bottom = sa.bottom
        mainScrollView.contentInset = scrollInset
        mainScrollView.scrollIndicatorInsets = scrollInset

        UIView.performWithoutAnimation {
            installOrUpdateSubviews()
            view.layoutIfNeeded()
        }
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            manager.colorResolver.update(traitCollection: traitCollection)
            updateBackground()
        }
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Keep the destination layer tree static until the navigation transition has finished.
        setLottiePlaybackEnabled(false)
        if let sheet = self.sheetPresentationController {
            sheet.configureAllowsInteractiveDismiss(false)
        }
        configureNavigationItems()
        prepareGlassForNavigationPush()
        installCustomBackGestureDelegates()

        if #unavailable(iOS 26) {
            // iOS 17: backButtonDisplayMode alone doesn't suppress the title from the previous VC.
            // Temporarily set an empty backBarButtonItem on the previous VC while this screen is visible.
            if let previousVC = navigationController?.viewControllers.dropLast().last {
                previousBackItemOwner = previousVC
                previousVCBackBarButtonItem = previousVC.navigationItem.backBarButtonItem
                previousVC.navigationItem.backBarButtonItem = UIBarButtonItem(title: "", style: .plain, target: nil, action: nil)
            }
        }
    }

    private func prepareGlassForNavigationPush() {
        guard #available(iOS 26, *), isMovingToParent,
              let navigationController,
              let coordinator = transitionCoordinator, coordinator.isAnimated,
              let slot = navigationItem.leftBarButtonItem?.customView as? NftNavigationButtonSlot,
              coordinator.viewController(forKey: .from)?.navigationItem.leftBarButtonItem?.identifier
                != NftDetailsNavigationButton.backTransitionIdentifier else { return }
        coordinator.animate(alongsideTransition: { _ in
            slot.lift(in: navigationController.view, fadeIn: true)
        }, completion: { _ in slot.restore() })
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        setLottiePlaybackEnabled(true)
        if clearNavigationButton != nil, navigationContrastLink == nil {
            let link = CADisplayLink(target: navigationContrastTarget, selector: #selector(NftNavigationContrastTarget.tick))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            link.add(to: .main, forMode: .common)
            navigationContrastLink = link
        }
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationContrastLink?.invalidate()
        navigationContrastLink = nil
        restoreBackGestureDelegates()
        setLottiePlaybackEnabled(false)
        manager.colorCache.saveIfNeeded()

        if let sheet = self.sheetPresentationController {
            sheet.configureAllowsInteractiveDismiss(true)
        }

        if #unavailable(iOS 26) {
            previousBackItemOwner?.navigationItem.backBarButtonItem = previousVCBackBarButtonItem
            previousBackItemOwner = nil
            previousVCBackBarButtonItem = nil
        }
    }

    private func setLottiePlaybackEnabled(_ isEnabled: Bool) {
        isLottiePlaybackEnabled = isEnabled
        headerView?.setLottiePlaybackEnabled(isEnabled)
    }
    
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        installOrUpdateSubviews()
    }

    public override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animateAlongsideTransition(in: view) { [weak self] _ in
            self?.installOrUpdateSubviews()
        } completion: { [weak self] _ in
            self?.installOrUpdateSubviews()
        }
    }


    private func installOrUpdateSubviews() {
        guard isViewLoaded, !manager.models.isEmpty else { return }

        contentContainer.layoutIfNeeded()
        let pageWidth = contentContainer.bounds.width
        guard pageWidth > 0, contentContainer.bounds.height > 0 else { return }
        let heroFrame = NftDetailsHeroLayout.frame(in: contentContainer.bounds.size, safeAreaInsets: view.safeAreaInsets,
            userInterfaceIdiom: traitCollection.userInterfaceIdiom,
            navigationBarHeight: navigationController?.navigationBar.bounds.height ?? 0)
        let didChangeGeometry = headerView?.layoutGeometry.expandedImageFrame != heroFrame
            || pager?.layoutGeometry.pageWidth != pageWidth

        manager.targetWidth = pageWidth
        
        let collapsedHeight = 165.0
        installOrUpdateHeader(pageWidth: pageWidth, collapsedHeight: collapsedHeight, heroFrame: heroFrame)
        installOrUpdatePager(pageWidth: pageWidth, collapsedHeight: collapsedHeight, heroFrame: heroFrame)

        if didChangeGeometry {
            _ = headerView?.dismissFullScreen()
        }

        if let pager, state.isExpanded, !pager.isExpanded {
            pager.simulateUserScrollToExpand(mainScrollView)
        }
        if didChangeGeometry { updateBackground() }
    }
    
    private func installOrUpdateHeader(pageWidth: CGFloat, collapsedHeight: CGFloat, heroFrame: CGRect) {
        assert(pageWidth > 0 && isViewLoaded && collapsedHeight > 0)

        let layoutGeometry = NftDetailsMainHeaderView.LayoutGeometry(
            topSafeAreaInset: view.safeAreaInsets.top,
            leadingSafeAreaInset: view.safeAreaInsets.left,
            trailingSafeAreaInset: view.safeAreaInsets.right,
            collapsedAreaHeight: collapsedHeight,
            pageWidth: pageWidth,
            expandedImageFrame: heroFrame
        )

        guard headerView?.layoutGeometry != layoutGeometry else { return }

        if let headerView {
            headerView.layoutGeometry = layoutGeometry
            headerView.overlayParentView = view
        } else {
            let newHeader = NftDetailsMainHeaderView(
                frame: contentContainer.bounds,
                models: manager.models,
                selectedModel: selectedModel,
                delegate: self,
                layoutGeometry: layoutGeometry,
                coverFlowThumbnailDownloader: manager.coverFlowThumbnailDownloader,
                colorResolver: manager.colorResolver
            )
            newHeader.overlayParentView = view
            newHeader.translatesAutoresizingMaskIntoConstraints = false
            contentContainer.insertSubview(newHeader, belowSubview: mainScrollView)
            NSLayoutConstraint.activate([
                newHeader.topAnchor.constraint(equalTo: contentContainer.topAnchor),
                newHeader.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
                newHeader.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
                newHeader.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
            ])
            headerView = newHeader
            mainScrollView.headerViewToRedirect = newHeader
            newHeader.setLottiePlaybackEnabled(isLottiePlaybackEnabled)
        }
    }

    private func installOrUpdatePager(pageWidth: CGFloat, collapsedHeight: CGFloat, heroFrame: CGRect) {
        assert(pageWidth > 0 && isViewLoaded && collapsedHeight > 0)
        
        let layoutGeometry = NftDetailsPagerView.LayoutGeometry(
            topSafeAreaInset: view.safeAreaInsets.top,
            collapsedAreaHeight: collapsedHeight,
            pageWidth: pageWidth,
            expandedImageFrame: heroFrame
        )
        
        guard pager?.layoutGeometry != layoutGeometry else { return }
        
        var initiallyExpanded = false
        if let existingPager = pager, existingPager.layoutGeometry.pageWidth != pageWidth {
            initiallyExpanded = existingPager.isExpanded
            existingPager.removeFromSuperview()
            pager = nil
        }
        
        if let pager {
            pager.layoutGeometry = layoutGeometry
        } else {
            let newPager = NftDetailsPagerView(
                models: manager.models,
                colorResolver: manager.colorResolver,
                currentIndex: selectedModel.index,
                layoutGeometry: layoutGeometry,
                delegate: self,
                initiallyExpanded: initiallyExpanded
            )
            newPager.translatesAutoresizingMaskIntoConstraints = false
            mainScrollContentView.addSubview(newPager)
            NSLayoutConstraint.activate([
                newPager.topAnchor.constraint(equalTo: mainScrollContentView.topAnchor),
                newPager.leadingAnchor.constraint(equalTo: mainScrollContentView.leadingAnchor),
                newPager.trailingAnchor.constraint(equalTo: mainScrollContentView.trailingAnchor),
                newPager.bottomAnchor.constraint(equalTo: mainScrollContentView.bottomAnchor),
            ])
            pager = newPager
        }
    }
        
    private func updateBackground() {
        if liveAtmosphereSubscription?.model !== selectedModel {
            liveAtmosphereSubscription = .init(model: selectedModel, event: .liveAtmosphereUpdated, tag: "BG/Animation") { [weak self] in
                self?.updateBackground()
            }
        }
        
        func getPageModel(forModel model: ItemModel) -> Background.PageModel {
            let image: CIImage? = {
                guard case .loaded(let processed) = model.processedImageState else { return nil }
                return processed.artworkCIImage
            }()
            let atmosphere: CIImage? = {
                if let live = model.liveAtmosphereImage { return CIImage(image: live) }
                guard case .loaded(let processed) = model.processedImageState else { return nil }
                return processed.atmosphere(height: pager?.atmosphereHeight(for: model) ?? 200,
                                            pageWidth: headerView?.layoutGeometry.expandedImageFrame.width ?? backgroundView.bounds.width)?.ciImage
            }()
            return .init(
                backgroundColor: manager.colorResolver.effectiveBaseColor(for: model),
                image: image,
                tag: model.shortDescription,
                atmosphereImage: atmosphere,
                atmosphereHeight: pager?.atmosphereHeight(for: model) ?? 200,
                hasLiveAtmosphere: model.liveAtmosphereImage != nil
            )
        }
        
        var pageState: Background.PageState
        switch state.pageTransition {
        case let .staticPage(page):
            pageState = .staticPage(getPageModel(forModel: page))
        case let .transition(leftPage, rightPage, progress):
            pageState = .transition(
                    leftPage: getPageModel(forModel: leftPage),
                    rightPage: getPageModel(forModel: rightPage),
                    progress: CGFloat(progress)
                )
        }

        headerView?.setAtmosphereHeight(pager?.atmosphereHeight(for: selectedModel) ?? 200)
        if let other = headerView?.updateNativePageTransition(state.pageTransition,
            color: manager.colorResolver.effectiveBaseColor(for: selectedModel)) {
            // The header supplies the live selected page and its complete base
            // color, masked over this opaque other page. No video pixels cross
            // from Core Animation to Metal during the gesture.
            pageState = .staticPage(getPageModel(forModel: other))
        }

        let model = Background.Model(
            pageState: pageState,
            isExpanded: state.isExpanded,
            shouldShowPreview: state.isPreviewHidden && state.isExpanded,
            heroFrame: headerView?.layoutGeometry.expandedImageFrame ?? .zero,
            shouldShowAtmosphere: (state.isPreviewHidden || headerView?.needsBackgroundAtmosphere == true) && state.isExpanded,
            contentOffsetY: mainScrollView.contentOffset.y,
            isViewportMoving: mainScrollView.isTracking || mainScrollView.isDragging || mainScrollView.isDecelerating
        )
                
        backgroundView.setModel(model)
        let edgeColor = pageState.edgeColor(fallback: manager.colorResolver.fallbackColor)
        if view.backgroundColor != edgeColor {
            if state.pageTransition.isTransitioning || view.window == nil || UIAccessibility.isReduceMotionEnabled {
                view.backgroundColor = edgeColor
            } else {
                UIView.animate(withDuration: 0.25, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                    self.view.backgroundColor = edgeColor
                }
            }
        }
        updateClearNavigationButtonColor()
    }
        
    private enum SelectModelInitiator {
        case none, pager, coverFlow
    }

    private func selectModel(_ model: ItemModel, animated: Bool, forced: Bool, initiator: SelectModelInitiator) {
        guard selectedModel !== model || forced else { return }

        selectedModel.isSelected = false
        selectedModel = model
        selectedModel.isSelected = true
        setActiveModel(model)

        var notifyCoverFlow = false
        var notifyPager = false
        switch initiator {
        case .coverFlow:
            notifyPager = true
            
        case .pager:
            notifyCoverFlow = true

        case .none:
            notifyCoverFlow = true
        }
        
        if notifyCoverFlow, let headerView {
            // Always snap the cover flow without animation. During pager scrolling, syncCoverFlowWithPager has already moved
            // it to the correct position in real time. An animated cover-flow scroll from a stale position fires
            // visibleItemsInvalidationHandler for every intermediate item, which triggers onCoverFlowDidSelectItem callbacks
            // that drive the pager back to those items the "rollback" bug.
            headerView.selectModel(model)
            
            // During model selecting it may change the visibility so update the state as well
            state.isPreviewHidden = headerView.isPreviewHidden
        }
        
        if notifyPager {
            pager?.animateToIndex(model.index)
        }

        // Always update background + re-subscribe to updates if necessary
        if selectedModelSubscription?.model !== model {
            selectedModelSubscription = .init(model: model, event: .processedImageUpdated, tag: "BG") { [weak self] in
                self?.updateBackground()
            }
        }
        updateBackground()
    }
    
    @objc private func handleInlinePinch(_ gesture: UIPinchGestureRecognizer) {
        headerView?.handleInlinePinch(gesture) { [weak self] in
            self?.updatePinchGestureOwnership()
        }
        updatePinchGestureOwnership()
    }

    private func canBeginInlinePinch(at point: CGPoint) -> Bool {
        guard !state.pageTransition.isTransitioning, let headerView, headerView.canBeginInlineZoom else { return false }
        return NftDetailsHeroLayout.scrolledFrame(headerView.layoutGeometry.expandedImageFrame,
            offsetY: mainScrollView.contentOffset.y).contains(point)
    }

    private func updatePinchGestureOwnership() {
        if isPinchInteractionActive {
            guard gesturesSuspendedForPinch.isEmpty else { return }
            func suspend(in view: UIView) {
                for gesture in view.gestureRecognizers ?? [] where gesture.isEnabled {
                    if gesture is UIPanGestureRecognizer || gesture is UITapGestureRecognizer {
                        gesturesSuspendedForPinch.append(gesture)
                        gesture.isEnabled = false
                    }
                }
                view.subviews.forEach { suspend(in: $0) }
            }
            suspend(in: contentContainer)
        } else {
            let suspended = gesturesSuspendedForPinch
            gesturesSuspendedForPinch.removeAll()
            suspended.forEach { $0.isEnabled = true }
            if !suspended.isEmpty { scrollViewDidScroll(mainScrollView) }
        }
    }

    private func openFullScreenPreview() {
        guard !isPinchInteractionActive else { return }
        headerView?.openFullScreenPreview()
    }

    // MARK: - Item reconcile / removal

    /// Delay before self-dismissing once the list becomes empty, so the user perceives the final
    /// removal / the screen state before it goes away.
    private static let emptyDismissDelay: TimeInterval = 0.4
    private var isAwaitingEmptyDismiss = false

    /// Schedules a one-shot self-dismiss after `emptyDismissDelay`. Safe to call repeatedly.
    private func scheduleEmptyDismiss() {
        guard !isAwaitingEmptyDismiss else { return }
        isAwaitingEmptyDismiss = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.emptyDismissDelay) { [weak self] in
            self?.dismissSelf()
        }
    }

    /// Reconciles the displayed list to `newItems` (insertions, removals and reorders), keyed by NFT
    /// id, preserving image-pipeline state for surviving items. Selection is kept on the current item
    /// when it survives, otherwise it falls back to `preferredSelectedId` and then the first item.
    ///
    /// When the reconciled list is empty the screen schedules a delayed self-dismiss. A no-op reconcile
    /// (same ids in the same order) only refreshes display state (hidden / on-sale badges).
    func reconcileItems(_ newItems: [NftDetailsItem], preferredSelectedId: String? = nil, animated: Bool = true) {
        guard isViewLoaded else { return }

        if newItems.isEmpty {
            _ = headerView?.dismissFullScreen()
            scheduleEmptyDismiss()
            return
        }

        // Fast path: nothing structural changed and no explicit re-selection requested — just refresh badges.
        if preferredSelectedId == nil, manager.models.map(\.id) == newItems.map(\.id) {
            manager.notifyDisplayStateChanged()
            return
        }

        // Leave full-screen preview before mutating the list to avoid an overlay referencing a stale model.
        _ = headerView?.dismissFullScreen()

        let newModels = manager.reconcile(toItems: newItems)
        guard !newModels.isEmpty else {
            scheduleEmptyDismiss()
            return
        }

        // An explicitly requested selection wins (e.g. the last NFT unhidden in a pushed child screen),
        // otherwise keep the current selection if it survived, otherwise fall back to the first item.
        let newSelected: ItemModel = preferredSelectedId.flatMap { id in newModels.first(where: { $0.id == id }) }
            ?? newModels.first(where: { $0.id == selectedModel.id })
            ?? newModels[0]

        if newSelected !== selectedModel {
            selectedModel.isSelected = false
            selectedModel = newSelected
            selectedModel.isSelected = true
        }
        setActiveModel(newSelected)

        if selectedModelSubscription?.model !== newSelected {
            selectedModelSubscription = .init(model: newSelected, event: .processedImageUpdated, tag: "BG") { [weak self] in
                self?.updateBackground()
            }
        }

        // Reset the transition state so it no longer references a removed model.
        state.pageTransition = .staticPage(newSelected)

        pager?.setModels(newModels, newCurrentIndex: newSelected.index, animated: animated)
        headerView?.setModels(newModels, newSelectedModel: newSelected, animated: animated)

        manager.notifyDisplayStateChanged()
        updateBackground()
    }

    /// Duration of the cross-fade that masks the structural removal of the displayed NFT.
    private static let removalCrossfadeDuration: TimeInterval = 0.3

    /// Removes the item with the given id from the shared model list with an animated UI update.
    ///
    /// If the removed item is the currently selected one, selection moves to the next item (or the
    /// previous one if it was last). When the list becomes empty, the screen is dismissed.
    ///
    /// Removing the displayed NFT changes several layers at once — the pager re-centers on the new
    /// page, the cover flow drops its tile, the preview swaps its image and the background recolors.
    /// Doing these directly produces a burst of instant flashes, so we snapshot the current frame,
    /// apply every change underneath it without per-layer animation, and cross-fade the snapshot out
    /// to merge them into one smooth transition.
    func removeItem(id: String, animated: Bool = true) {
        guard let removedModel = manager.models.first(where: { $0.id == id }) else { return }

        // Leave full-screen preview before mutating the list to avoid an overlay referencing a stale model.
        _ = headerView?.dismissFullScreen()

        let wasSelected = (selectedModel.id == id)

        // Pick the replacement selection (next, else previous) using the pre-removal ordering.
        var newSelected: ItemModel? = wasSelected ? nil : selectedModel
        if wasSelected, let idx = manager.models.firstIndex(where: { $0.id == id }) {
            let models = manager.models
            if idx + 1 < models.count {
                newSelected = models[idx + 1]
            } else if idx > 0 {
                newSelected = models[idx - 1]
            }
        }

        // Capture the current frame before mutating, so the abrupt structural updates below happen
        // hidden behind it. Only worthwhile when the list survives (an empty list dismisses instead)
        // and the screen is actually on-screen.
        let shouldCrossfade = animated && view.window != nil && manager.models.count > 1

        // Foreground (cover flow, pager page, preview) cross-fade. `snapshotView` does not capture the
        // Metal-backed background, so its region stays transparent — that part is handled by `bgFade`.
        let crossfadeSnapshot: UIView? = shouldCrossfade ? view.snapshotView(afterScreenUpdates: false) : nil
        // Solid overlay holding the pre-removal background color while the live (Metal) background
        // recolors underneath, so the backdrop dissolves instead of snapping. The background is a flat
        // base color in the expanded/collapsed states from which hiding is triggered.
        let bgFade: UIView? = shouldCrossfade ? UIView() : nil

        if let bgFade {
            bgFade.isUserInteractionEnabled = false
            bgFade.backgroundColor = view.backgroundColor
            bgFade.frame = contentContainer.bounds
            bgFade.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            contentContainer.insertSubview(bgFade, aboveSubview: backgroundView)
        }
        if let crossfadeSnapshot {
            crossfadeSnapshot.isUserInteractionEnabled = false
            crossfadeSnapshot.frame = view.bounds
            view.addSubview(crossfadeSnapshot)
        }

        let newModels = manager.removeModel(id: id)
        guard !newModels.isEmpty, let newSelected else {
            crossfadeSnapshot?.removeFromSuperview()
            bgFade?.removeFromSuperview()
            scheduleEmptyDismiss()
            return
        }

        removedModel.isSelected = false

        if wasSelected {
            selectedModel = newSelected
            selectedModel.isSelected = true
            setActiveModel(newSelected)
            if selectedModelSubscription?.model !== newSelected {
                selectedModelSubscription = .init(model: newSelected, event: .processedImageUpdated, tag: "BG") { [weak self] in
                    self?.updateBackground()
                }
            }
        }

        // Reset the transition state so it no longer references the removed model.
        state.pageTransition = .staticPage(newSelected)

        // When cross-fading, apply the structural updates instantly underneath the overlays; the
        // overlays' fade-out is the only visible animation.
        let childAnimated = !shouldCrossfade && animated
        pager?.removeModel(id: id, newModels: newModels, newCurrentIndex: newSelected.index, animated: childAnimated)
        headerView?.removeModel(id: id, newModels: newModels, newSelectedModel: newSelected, animated: childAnimated)

        updateBackground()

        if shouldCrossfade {
            UIView.animate(
                withDuration: Self.removalCrossfadeDuration,
                delay: 0,
                options: [.curveEaseInOut],
                animations: {
                    crossfadeSnapshot?.alpha = 0
                    bgFade?.alpha = 0
                },
                completion: { _ in
                    crossfadeSnapshot?.removeFromSuperview()
                    bgFade?.removeFromSuperview()
                }
            )
        }
    }

    // MARK: - Actions. Must be overridden in descendants

    private func setActiveModel(_ model: ItemModel) {
        manager.setActiveModel(model)
        nftDetailsDidSetActiveModel(model)
    }

    func nftDetailsDidSetActiveModel(_ model: NftDetailsItemModel) {
    }
    
    func ntfDetailsOnConfigureAction(forModel model: NftDetailsItemModel, action: NftDetailsItemModel.Action) -> NftDetailsActionConfig? {
        fatalError("Override this")
    }
}

extension NftDetailsBaseVC: NftDetailsPagerDelegate {
    func pagerDidSelectModel(_ pager: NftDetailsPagerView, model: ItemModel) {
        selectModel(model, animated: true, forced: false, initiator: .pager)
    }

    func pagerDidScroll(_ pager: NftDetailsPagerView, withProgress progress: CGFloat, fromModel: ItemModel, toModel: ItemModel?) {
        state.pageTransition = .init(leftPage: fromModel, rightPage: toModel, progress: progress)

        // permit/deny header to show preview. After operation update the state.
        let canShowPreview = state.pageTransition.isStatic
        let staticModel: ItemModel?
        if case .staticPage(let model) = state.pageTransition { staticModel = model }
        else { staticModel = nil }
        headerView?.setCanShowPreview(canShowPreview, staticModel: staticModel)
        state.isPreviewHidden = headerView?.isPreviewHidden ?? true

        // Mirror the pager drag to the cover flow so both track each other in real time.
        if pager.isUserDragging {
            headerView?.syncCoverFlowWithPager(progress: progress, currentModel: fromModel)
        }
                
        // Stop offscreen carousel players only in the collapsed presentation.
        // The expanded player supplies live frames throughout a page gesture.
        if state.pageTransition.isTransitioning && !state.isExpanded {
            NotificationCenter.default.post(name: .nftDetailsStopLottieAnimations, object: nil)
        }
        
        updateBackground()
    }
    
    func pagerDidRequestFullScreenPreview() {
        openFullScreenPreview()
    }
}

extension NftDetailsBaseVC: NftDetailsMainHeaderViewDelegate {
    
    func headerCoverFlowDidTapSelectedModel() {
        guard !isPinchInteractionActive else { return }
        pager?.simulateUserScrollToExpand(mainScrollView)
    }

    func headerCoverFlowDidSelectModel(_ model: ItemModel) {
        selectModel(model, animated: true, forced: false, initiator: .coverFlow)
    }
    
    func headerCoverFlowDidScroll(withProgress progress: CGFloat, currentModel: NftDetailsItemModel) {
        pager?.syncPagerWithCoverFlow(progress, currentModel: currentModel)
    }
    
    func headerDidChangePreviewVisibilityInternaly(_ headerView: NftDetailsMainHeaderView) {
        state.isPreviewHidden = headerView.isPreviewHidden
        updateBackground()
    }
}

extension NftDetailsBaseVC: UIScrollViewDelegate {
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        assert(scrollView == mainScrollView)
        guard !isPinchInteractionActive, let pager, let headerView else { return }
                
        // Pager. This may change expanded state here so we handle it first, update the state
        pager.handleVerticalScroll(scrollView)
        state.isExpanded = pager.isExpanded

        // Header. During expansion/collapsing it may change the visibility so update the state as well
        headerView.handleVerticalScroll(scrollView, isExpanded: state.isExpanded )
        state.isPreviewHidden = headerView.isPreviewHidden

        // Background with new state
        updateBackground()
    }

    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        pager?.handleEndDragging(willDecelerate: decelerate)
    }
    
    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        pager?.handleEndDecelerating()
    }
}


extension NftDetailsBaseVC: UIGestureRecognizerDelegate {
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === inlinePinchGesture else { return true }
        return canBeginInlinePinch(at: gestureRecognizer.location(in: contentContainer))
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                  shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // A pan may recognize while the first finger is down. Keep the pinch
        // eligible; the touch guard cancels that pan as soon as the second lands.
        gestureRecognizer === inlinePinchGesture && otherGestureRecognizer is UIPanGestureRecognizer
    }
}

@MainActor
private final class NftNavigationContrastTarget: NSObject {
    weak var owner: NftDetailsBaseVC?
    init(owner: NftDetailsBaseVC) { self.owner = owner }
    @objc func tick() { owner?.updateClearNavigationButtonColor() }
}
