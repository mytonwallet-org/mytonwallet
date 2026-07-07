
import UIKit
import WebKit
import UIComponents
import WalletCore
import WalletContext

private let blankPageURL = URL(string: "about:blank")!

@MainActor protocol InAppBrowserDelegate: AnyObject {
    func inAppBrowserTitleChanged(_ browserContainer: InAppBrowserVC)
}

final class InAppBrowserVC: WViewController, InAppBrowserPageDelegate {
    override var hideNavigationBar: Bool { true }

    weak var delegate: InAppBrowserDelegate?
    var onCloseRequested: (@MainActor () -> Void)?

    private let iconProvider = DappInfoProvider()
    private lazy var navigationBar = makeNavigationBar()
    private lazy var tabSwitcherButton = WNavigationBarButton(
        icon: UIImage(systemName: "square.on.square"),
        tintColor: IOS_26_MODE_ENABLED ? nil : .tintColor
    ) { [weak self] in
        self?.toggleTabSwitcher()
    }
    private var pages: [InAppBrowserPageVC] = []
    private var selectedPageID: UUID?
    private var tabSwitcherVC: InAppBrowserTabSwitcherVC?

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
        view.backgroundColor = .air.background
        view.addSubview(navigationBar)
        NSLayoutConstraint.activate([
            navigationBar.topAnchor.constraint(equalTo: view.topAnchor),
            navigationBar.leftAnchor.constraint(equalTo: view.leftAnchor),
            navigationBar.rightAnchor.constraint(equalTo: view.rightAnchor),
            navigationBar.titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: navigationBar.leadingAnchor, constant: 30),
            navigationBar.titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: navigationBar.backButton.trailingAnchor, constant: 16),
            navigationBar.titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: navigationBar.leadingButton.view.trailingAnchor, constant: 16),
        ])
        navigationBar.titleLabel.numberOfLines = 1
        navigationBar.titleLabel.alpha = 0
        navigationBar.titleLabel.transform = .identity.scaledBy(x: 0.4, y: 0.4)

        updateNavigationBar()

    }

    private func makeNavigationBar() -> WNavigationBar {
        let closeButton = if IOS_26_MODE_ENABLED {
            WNavigationBarButton(icon: UIImage(systemName: "xmark"), onPress: { [weak self] in
                self?.closeCurrentTabOrSheet()
            })
        } else {
            WNavigationBarButton(text: lang("Close"), onPress: { [weak self] in
                self?.closeCurrentTabOrSheet()
            })
        }

        let image = IOS_26_MODE_ENABLED ? UIImage(systemName: "ellipsis") : UIImage(named: "More22", in: AirBundle, with: nil)
        let moreButton = WNavigationBarButton(icon: image, tintColor: IOS_26_MODE_ENABLED ? nil : .tintColor, menu: makeMenu())
        return WNavigationBar(leadingButton: closeButton, trailingButtons: [tabSwitcherButton, moreButton]) { [weak self] in
            self?.goBack()
        }
    }

    var currentPage: InAppBrowserPageVC? {
        if let selectedPageID, let selectedPage = pages.first(where: { $0.id == selectedPageID }) {
            return selectedPage
        }
        return pages.first
    }

    var displayTitle: String? {
        displayTitleText
    }
    var dappInfo: DappInfo? {
        iconProvider.getDappInfo(for: currentPage?.state.url)
    }
    private var displayTitleText: String?

    func openPage(config: InAppBrowserPageConfig) {
        if pages.count == 1, currentPage?.state.url == config.url {
            return
        }
        hideTabSwitcher(animated: false)
        removeAllPages()
        addPage(config: config, selecting: true)
    }

    @discardableResult
    private func addPage(
        config: InAppBrowserPageConfig,
        webViewConfiguration: WKWebViewConfiguration? = nil,
        loadsInitialRequest: Bool = true,
        selecting: Bool
    ) -> InAppBrowserPageVC {
        let pageVC = InAppBrowserPageVC(
            config: config,
            webViewConfiguration: webViewConfiguration,
            loadsInitialRequest: loadsInitialRequest
        )
        pageVC.delegate = self
        pages.append(pageVC)
        addChild(pageVC)
        view.insertSubview(pageVC.view, belowSubview: navigationBar)
        pageVC.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pageVC.view.topAnchor.constraint(equalTo: view.topAnchor),
            pageVC.view.leftAnchor.constraint(equalTo: view.leftAnchor),
            pageVC.view.rightAnchor.constraint(equalTo: view.rightAnchor),
            pageVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        bringOverlaysToFront()
        pageVC.didMove(toParent: self)
        if selecting {
            selectPage(pageVC, hidesTabSwitcher: false)
        } else {
            pageVC.view.isHidden = true
        }
        updateTabSwitcher(animated: true)
        updateNavigationBar()
        return pageVC
    }

    private func selectPage(
        _ page: InAppBrowserPageVC,
        hidesTabSwitcher: Bool = true,
        capturesCurrentPreview: Bool = true
    ) {
        guard pages.contains(where: { $0 === page }) else { return }
        if capturesCurrentPreview, currentPage !== page {
            currentPage?.capturePreview()
        }
        selectedPageID = page.id
        for existingPage in pages {
            existingPage.view.isHidden = existingPage !== page
        }
        bringOverlaysToFront()
        if hidesTabSwitcher {
            hideTabSwitcher(animated: true)
        }
        updateTabSwitcher(animated: false)
        updateNavigationBar()
    }

    private func selectPage(id: UUID) {
        guard let page = pages.first(where: { $0.id == id }) else { return }
        selectPage(page)
    }

    private func closePage(id: UUID) {
        guard let page = pages.first(where: { $0.id == id }) else { return }
        closePage(page)
    }

    private func closePage(_ page: InAppBrowserPageVC) {
        let wasCurrentPage = page === currentPage
        guard let index = pages.firstIndex(where: { $0 === page }) else { return }
        page.willMove(toParent: nil)
        page.view.removeFromSuperview()
        page.removeFromParent()
        pages.remove(at: index)

        if pages.isEmpty {
            hideTabSwitcher(animated: false)
            updateNavigationBar()
            closeSheet()
            return
        }

        if wasCurrentPage {
            let nextIndex = min(index, pages.count - 1)
            selectPage(pages[nextIndex], hidesTabSwitcher: false, capturesCurrentPreview: false)
        }
        updateTabSwitcher(animated: true)
        updateNavigationBar()
    }

    private func removeAllPages() {
        for page in pages {
            page.willMove(toParent: nil)
            page.view.removeFromSuperview()
            page.removeFromParent()
        }
        pages.removeAll()
        selectedPageID = nil
    }

    func inAppBrowserPageStateChanged(_ browserPageVC: InAppBrowserPageVC) {
        if browserPageVC === currentPage {
            updateNavigationBar()
        }
        updateTabSwitcher(animated: true)
    }

    func inAppBrowserPage(_ browserPageVC: InAppBrowserPageVC, wantsOpenNewPageWith config: InAppBrowserPageConfig) {
        addPage(config: config, selecting: true)
    }

    func inAppBrowserPage(
        _ browserPageVC: InAppBrowserPageVC,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction
    ) -> WKWebView? {
        let url = navigationAction.request.url ?? blankPageURL
        let page = addPage(
            config: browserPageVC.childConfig(url: url),
            webViewConfiguration: configuration,
            loadsInitialRequest: false,
            selecting: true
        )
        return page.webViewForWebKitPopup()
    }

    func inAppBrowserPageWantsClose(_ browserPageVC: InAppBrowserPageVC) {
        closePage(browserPageVC)
    }

    private func bringOverlaysToFront() {
        if let tabSwitcherVC {
            view.bringSubviewToFront(tabSwitcherVC.view)
        }
        view.bringSubviewToFront(navigationBar)
    }

    func updateNavigationBar(delayTitleChangeToNil: Bool = true) {
        updateTabSwitcherButton()
        guard let page = currentPage else {
            delegate?.inAppBrowserTitleChanged(self)
            return
        }
        let pageState = page.state
        navigationBar.setTitleMenu(makeTitleMenu(for: pageState.url))
        let pageTitle = pageState.title?.nilIfEmpty
        let explorerTitle = explorerTitleText(for: pageState.url)
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
                navigationBar.titleLabel.isHidden = titleIsNil
                navigationBar.titleLabel.alpha = titleIsNil ? 0 : 1
                navigationBar.titleLabel.transform = titleIsNil ? .identity.scaledBy(x: 0.4, y: 0.4) : .identity
            }

            let host = pageState.url.host(percentEncoded: false)
            let subtitle: String? = pageState.url.isSubproject ? nil : host
            let subtitleIsNil = subtitle?.nilIfEmpty == nil
            navigationBar.subtitleLabel.text = subtitle
            navigationBar.subtitleLabel.isHidden = subtitleIsNil
            navigationBar.subtitleLabel.alpha = subtitleIsNil ? 0 : 1

            let canGoBack = pageState.canGoBack
            if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
                navigationBar.backButton.isHidden = true
                navigationBar.leadingButton.setImage(UIImage(systemName: canGoBack ? "chevron.left" : "xmark"))
                navigationBar.leadingButton.onPress = canGoBack ? { [weak self] in
                    self?.goBack()
                } : { [weak self] in
                    self?.closeCurrentTabOrSheet()
                }
            } else {
                navigationBar.backButton.isHidden = !canGoBack
                navigationBar.leadingButton.view.isHidden = canGoBack
            }

            delegate?.inAppBrowserTitleChanged(self)
        }
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
        let titleLabel = navigationBar.titleLabel
        if let explorerTitle {
            titleLabel.attributedText = makeExplorerTitleText(explorerTitle, label: titleLabel)
        } else {
            titleLabel.attributedText = nil
            titleLabel.text = title
        }
    }

    private func makeExplorerTitleText(_ title: String, label: UILabel) -> NSAttributedString {
        let font = label.font ?? .systemFont(ofSize: 17, weight: .semibold)
        let color = label.textColor ?? UIColor.label
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
        hideTabSwitcher(animated: true)
        currentPage?.navigate(to: url)
    }

    override func goBack() {
        if tabSwitcherVC != nil {
            hideTabSwitcher(animated: true)
            return
        }
        currentPage?.goBackInHistory()
    }

    func reload() {
        currentPage?.reload()
    }

    @discardableResult
    func emitDappDisconnectEvent(origin: String) -> Bool {
        var didEmit = false
        for page in pages where page.hasOrigin(origin) {
            didEmit = true
            page.emitDappDisconnectEvent()
        }
        return didEmit
    }

    private func toggleTabSwitcher() {
        if tabSwitcherVC == nil {
            showTabSwitcher()
        } else {
            hideTabSwitcher(animated: true)
        }
    }

    private func updateTabSwitcherButton() {
        let shouldShow = pages.count > 1
        tabSwitcherButton.view.isHidden = !shouldShow
        tabSwitcherButton.setImage(Self.tabSwitcherImage(tabCount: pages.count))
        tabSwitcherButton.view.accessibilityLabel = lang("$iab_tabs_count", arg1: pages.count)
        if !shouldShow {
            hideTabSwitcher(animated: false)
        }
    }

    private static func tabSwitcherImage(tabCount: Int) -> UIImage? {
        let imageName = (1...50).contains(tabCount) ? "\(tabCount).square" : "dot.square"
        return UIImage(systemName: imageName)
    }

    private func showTabSwitcher() {
        guard tabSwitcherVC == nil else { return }
        currentPage?.capturePreview { [weak self] in
            self?.updateTabSwitcher(animated: true)
        }
        let tabSwitcherVC = InAppBrowserTabSwitcherVC()
        tabSwitcherVC.delegate = self
        self.tabSwitcherVC = tabSwitcherVC
        addChild(tabSwitcherVC)
        view.insertSubview(tabSwitcherVC.view, belowSubview: navigationBar)
        tabSwitcherVC.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tabSwitcherVC.view.topAnchor.constraint(equalTo: navigationBar.bottomAnchor),
            tabSwitcherVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabSwitcherVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabSwitcherVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        tabSwitcherVC.didMove(toParent: self)
        updateTabSwitcher(animated: false)
        tabSwitcherVC.view.alpha = 0
        UIView.animate(withDuration: 0.18) {
            tabSwitcherVC.view.alpha = 1
        }
    }

    private func hideTabSwitcher(animated: Bool) {
        guard let tabSwitcherVC else { return }
        self.tabSwitcherVC = nil
        let remove = {
            tabSwitcherVC.willMove(toParent: nil)
            tabSwitcherVC.view.removeFromSuperview()
            tabSwitcherVC.removeFromParent()
        }
        guard animated else {
            remove()
            return
        }
        UIView.animate(withDuration: 0.18) {
            tabSwitcherVC.view.alpha = 0
        } completion: { _ in
            remove()
        }
    }

    private func updateTabSwitcher(animated: Bool) {
        guard let tabSwitcherVC else { return }
        tabSwitcherVC.apply(tabs: makeTabInfos(), animated: animated)
    }

    private func makeTabInfos() -> [InAppBrowserTabInfo] {
        pages.map { page in
            let pageState = page.state
            let url = pageState.url
            let title = pageState.title?.nilIfEmpty ?? url.host(percentEncoded: false) ?? url.absoluteString
            let subtitle = url.absoluteString
            return InAppBrowserTabInfo(
                id: pageState.id,
                title: title,
                subtitle: subtitle,
                previewImage: pageState.previewImage,
                isSelected: page === currentPage
            )
        }
    }

    private func closeCurrentTabOrSheet() {
        guard pages.count > 1, let currentPage else {
            closeSheet()
            return
        }
        closePage(currentPage)
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

extension InAppBrowserVC: InAppBrowserTabSwitcherDelegate {
    func inAppBrowserTabSwitcher(_ tabSwitcher: InAppBrowserTabSwitcherVC, didSelectTab id: UUID) {
        selectPage(id: id)
    }

    func inAppBrowserTabSwitcher(_ tabSwitcher: InAppBrowserTabSwitcherVC, didCloseTab id: UUID) {
        closePage(id: id)
    }
}
