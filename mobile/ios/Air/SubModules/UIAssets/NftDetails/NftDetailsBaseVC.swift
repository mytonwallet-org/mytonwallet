import UIKit
import UIComponents

public class NftDetailsBaseVC: UIViewController {
    private let manager: NftDetailsManager
    private var selectedModel: NftDetailsItemModel
    private var selectedModelSubscription: NftDetailsItemModel.Subscription?

    private let backgroundView = NftDetailsBackground.View()
    private let contentContainer = UIView()
    private let mainScrollView = NftDetailMainScrollView()
    private let mainScrollContentView = UIView()
    private var fullscreenOverlay: NftDetailsFullscreenOverlayView?
    private var headerView: NftDetailsMainHeaderView!
    private var pager: NftDetailsPagerView?

    private nonisolated(unsafe) var memoryWarningObserver: NSObjectProtocol?
    private var previousVCBackBarButtonItem: UIBarButtonItem? = nil
    private weak var previousBackItemOwner: UIViewController?

    init(nfts: [NftDetailsItem], selectedIndex: Int) {
        self.manager = NftDetailsManager(items: nfts)
        self.selectedModel = manager.models[selectedIndex]
        
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        memoryWarningObserver.map { NotificationCenter.default.removeObserver($0) }
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .air.sheetBackground

        navigationItem.backButtonDisplayMode = .minimal
        navigationItem.backAction = UIAction { [weak self] _ in
            guard let self else { return }
            
            if let fullscreenOverlay = self.fullscreenOverlay {
                fullscreenOverlay.dismiss()
                return
            }
            
            self.navigationController?.popViewController(animated: true)
        }

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentContainer)

        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(backgroundView)

        headerView = NftDetailsMainHeaderView(models: manager.models, delegate: self)
        headerView.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(headerView)

        mainScrollView.contentViewToRedirect = mainScrollContentView
        mainScrollView.headerViewToRedirect = headerView
        mainScrollView.showsVerticalScrollIndicator = true
        mainScrollView.alwaysBounceVertical = true
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

