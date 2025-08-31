
import UIKit
import WebKit
import UIComponents
import WalletCore
import WalletContext

private var log = Log("InAppBrowserVC")


@MainActor protocol InAppBrowserDelegate: AnyObject {
    func inAppBrowserTitleChanged(_ browserContainer: InAppBrowserVC)
}


public class InAppBrowserVC: WViewController, InAppBrowserPageDelegate {
    
    weak var delegate: InAppBrowserDelegate?

    private var iconProvider = DappInfoProvider()
    
    internal init() {
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
    }
    
    // MARK: - Load and SetupView Functions
    public override func loadView() {
        super.loadView()
        setupViews()
    }
    
    private func setupViews() {
        view.backgroundColor = WTheme.background
        
        let closeButton = WNavigationBarButton(text: lang("Close"), onPress: { [weak self] in
            if let sheet = self?.parent as? WMinimizableSheet {
                sheet.delegate?.minimizableSheetDidClose(sheet)
            }
            self?.presentingViewController?.dismiss(animated: true)
        })
        
        let image = UIImage(named: "More22", in: AirBundle, with: nil)
        let moreButton = WNavigationBarButton(icon: image, tintColor: WTheme.tint, onPress: nil, menu: makeMenu(), showsMenuAsPrimaryAction: true)
        
        let navigationBar = addNavigationBar(navHeight: 60, title: " ", subtitle: "", leadingItem: closeButton, trailingItem: moreButton, tintColor: nil, titleColor: nil, closeIcon: false, addBackButton: { [weak self] in
            self?.goBack()
        })
        navigationBar.showSeparator = true
        if let title = navigationBar.titleLabel, let backButton = navigationBar.backButton, let leading = navigationBar.leadingItem?.view {
            NSLayoutConstraint.activate([
                title.leadingAnchor.constraint(greaterThanOrEqualTo: navigationBar.leadingAnchor, constant: 30),
                title.leadingAnchor.constraint(greaterThanOrEqualTo: backButton.trailingAnchor, constant: 16),
                title.leadingAnchor.constraint(greaterThanOrEqualTo: leading.trailingAnchor, constant: 16),
                
            ])
            title.numberOfLines = 1
            title.alpha = 0
            title.transform = .identity.scaledBy(x: 0.4, y: 0.4)
        }
        
        bringNavigationBarToFront()
        updateNavigationBar()
        
        updateTheme()
    }
    
    private var pages: [InAppBrowserPageVC] {
        children.compactMap { $0 as? InAppBrowserPageVC }
    }
    
    private var pageConfigs: [InAppBrowserPageVC.Config] {
        pages.map(\.config)
    }
    
    var currentPage: InAppBrowserPageVC? { pages.first }
    
    var displayTitle: String? {
        navigationBar?.titleLabel?.text
    }
    var dappInfo: DappInfo? {
        iconProvider.getDappInfo(for: currentPage?.config.url)
    }

    internal func openPage(config: InAppBrowserPageVC.Config) {
        if currentPage?.config.url == config.url {
            return
        }
        for page in pages {
            page.removeFromParent()
        }
        let pageVC = InAppBrowserPageVC(config: config)
        pageVC.delegate = self
        addChild(pageVC)
        view.addSubview(pageVC.view)
        pageVC.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pageVC.view.topAnchor.constraint(equalTo: view.topAnchor),
            pageVC.view.leftAnchor.constraint(equalTo: view.leftAnchor),
            pageVC.view.rightAnchor.constraint(equalTo: view.rightAnchor),
            pageVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        bringNavigationBarToFront()
        pageVC.didMove(toParent: self)
        updateNavigationBar()
    }
    
    func inAppBrowserPageStateChanged(_ browserPageVC: InAppBrowserPageVC) {
        if browserPageVC === currentPage {
            updateNavigationBar()
        }
    }
    
    func updateNavigationBar(delayTitleChangeToNil: Bool = true) {
        if let navigationBar, let page = currentPage {
            let title: String? = page.webView?.title ?? page.config.title
            let titleIsNil = title?.nilIfEmpty == nil
            
            UIView.animate(withDuration: 0.15) { [self] in
                
                if titleIsNil && delayTitleChangeToNil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                        self?.updateNavigationBar(delayTitleChangeToNil: false)
                    }
                } else {
                    navigationBar.titleLabel?.text = title
                    navigationBar.titleLabel?.isHidden = titleIsNil
                    navigationBar.titleLabel?.alpha = titleIsNil ? 0 : 1
                    navigationBar.titleLabel?.transform = titleIsNil ? .identity.scaledBy(x: 0.4, y: 0.4) : .identity
                }
                
                let subtitle: String? = page.config.url.host(percentEncoded: false)
                let subtitleIsNil = subtitle?.nilIfEmpty == nil
                navigationBar.subtitleLabel?.text = subtitle
                navigationBar.subtitleLabel?.isHidden = subtitleIsNil
                navigationBar.subtitleLabel?.alpha = subtitleIsNil ? 0 : 1
                
                let canGoBack = page.webView?.canGoBack == true
                navigationBar.backButton?.isHidden = !canGoBack
                navigationBar.leadingItem?.view.isHidden = canGoBack
                
                delegate?.inAppBrowserTitleChanged(self)
            }
        }
    }
    
    public override func updateTheme() {
    }
    
    private func makeMenu() -> UIMenu {
        let reloadAction = UIAction(title: lang("Reload Page"),
                                    image: UIImage(systemName: "arrow.clockwise")) { [weak self] _ in
            self?.reload()
        }
        let openInSafariAction = UIAction(title: lang("Open in Safari"),
                                          image: UIImage(systemName: "safari")) { [weak self] _ in
            self?.openInSafari()
        }
        let copyAction = UIAction(title: lang("Copy URL"),
                                  image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in
            self?.copy()
        }
        let shareAction = UIAction(title: lang("Share"),
                                   image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
            self?.share()
        }
        let menu = UIMenu(title: "", children: [reloadAction, openInSafariAction, copyAction, shareAction])
        return menu
    }
    
    public override func goBack() {
        currentPage?.webView?.goBack()
    }
    
    internal func reload() {
        currentPage?.reload()
    }
    
    private func openInSafari() {
        currentPage?.openInSafari()
    }
    
    private func copy() {
        currentPage?.copyUrl()
    }

    private func share() {
        currentPage?.share()
    }
}
