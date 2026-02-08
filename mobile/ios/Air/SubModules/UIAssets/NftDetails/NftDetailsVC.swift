import SwiftUI
import UIKit
import UIComponents
import WalletContext
import WalletCore
import Perception
import SwiftNavigation

@MainActor
public class NftDetailsVC: WViewController, UIScrollViewDelegate {
    
    private let nft: ApiNft
    
    let scrollView = UIScrollView(frame: .zero)
    
    var viewModel: NftDetailsViewModel
    
    var hostingController: UIHostingController<NftDetailsView>? = nil
    private var hostingControllerHeightConstraint: NSLayoutConstraint?
    private var scrollContentHeightConstraint: NSLayoutConstraint?
    private var fullscreenPreviewConstraint: NSLayoutConstraint?
    private var reportedHeight: CGFloat?
    private var isOpenObserver: ObserveToken?
    private var contentHeightObserver: ObserveToken?
    
    var backButton: HostingView? = nil
    
    public init(accountId: String, nft: ApiNft, listContext: NftCollectionFilter) {
        self.nft = nft
        self.viewModel = NftDetailsViewModel(accountId: accountId, isExpanded: false, nft: nft, listContext: listContext, navigationBarInset: 0)
        super.init(nibName: nil, bundle: nil)
        viewModel.viewController = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
    }
    
    private func setupViews() {
        
        if let sheet = self.sheetPresentationController {
            sheet.setValue(true, forKey: "wantsFullScreen")
            sheet.setValue(false, forKey: "allowsInteractiveDismissWhenFullScreen")
        }

        if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
            addCloseNavigationItemIfNeeded()
            configureNavigationItemWithTransparentBackground()
        } else {
            let navigationBar = WNavigationBar(
                title: nft.name ?? "",
                closeIcon: isPresentationModal,
                addBackButton: { [weak self] in self?.goBack() }
            )
            navigationBar.shouldPassTouches = true
            navigationBar.titleLabel?.alpha = 0
            view.addSubview(navigationBar)
            NSLayoutConstraint.activate([
                navigationBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor).withPriority(.defaultHigh),
                navigationBar.leftAnchor.constraint(equalTo: view.leftAnchor),
                navigationBar.rightAnchor.constraint(equalTo: view.rightAnchor)
            ])
            self.navigationBar = navigationBar
            navigationBarProgressiveBlurMinY = 150
            navigationBarProgressiveBlurDelta = 48
        }
        
        scrollView.delegate = self
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.minimumZoomScale = 1.0
        scrollView.alwaysBounceVertical = true
        scrollView.bounces = true
        view.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        scrollView.backgroundColor = .clear
        
        let hostingController = UIHostingController(rootView: NftDetailsView(viewModel: viewModel), ignoreSafeArea: true)
        hostingController.view.backgroundColor = .clear
        addChild(hostingController)
        scrollView.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        
        let hostingControllerHeightConstraint = hostingController.view.heightAnchor.constraint(equalToConstant: 2000)
        self.hostingControllerHeightConstraint = hostingControllerHeightConstraint
        let scrollContentHeightContstraint = scrollView.contentLayoutGuide.heightAnchor.constraint(equalToConstant: 2000)
        self.scrollContentHeightConstraint = scrollContentHeightContstraint
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            
            hostingController.view.centerXAnchor.constraint(equalTo: scrollView.frameLayoutGuide.centerXAnchor),
            hostingController.view.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
