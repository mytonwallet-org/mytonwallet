
import UIComponents
import UIKit
import WalletContext
import WalletCore


protocol WMinimizableSheetDelegate: AnyObject {
    func minimizableSheetDidExpand(_ sheet: WMinimizableSheet)
    func minimizableSheetDidMinimize(_ sheet: WMinimizableSheet)
    func minimizableSheetWillDismiss(_ sheet: WMinimizableSheet)
    func minimizableSheetDidDismiss(_ sheet: WMinimizableSheet)
    func minimizableSheetDidClose(_ sheet: WMinimizableSheet)
}


public class WMinimizableSheet: WViewController {
    
    private var minimizingDisabled: Bool = false
    private var startMinimized: Bool = false
    
    var browser: InAppBrowserVC?

    weak var delegate: WMinimizableSheetDelegate?
    
    var blurView: WBlurView!
    var contentView: MinimizedSheetView!

    init(browser: InAppBrowserVC, startMinimized: Bool = false) {
        self.browser = browser
        self.startMinimized = startMinimized
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
    }
    
    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupMinimizingBehavior()
        setupViews()
        if let browser {
            addBrowser(browser)
            if startMinimized {
                browser.view.alpha = 0
            }
        }
    }

    func setupViews() {
        view.backgroundColor = WTheme.browserOpaqueBar
        blurView = WBlurView()
        view.addSubview(blurView)
        blurView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: view.topAnchor),
            blurView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            blurView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        
        self.contentView = MinimizedSheetView(
            title: browser?.displayTitle,
            iconUrl: nil,
            titleTapAction: { [weak self] in
                self?.expandTouchTargetPressed()
            },
            closeAction: { [weak self] in
                self?.closeButtonPressed()
            }
        )
        view.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: view.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentView.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    func addBrowser(_ browser: InAppBrowserVC) {
        self.browser = browser
        browser.delegate = self
        addChild(browser)
        view.addSubview(browser.view)
        browser.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            browser.view.topAnchor.constraint(equalTo: view.topAnchor),
            browser.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            browser.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            browser.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        browser.didMove(toParent: self)
        inAppBrowserTitleChanged(browser)
    }

    func removeBrowser() -> InAppBrowserVC? {
        let browser = self.browser
        self.browser = nil
        if let browser {
            UIView.animate(withDuration: 0.3) {
                browser.view.alpha = 0
            } completion: { _ in
                browser.willMove(toParent: nil)
                browser.view.removeFromSuperview()
                browser.view.alpha = 1
                browser.removeFromParent()
            }
        }
        return browser
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !(presentingViewController is UITabBarController) {
            minimizingDisabled = true
            sheetPresentationController?.detents = [.large()]
        }
    }
    
    func closeButtonPressed() {
        delegate?.minimizableSheetDidClose(self)
        presentingViewController?.dismiss(animated: true)
        WalletCoreData.notify(event: .minimizedSheetChanged(.closed))
    }

    @objc func expandTouchTargetPressed() {
        expand()
    }

    func expand() {
        if let sheet = sheetPresentationController {
            sheet.animateChanges { 
                sheet.selectedDetentIdentifier = .large
                self.sheetPresentationControllerDidChangeSelectedDetentIdentifier(sheet)
            }
        }
        WalletCoreData.notify(event: .minimizedSheetChanged(.expanded))
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        if isBeingDismissed {
            delegate?.minimizableSheetWillDismiss(self)
        }
        super.viewWillDisappear(animated)
    }
    
    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        WalletCoreData.notify(event: .minimizedSheetChanged(.closed))
    }
}


extension WMinimizableSheet: UISheetPresentationControllerDelegate {
    
    public var isMinimized: Bool { sheetPresentationController?.selectedDetentIdentifier == .minimized }
    public var isExpanded: Bool { sheetPresentationController?.selectedDetentIdentifier == .large }
    
    func setupMinimizingBehavior() {
        if let sheet = sheetPresentationController {
            let detent: UISheetPresentationController.Detent.Identifier = startMinimized ? .minimized : .large
            
            let detentValue: CGFloat = if #available(iOS 26, *) {
                44 + 34
            } else {
                44
            }
            sheet.preferredCornerRadius = startMinimized ? 12 : nil
            sheet.detents = [.large(), .custom(identifier: .minimized, resolver: { _ in detentValue })]
            sheet.selectedDetentIdentifier  = detent
            sheet.largestUndimmedDetentIdentifier = .minimized
            sheet.delegate = self
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                sheet.selectedDetentIdentifier = detent
                self.sheetPresentationControllerDidChangeSelectedDetentIdentifier(sheet)
            }
        }
    }
    
    public func sheetPresentationControllerDidChangeSelectedDetentIdentifier(_ sheetPresentationController: UISheetPresentationController) {
        let isMinimized = sheetPresentationController.selectedDetentIdentifier == .minimized
        let cornerRadius: CGFloat? = isMinimized ? 12.0 : nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if sheetPresentationController.preferredCornerRadius != cornerRadius {
                sheetPresentationController.animateChanges {
                    sheetPresentationController.preferredCornerRadius = cornerRadius
                }
            }
        }
        WalletCoreData.notify(event: .minimizedSheetChanged(isMinimized ? .minimized : .expanded))
        if isMinimized {
            delegate?.minimizableSheetDidMinimize(self)
        } else {
            delegate?.minimizableSheetDidExpand(self)
        }
    }
    
    public func presentationControllerWillDismiss(_ presentationController: UIPresentationController) {
        delegate?.minimizableSheetWillDismiss(self)
        WalletCoreData.notify(event: .minimizedSheetChanged(.closed))
        transitionCoordinator?.notifyWhenInteractionChanges({ [weak self] context in
            if context.isCancelled, let self, let sheetPresentationController {
                let isMinimized = sheetPresentationController.selectedDetentIdentifier == .minimized
                WalletCoreData.notify(event: .minimizedSheetChanged(isMinimized ? .minimized : .expanded))
            }
        })
    }
    
    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        delegate?.minimizableSheetDidDismiss(self)
        WalletCoreData.notify(event: .minimizedSheetChanged(.closed))
    }
}


extension WMinimizableSheet: InAppBrowserDelegate {
    func inAppBrowserTitleChanged(_ browserContainer: InAppBrowserVC) {
        let dappInfo = browserContainer.dappInfo
        contentView.viewModel.title = dappInfo?.shortTitle ?? browserContainer.displayTitle
        contentView.viewModel.iconUrl = dappInfo?.iconUrl
    }
}