            headerView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
        ])
        
        selectModel(selectedModel, animated: false, forced: true, initiator: .none)

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
        guard !manager.models.isEmpty else { return }
        manager.releaseImageResources(keepingModelsAround: selectedModel)
    }
    
    public override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()

        let sa = view.safeAreaInsets
        headerView.topSafeAreaInset = sa.top

        var scrollInset = UIEdgeInsets.zero
        scrollInset.bottom = sa.bottom
        mainScrollView.contentInset = scrollInset
        mainScrollView.scrollIndicatorInsets = scrollInset

        UIView.performWithoutAnimation {
            installOrUpdateDetailsPagerIsPossible()
            view.layoutIfNeeded()
        }
    }
    
    public override func viewWillAppear(_ animated: Bool) {
       super.viewWillAppear(animated)
       if let sheet = self.sheetPresentationController {
           sheet.configureAllowsInteractiveDismiss(false)
       }

        if #available(iOS 26, *) {
            
        } else {
            // iOS 17: backButtonDisplayMode alone doesn't suppress the title from the previous VC.
            // Temporarily set an empty backBarButtonItem on the previous VC while this screen is visible.
            if let previousVC = navigationController?.viewControllers.dropLast().last {
                previousBackItemOwner = previousVC
                previousVCBackBarButtonItem = previousVC.navigationItem.backBarButtonItem
                previousVC.navigationItem.backBarButtonItem = UIBarButtonItem(title: "", style: .plain, target: nil, action: nil)
            }
        }
    }

    public override func viewWillDisappear(_ animated: Bool) {
       super.viewWillDisappear(animated)
       if let sheet = self.sheetPresentationController {
           sheet.configureAllowsInteractiveDismiss(true)
       }

        if #available(iOS 26, *) {
            
        } else {
            previousBackItemOwner?.navigationItem.backBarButtonItem = previousVCBackBarButtonItem
            previousBackItemOwner = nil
            previousVCBackBarButtonItem = nil
        }
    }
    
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        installOrUpdateDetailsPagerIsPossible()
    }

    public override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animateAlongsideTransition(in: view) { [weak self] _ in
            self?.installOrUpdateDetailsPagerIsPossible()
        } completion: { [weak self] _ in
            self?.installOrUpdateDetailsPagerIsPossible()
        }
    }

    private func installOrUpdateDetailsPagerIsPossible() {
        guard isViewLoaded, !manager.models.isEmpty else { return }

        contentContainer.layoutIfNeeded()
        let pageWidth = contentContainer.bounds.width
        guard pageWidth > 0 else { return }

        let layoutGeometry = NftDetailsPagerView.LayoutGeometry(
            topSafeAreaInset: view.safeAreaInsets.top,
            collapsedAreaHeight: headerView.collapsedHeight,
            pageWidth: pageWidth
        )
        
        manager.targetWidth = pageWidth

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
            let idx = manager.models.findIndexById(selectedModel.id) ?? 0
            let newPager = NftDetailsPagerView(
                models: manager.models,
                currentIndex: idx,
                layoutGeometry: layoutGeometry,
                delegate: self,
                hideStaticPreview: backgroundView.transition.shouldBakeInImageIntoBackground,
                initiallyExpanded: initiallyExpanded
            )
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
    
    private func getBackgroundPageModel(forModel model: NftDetailsItemModel) -> NftDetailsBackground.PageModel {
        var backgroundPattern: CIImage?
        var image: CIImage?
        if case .loaded(let processed) = model.processedImageState {
            backgroundPattern = processed.backgroundPattern
            image = processed.previewImage?.cgImage.flatMap { CIImage(cgImage: $0) }
        }
        return .init(background: backgroundPattern, image: image, tag: model.name)
    }

    private func updateBackground(fromModel: NftDetailsItemModel, toModel: NftDetailsItemModel?, sideProgress: CGFloat) {
        let model = NftDetailsBackground.Model(
            leftPage: getBackgroundPageModel(forModel: fromModel),
            rightPage: toModel.flatMap { getBackgroundPageModel(forModel: $0) },
            sideProgress: sideProgress,
        )
        backgroundView.setModel(model)
    }

    
    private enum SelectModelInitiator {
        case none, pager, coverFlow
    }

    private func selectModel(_ model: NftDetailsItemModel, animated: Bool, forced: Bool, initiator: SelectModelInitiator) {
        guard selectedModel !== model || forced else { return }

        selectedModel.isSelected = false
        selectedModel = model
        selectedModel.isSelected = true

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
        
        if notifyCoverFlow {
            // Always snap the cover flow without animation. During pager scrolling, syncCoverFlowWithPager has already moved
            // it to the correct position in real time. An animated cover-flow scroll from a stale position fires
            // visibleItemsInvalidationHandler for every intermediate item, which triggers onCoverFlowDidSelectItem callbacks
            // that drive the pager back to those items the "rollback" bug.
            headerView.selectCoverFlowModel(model, animated: false, forced: forced)
        }
        
        if notifyPager {
            if let idx = manager.models.findIndexById(model.id) {
                pager?.animateToIndex(idx)
            }
        }

        // Update background when processedImageState changes for this model (s
        installProcessedImageObserver(for: model)
        updateBackground(fromModel: model, toModel: nil, sideProgress: 0)
    }

    private func installProcessedImageObserver(for model: NftDetailsItemModel) {
        guard selectedModelSubscription?.model !== model else { return }
        
        selectedModelSubscription = .init(model: model, event: .processedImageUpdated, tag: "BG") { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.selectedModel === model else { return }
                self.updateBackground(fromModel: model, toModel: nil, sideProgress: 0)
            }
        }
    }
    
    private func openFullScreenPreview(forModel model: NftDetailsItemModel, fromView view: UIView) {
        
        guard fullscreenOverlay == nil else { return }
        let overlay = NftDetailsFullscreenOverlayView(
            models: manager.models,
            currentIndex: manager.models.findIndexById(model.id) ?? 0
        )
        overlay.onDismiss = { [weak self] in
            self?.fullscreenOverlay = nil
        }
        fullscreenOverlay = overlay
        overlay.presentWithFlyingTransition(from: view, in: contentContainer)
    }

    // MARK: - Actions. Must be overridden in descendants
    
    func nftDetailsOnShowCollection(forModel model: NftDetailsItemModel) { fatalError("Override this") }
    
    func nftDetailsOnRenewDomain(forModel model: NftDetailsItemModel) { fatalError("Override this") }
    
    func ntfDetailsOnConfigureToolbarButton(forModel model: NftDetailsItemModel, action: NftDetailsItemModel.Action) -> NftDetailsToolbarButtonConfig? {
        fatalError("Override this")
    }
}

