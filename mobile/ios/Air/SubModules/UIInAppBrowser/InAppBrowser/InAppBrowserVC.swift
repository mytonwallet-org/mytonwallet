
import UIKit
import WebKit
import UIComponents
import WalletCore
import WalletContext

private var log = Log("InAppBrowserVC")

@MainActor protocol InAppBrowserDelegate: AnyObject {
    func inAppBrowserTitleChanged(_ browserContainer: InAppBrowserVC)
}

final class InAppBrowserVC: WViewController, InAppBrowserPageDelegate {
    
    weak var delegate: InAppBrowserDelegate?
    var onCloseRequested: (@MainActor () -> Void)?

    private var iconProvider = DappInfoProvider()
    
    init() {
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Load and SetupView Functions
    override func loadView() {
        super.loadView()
        setupViews()
    }
    
    private func setupViews() {
        view.backgroundColor = WTheme.background
        
        let closeButton = if IOS_26_MODE_ENABLED {
            WNavigationBarButton(icon: UIImage(systemName: "xmark"), onPress: { [weak self] in
                self?.closeSheet()
            })
        } else {
            WNavigationBarButton(text: lang("Close"), onPress: { [weak self] in
                self?.closeSheet()
            })
        }
        
        let image = IOS_26_MODE_ENABLED ? UIImage(systemName: "ellipsis") : UIImage(named: "More22", in: AirBundle, with: nil)
        let moreButton = WNavigationBarButton(icon: image, tintColor: WTheme.tint, onPress: nil, menu: makeMenu(), showsMenuAsPrimaryAction: true)
        
        addNavigationBar(navHeight: 60, title: " ", subtitle: "", leadingItem: closeButton, trailingItem: moreButton, tintColor: nil, titleColor: nil, closeIcon: false, addBackButton: { [weak self] in
            self?.goBack()
        }, prefersHardEdge: true)
        if let navigationBar {
            navigationBar.setTitleMenu(makeTitleMenu(for: currentPage?.config.url))
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
        }
        
        bringNavigationBarToFront()
        updateNavigationBar()
        
        updateTheme()
    }
    
    private var pages: [InAppBrowserPageVC] {
        children.compactMap { $0 as? InAppBrowserPageVC }
    }
    
    private var pageConfigs: [InAppBrowserPageConfig] {
        pages.map(\.config)
    }
    
    var currentPage: InAppBrowserPageVC? { pages.first }
    
    var displayTitle: String? {
        displayTitleText
    }
    var dappInfo: DappInfo? {
        iconProvider.getDappInfo(for: currentPage?.config.url)
    }
    private var displayTitleText: String?

    func openPage(config: InAppBrowserPageConfig) {
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
            navigationBar.setTitleMenu(makeTitleMenu(for: page.config.url))
            let pageTitle: String? = page.webView?.title?.nilIfEmpty ?? page.config.title
            let explorerTitle = explorerTitleText(for: page.config.url)
            let title = explorerTitle ?? pageTitle
            displayTitleText = title
            let titleIsNil = title?.nilIfEmpty == nil
            
            UIView.animate(withDuration: 0.15) { [self] in
                
                if titleIsNil && delayTitleChangeToNil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                        self?.updateNavigationBar(delayTitleChangeToNil: false)
                    }
                } else {
                    applyTitle(navigationBar: navigationBar, title: title, explorerTitle: explorerTitle)
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
                if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
                    navigationBar.backButton?.isHidden = true
                    (navigationBar.leadingItem?.view as? WButton)?.setImage(
                        UIImage(systemName: canGoBack ? "chevron.left" : "xmark"),
                        for: .normal
                    )
                    navigationBar.leadingItem?.onPress = canGoBack ? navigationBar.onBackPressed : { [weak self] in
                        self?.closeSheet()
                    }
                } else {
                    navigationBar.backButton?.isHidden = !canGoBack
                    navigationBar.leadingItem?.view.isHidden = canGoBack
                }
                
                delegate?.inAppBrowserTitleChanged(self)
            }
        }
    }
    
    override func updateTheme() {
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
        let copyAction = UIAction(title: lang("Copy Address"),
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

    private func makeTitleMenu(for url: URL?) -> UIMenu? {
        guard let url,
              let tonscanUrl = ExplorerHelper.convertExplorerUrl(url, toExplorerId: "tonscan"),
              let tonviewerUrl = ExplorerHelper.convertExplorerUrl(url, toExplorerId: "tonviewer") else {
            return nil
        }
        let isTonscan = tonscanUrl == url
        let isTonviewer = tonviewerUrl == url
        let tonscanAction = UIAction(title: "Tonscan", state: isTonscan ? .on : .off) { [weak self] _ in
            guard let self, !isTonscan else { return }
            ExplorerHelper.setSelectedExplorerId("tonscan", for: .ton)
            self.navigate(to: tonscanUrl)
        }
        let tonviewerAction = UIAction(title: "Tonviewer", state: isTonviewer ? .on : .off) { [weak self] _ in
            guard let self, !isTonviewer else { return }
            ExplorerHelper.setSelectedExplorerId("tonviewer", for: .ton)
            self.navigate(to: tonviewerUrl)
        }
        return UIMenu(title: "", children: [tonscanAction, tonviewerAction])
    }

    private func explorerTitleText(for url: URL?) -> String? {
        guard let url,
              let tonscanUrl = ExplorerHelper.convertExplorerUrl(url, toExplorerId: "tonscan"),
              let tonviewerUrl = ExplorerHelper.convertExplorerUrl(url, toExplorerId: "tonviewer") else {
            return nil
        }
        if tonscanUrl == url {
            return "Tonscan"
        }
        if tonviewerUrl == url {
            return "Tonviewer"
        }
        return nil
    }

    private func applyTitle(navigationBar: WNavigationBar, title: String?, explorerTitle: String?) {
        guard let titleLabel = navigationBar.titleLabel else { return }
        if let explorerTitle {
            titleLabel.attributedText = makeExplorerTitleText(explorerTitle, label: titleLabel)
        } else {
            titleLabel.attributedText = nil
            titleLabel.text = title
        }
    }

    private func makeExplorerTitleText(_ title: String, label: UILabel) -> NSAttributedString {
        let font = label.font ?? .systemFont(ofSize: 17, weight: .semibold)
        let color = label.textColor ?? WTheme.primaryLabel
        let attr = NSMutableAttributedString(string: title, attributes: [
            .font: font,
            .foregroundColor: color,
        ])
        attr.append(NSAttributedString(string: " "))
        let attachment = NSTextAttachment()
        let image = UIImage.airBundle("HomeTitleArrow").withTintColor(color, renderingMode: .alwaysOriginal)
        attachment.image = image
        let size = image.size
        attachment.bounds = CGRect(x: 0, y: -1, width: size.width, height: size.height)
        attr.append(NSAttributedString(attachment: attachment))
        return attr
    }

    private func navigate(to url: URL) {
        currentPage?.webView?.load(URLRequest(url: url))
    }
    
    override func goBack() {
        currentPage?.webView?.goBack()
    }
    
    func reload() {
        currentPage?.reload()
    }

    private func closeSheet() {
        onCloseRequested?()
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
