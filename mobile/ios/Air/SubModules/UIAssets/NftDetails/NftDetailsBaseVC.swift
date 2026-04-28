import UIKit
import UIComponents

public class NftDetailsBaseVC: UIViewController {
    let manager: NftDetailsManager
    
    private var selectedModel: ItemModel
    private var selectedModelSubscription: ItemModel.Subscription?

    private let backgroundView = Background.View()
    private let contentContainer = UIView()
    private let mainScrollView = NftDetailMainScrollView()
    private let mainScrollContentView = UIView()
    private var headerView: NftDetailsMainHeaderView?
    private var pager: NftDetailsPagerView?
    
    typealias Background = NftDetailsBackground
    typealias ItemModel = NftDetailsItemModel

    private nonisolated(unsafe) var memoryWarningObserver: NSObjectProtocol?
    private var previousVCBackBarButtonItem: UIBarButtonItem? = nil
    private weak var previousBackItemOwner: UIViewController?
    
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

    init(nfts: [NftDetailsItem], selectedIndex: Int) {
        self.manager = NftDetailsManager(items: nfts)
        self.selectedModel = manager.models[selectedIndex]
        self.state = State(
            isExpanded: false,
            pageTransition: .staticPage(selectedModel),
            isPreviewHidden: true
        )
        
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
            
            if let headerView, headerView.dismissFullScreen() {
                return
            }
            
            self.navigationController?.popViewController(animated: true)
        }

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentContainer)

        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(backgroundView)

        mainScrollView.contentViewToRedirect = mainScrollContentView
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
       manager.saveColorCacheIfNeeded()
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
        guard pageWidth > 0 else { return }

        if manager.targetWidth != pageWidth {
            _ = headerView?.dismissFullScreen()
        }
        
        manager.targetWidth = pageWidth
        
        let collapsedHeight = 165.0
        installOrUpdateHeader(pageWidth: pageWidth, collapsedHeight: collapsedHeight)
        installOrUpdatePager(pageWidth: pageWidth, collapsedHeight: collapsedHeight)
    }
    
    private func installOrUpdateHeader(pageWidth: CGFloat, collapsedHeight: CGFloat) {
        assert(pageWidth > 0 && isViewLoaded && collapsedHeight > 0)

        let layoutGeometry = NftDetailsMainHeaderView.LayoutGeometry(
            topSafeAreaInset: view.safeAreaInsets.top,
            collapsedAreaHeight: collapsedHeight,
            pageWidth: pageWidth
        )

        guard headerView?.layoutGeometry != layoutGeometry else { return }

        if let headerView {
            headerView.layoutGeometry = layoutGeometry
        } else {
            let newHeader = NftDetailsMainHeaderView(
                frame: contentContainer.bounds,
                models: manager.models,
                selectedModel: selectedModel,
                delegate: self,
                layoutGeometry: layoutGeometry,
                coverFlowThumbnailDownloader: manager.coverFlowThumbnailDownloader,
                colorCache: manager.colorCache
            )
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
        }
    }

    private func installOrUpdatePager(pageWidth: CGFloat, collapsedHeight: CGFloat) {
        assert(pageWidth > 0 && isViewLoaded && collapsedHeight > 0)
        
        let layoutGeometry = NftDetailsPagerView.LayoutGeometry(
            topSafeAreaInset: view.safeAreaInsets.top,
            collapsedAreaHeight: collapsedHeight,
            pageWidth: pageWidth
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
            let idx = manager.models.findIndexById(selectedModel.id) ?? 0
            let newPager = NftDetailsPagerView(
                models: manager.models,
                currentIndex: idx,
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
        let perf = NftDetailsPerformance.beginMeasure("vc_updateBackground")
        defer { NftDetailsPerformance.endMeasure(perf) }

        func getPageModel(forModel model: ItemModel) -> Background.PageModel {
            var backgroundPattern: CIImage?
            var image: CIImage?
            if case .loaded(let processed) = model.processedImageState {
                backgroundPattern = processed.backgroundCIImage
                image = processed.previewCIImage
            }
            return .init(background: backgroundPattern, image: image, tag: model.name)
        }
        
        let pageState: Background.PageState
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

        let model = Background.Model(
            pageState: pageState,
            isExpanded: state.isExpanded,
            shouldShowPreview: state.isPreviewHidden && state.isExpanded
        )
        backgroundView.setModel(model)
    }
        
    private enum SelectModelInitiator {
        case none, pager, coverFlow
    }

    private func selectModel(_ model: ItemModel, animated: Bool, forced: Bool, initiator: SelectModelInitiator) {
        guard selectedModel !== model || forced else { return }

        selectedModel.isSelected = false
        selectedModel = model
        selectedModel.isSelected = true
        manager.setActiveModel(model)

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
            if let idx = manager.models.findIndexById(model.id) {
                pager?.animateToIndex(idx)
            }
        }

        // Always update background + re-subscribe to updates if necessary
        if selectedModelSubscription?.model !== model {
            selectedModelSubscription = .init(model: model, event: .processedImageUpdated, tag: "BG") { [weak self] in
                self?.updateBackground()
            }
        }
        updateBackground()
    }
    
    private func openFullScreenPreview() {
        headerView?.openFullScreenPreview()
    }

    // MARK: - Actions. Must be overridden in descendants
    
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

        // permit/deny header to show preview. After operation update the sate
        let canShowPreview = state.pageTransition.isStatic
        headerView?.setCanShowPreview(canShowPreview)
        state.isPreviewHidden = headerView?.isPreviewHidden ?? true

        // Mirror the pager drag to the cover flow so both track each other in real time.
        if pager.isUserDragging {
            headerView?.syncCoverFlowWithPager(progress: progress, currentItemId: fromModel.id)
        }
        
        NftDetailsPerformance.markPagerScrollEvent()
        
        // To reduce frame dropping cancels animations on any transitions.
        if state.pageTransition.isTransitioning {
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
        pager?.simulateUserScrollToExpand(mainScrollView)
    }

    func headerCoverFlowDidSelectModel(_ model: ItemModel) {
        selectModel(model, animated: true, forced: false, initiator: .coverFlow)
    }
    
    func headerCoverFlowDidScroll(withProgress progress: CGFloat, currentModelId: String) {
        pager?.syncPagerWithCoverFlow(progress, currentModelId: currentModelId)
    }
    
    func headerDidChangePreviewVisibilityInternaly(_ headerView: NftDetailsMainHeaderView) {
        state.isPreviewHidden = headerView.isPreviewHidden
        updateBackground()
    }
}

extension NftDetailsBaseVC: UIScrollViewDelegate {
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        assert(scrollView == mainScrollView)
        guard let pager, let headerView else { return }
                
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