//            hostingController.view.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor).withPriority(.defaultHigh),
            hostingControllerHeightConstraint,
            scrollContentHeightContstraint,
        ])
        self.hostingController = hostingController
        
        if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
        } else {
            let backButton = HostingView {
                BackButtonChevron(action: { [weak self] in self?.goBack() })
            }
            backButton.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(backButton)
            NSLayoutConstraint.activate([
                backButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6/*-12*/),
                backButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14)
            ])
            self.backButton = backButton
        }
        
        UIView.performWithoutAnimation {
            updateIsExpanded(viewModel.isExpanded)
            updateFullscreenPreview(viewModel.isFullscreenPreviewOpen)
        }
        
        isOpenObserver = observe { [weak self] in
            guard let self else { return }
            updateFullscreenPreview(viewModel.isFullscreenPreviewOpen)
        }
        
        contentHeightObserver = observe { [weak self] in
            guard let self else { return }
            if viewModel.state == .collapsed {
                reportedHeight = viewModel.contentHeight
            }
        }
                
        updateTheme()
    }
    
    public override func updateTheme() {
        view.backgroundColor = viewModel.isFullscreenPreviewOpen ? .black : WTheme.sheetBackground
    }
    
    
    public override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        viewModel.safeAreaInsets = view.safeAreaInsets
    }
    
    public override func viewWillAppear(_ animated: Bool) {

        if let sheet = self.sheetPresentationController {
            sheet.setValue(false, forKey: "allowsInteractiveDismissWhenFullScreen")
        }
        
        Haptics.prepare(.transition)
        if presentingViewController != nil,
            let presentationConroller = self.navigationController?.presentationController,
            let presentedView = presentationConroller.presentedView,
            let dismissGestureRecognizer = presentedView.gestureRecognizers?.first(where: { $0.description.contains("_UISheetInteractionBackgroundDismissRecognizer") })
        {
            dismissGestureRecognizer.require(toFail: scrollView.panGestureRecognizer)
        }
    }
    
    public override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        UIView.performWithoutAnimation {
            view.setNeedsLayout()
            view.layoutIfNeeded()
        }
    }
    
    public override func viewDidAppear(_ animated: Bool) {
        
        super.viewDidAppear(animated)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.bringNavigationBarToFront()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [self] in
            if let navigationBar {
                navigationBar.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
            }
        }
    }
    
    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        if let sheet = self.sheetPresentationController {
            sheet.setValue(true, forKey: "allowsInteractiveDismissWhenFullScreen")
        }
    }
    
    // MARK: Scroll view delegate
    
    var scrollToTopOnRelease = false
    var allowsOpenMediaViewerForCurrentInteraction = true
    
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let offset = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
        viewModel.y = offset
        
        switch viewModel.state {
        case .collapsed:
            updateNavigationBarProgressiveBlur(offset)
            navigationBar?.titleLabel?.alpha = calculateNavigationBarProgressiveBlurProgress(offset)
        case .expanded, .preview:
            updateNavigationBarProgressiveBlur(0)
            navigationBar?.titleLabel?.alpha = 0
        }
        
        if scrollView.isDecelerating { return }
        
        if abs(offset) < 50 {
            Haptics.prepare(.transition)
        }
        switch viewModel.state {
        case .collapsed:
            if offset < -10 {
                updateIsExpanded(true)
                Haptics.play(.transition)
                allowsOpenMediaViewerForCurrentInteraction = false
//                scrollView.panGestureRecognizer.state = .ended
            }
        case .expanded:
            if offset >= 10 {
                updateIsExpanded(false)
                allowsOpenMediaViewerForCurrentInteraction = false
                Haptics.play(.transition)
            } else if offset < -30 && allowsOpenMediaViewerForCurrentInteraction {
                viewModel.onImageLongTap()
                scrollView.panGestureRecognizer.state = .ended
            }
        case .preview:
            if abs(offset) > 60 && scrollView.zoomScale == 1.0 {
                viewModel.onImageLongTap()
                scrollToTopOnRelease = true
                scrollView.panGestureRecognizer.state = .ended
            }
        }
        if let reportedHeight, let scrollContentHeightConstraint {
            self.reportedHeight = nil
            UIView.performWithoutAnimation {
                scrollContentHeightConstraint.constant = reportedHeight
                self.view.setNeedsLayout()
                self.view.layoutIfNeeded()
            }
        }
    }

    public func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        let topInset = scrollView.adjustedContentInset.top
        let targetY = targetContentOffset.pointee.y + topInset
        let top = CGPoint(x: 0, y: -topInset)
        if scrollToTopOnRelease {
            self.scrollToTopOnRelease = false
            targetContentOffset.pointee = top
        } else {
            switch viewModel.state {
            case .collapsed:
                if targetY > 0 && targetY <= 100 {
                    targetContentOffset.pointee = top
                }
            case .expanded:
                targetContentOffset.pointee = top
            case .preview:
                if scrollView.zoomScale == 1 {
                    targetContentOffset.pointee = top
                }
            }
        }
    }
    
    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            allowsOpenMediaViewerForCurrentInteraction = true
        }
    }
    
    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        allowsOpenMediaViewerForCurrentInteraction = true
    }
    
    public func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        hostingController?.view
    }

    public func scrollViewDidZoom(_ scrollView: UIScrollView) {
        guard let view = hostingController?.view else { return }
        // Center image when smaller than scroll view
        let imageViewSize = view.frame.size
        let scrollSize = scrollView.bounds.size
        let verticalPadding = imageViewSize.height < scrollSize.height ? (scrollSize.height - imageViewSize.height) / 2 : 0
        let horizontalPadding = imageViewSize.width < scrollSize.width ? (scrollSize.width - imageViewSize.width) / 2 : 0
        scrollView.contentInset = UIEdgeInsets(top: verticalPadding, left: horizontalPadding, bottom: verticalPadding, right: horizontalPadding)
    }
    
    // MARK: Expansion handling
    
    func updateIsExpanded(_ isExpanded: Bool) {
        let now = Date()
        viewModel.isAnimatingSince = now
        withAnimation(.spring(duration: 0.3)) {
            viewModel.isExpanded = isExpanded
        }
        UIView.animate(withDuration: 0.3) {
            //            self.setNeedsStatusBarAppearanceUpdate()
            self.navigationBar?.alpha = isExpanded ? 0 : 1
            self.backButton?.alpha = isExpanded ? 1 : 0
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.3))
            if viewModel.isAnimatingSince == now {
                viewModel.isAnimatingSince = nil
            }
        }
    }
    
    // MARK: Fullscreen preview handling
    
    private func updateFullscreenPreview(_ isOpen: Bool) {
        scrollView.maximumZoomScale = isOpen ? 3.0 : 1.0
        if isOpen {
        } else {
            scrollView.setZoomScale(1, animated: false)
        }
        UIView.animate(withDuration: 0.25) {
            self.updateTheme()
        }
        Task { @MainActor [isOpen] in
            try? await Task.sleep(for: .seconds(0.5))
            if viewModel.isFullscreenPreviewOpen == isOpen {
                fullscreenPreviewConstraint?.isActive = isOpen
            }
        }
    }
    
    public override func goBack() {
        if viewModel.isFullscreenPreviewOpen {
            withAnimation(.spring) {
                viewModel.isFullscreenPreviewOpen = false
            }
        } else {
            super.goBack()
        }
    }
}


#if DEBUG
@available(iOS 18, *)
#Preview {
    let _ = (NftStore.configureForPreview())
    let vc = NftDetailsVC(accountId: "0-mainnet", nft: .sampleMtwCard, listContext: .none)
//    let _ = vc.viewModel.isExpanded = false
//    let _ = vc.viewModel.isFullscreenPreviewOpen = true
    previewNc(vc)
}
#endif