extension NftDetailsBaseVC: NftDetailsPagerDelegate {
    func pagerDidSelectModel(_ pager: NftDetailsPagerView, model: NftDetailsItemModel) {
        selectModel(model, animated: true, forced: false, initiator: .pager)
    }

    func pagerDidScroll(_ pager: NftDetailsPagerView, withProgress progress: CGFloat, fromModel: NftDetailsItemModel, toModel: NftDetailsItemModel?) {
        updateBackground(fromModel: fromModel, toModel: toModel, sideProgress: progress)

        // Mirror the pager drag to the cover flow so both track each other in real time.
        if pager.isUserDragging {
            headerView.syncCoverFlowWithPager(progress: progress, currentItemId: fromModel.id)
        }
    }
    
    func pagerRequestSelectedCoverFlowItemFrame() -> CGRect {
        headerView.selectedCoverFlowTileFrame()
    }
    
    func pagerDidChangeExpansionState(_ pager: NftDetailsPagerView) {
        headerView.setActive(!pager.isExpanded)
        backgroundView.isExpanded = pager.isExpanded
    }

    func pagerDidRequestFullScreenPreview(forModel model: NftDetailsItemModel, view: UIView) {
        openFullScreenPreview(forModel: model, fromView: view)
    }
    
    func pagerWantsToSwipeBackTheFirstPage() {
        navigationController?.popViewController(animated: true)
    }
}

extension NftDetailsBaseVC: NftDetailsMainHeaderViewDelegate {
    func headerCoverFlowDidTapModel(_ model: NftDetailsItemModel, view: UIView, longTap: Bool) {
        if longTap {
            openFullScreenPreview(forModel: model, fromView: view)
        } else {
            pager?.simulateUserScrollToExpand(mainScrollView)
        }
    }

    func headerCoverFlowDidSelectModel(_ model: NftDetailsItemModel) {
        selectModel(model, animated: true, forced: false, initiator: .coverFlow)
    }
    
    func headerCoverFlowDidScroll(withProgress progress: CGFloat, currentModelId: String) {
        pager?.syncPagerWithCoverFlow(progress, currentModelId: currentModelId)
    }
}

extension NftDetailsBaseVC: UIScrollViewDelegate {
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        assert(scrollView == mainScrollView)
        guard let pager else { return }

        // Pager. This may change expanded state here so we handle it first
        pager.handleVerticalScroll(scrollView)

        // Coverflow
        let offsetY = scrollView.contentOffset.y
        let y = pager.isExpanded ? 0.0 : max(0, offsetY)
        headerView.transform = CGAffineTransform(translationX: 0, y: -y)
        headerView.alpha = pager.isExpanded ? 0 : 1

        // Background
        backgroundView.isExpanded = pager.isExpanded
    }

    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        pager?.handleEndDragging(willDecelerate: decelerate)
    }
    
    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        pager?.handleEndDecelerating()
    }
}

