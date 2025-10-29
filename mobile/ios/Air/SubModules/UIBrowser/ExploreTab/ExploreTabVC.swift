
import UIKit
import UIComponents
import WalletCore
@preconcurrency import WalletContext
import UIDapp


public class ExploreTabVC: WViewController {
    
    private var exploreVC = ExploreVC()
    
    private var newSearch: ExploreSearch?
    
    private var searchBarContainer: UIView?
    private var searchBar: WSearchBar?
    private var searchBarContainerBottomConstraint: NSLayoutConstraint?
    private var searchBarBlurView: WBlurView?
    
    public override var hideNavigationBar: Bool { true }
    public override var prefersStatusBarHidden: Bool { exploreVC.prefersStatusBarHidden }
    
    public override func loadView() {
        super.loadView()
        setupViews()
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        // listen for keyboard
        WKeyboardObserver.observeKeyboard(delegate: self)
        
        TonConnect.shared.start()
    }
    
    func setupViews() {
        view.backgroundColor = WTheme.background
        
        addChild(exploreVC)
        exploreVC.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(exploreVC.view)
        NSLayoutConstraint.activate([
            exploreVC.view.topAnchor.constraint(equalTo: view.topAnchor),
            exploreVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            exploreVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            exploreVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        exploreVC.didMove(toParent: self)
        exploreVC.onSelectAny = { [self] in
            self.view.endEditing(true)
            searchBar?.resignFirstResponder()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.searchBar?.text = nil
                self.searchBar?.setCenteredPlaceholder()
                self.searchBar?.onChange?("")
                self.view.endEditing(true)
                self.searchBar?.resignFirstResponder()
                self.newSearch?.viewModel.string = ""
                self.view.endEditing(true)
            }
        }
        
        // MARK: search bar
        if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
            let newSearch = ExploreSearch()
            self.newSearch = newSearch
            view.addSubview(newSearch)
            view.keyboardLayoutGuide.keyboardDismissPadding = 40
            NSLayoutConstraint.activate([
                newSearch.heightAnchor.constraint(equalToConstant: 80),
                newSearch.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
                newSearch.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                newSearch.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            ])
//            newSearch.backgroundColor = .orange.withAlphaComponent(0.2)
            newSearch.viewModel.onChange = { [weak self] in self?.onChange($0) }
            newSearch.viewModel.onSubmit = { [weak self] in self?.onSubmit($0) }
        } else {
            let searchBarContainer = UIView()
            self.searchBarContainer = searchBarContainer
            searchBarContainer.translatesAutoresizingMaskIntoConstraints = false
            searchBarContainer.backgroundColor = .clear
            view.addSubview(searchBarContainer)
            let searchBarContainerBottomConstraint = searchBarContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -view.safeAreaInsets.bottom)
            self.searchBarContainerBottomConstraint = searchBarContainerBottomConstraint
            NSLayoutConstraint.activate([
                searchBarContainerBottomConstraint,
                searchBarContainer.leftAnchor.constraint(equalTo: view.leftAnchor),
                searchBarContainer.rightAnchor.constraint(equalTo: view.rightAnchor),
                searchBarContainer.heightAnchor.constraint(equalToConstant: 67)
            ])
            
            let color = UIColor { $0.userInterfaceStyle != .dark ? WColors.blurBackground : WColors.blurBackground.withAlphaComponent(0.85) }
            let searchBarBlurView = WBlurView(background: color)
            self.searchBarBlurView = searchBarBlurView
            view.addSubview(searchBarBlurView)
            searchBarBlurView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                searchBarBlurView.topAnchor.constraint(equalTo: searchBarContainer.topAnchor),
                searchBarBlurView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                searchBarBlurView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                searchBarBlurView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            ])

            let separatorView = UIView()
            separatorView.translatesAutoresizingMaskIntoConstraints = false
            separatorView.backgroundColor = WTheme.border
            searchBarContainer.addSubview(separatorView)
            NSLayoutConstraint.activate([
                separatorView.topAnchor.constraint(equalTo: searchBarContainer.topAnchor),
                separatorView.leftAnchor.constraint(equalTo: searchBarContainer.leftAnchor),
                separatorView.rightAnchor.constraint(equalTo: searchBarContainer.rightAnchor),
                separatorView.heightAnchor.constraint(equalToConstant: 0.33)
            ])
            
            let searchBar = WSearchBar()
            self.searchBar = searchBar
            searchBar.translatesAutoresizingMaskIntoConstraints = false
            searchBar.placeholder = lang("Search or enter address")
            searchBar.onChange = { [weak self] in self?.onChange($0) }
            searchBar.onSubmit = { [weak self] in self?.onSubmit($0) }
            searchBarContainer.addSubview(searchBar)
            NSLayoutConstraint.activate([
                searchBar.centerYAnchor.constraint(equalTo: searchBarContainer.centerYAnchor, constant: -1),
                searchBar.leftAnchor.constraint(equalTo: searchBarContainer.leftAnchor, constant: 16),
                searchBar.rightAnchor.constraint(equalTo: searchBarContainer.rightAnchor, constant: -16)
            ])
            view.bringSubviewToFront(searchBarContainer)
        }
        
        updateTheme()
    }
    
    public override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        
        if searchBar?.text?.isEmpty != false {
            DispatchQueue.main.async {
                self.searchBar?.setCenteredPlaceholder()
            }
        }
    }
    
    public override func updateTheme() {
        view.backgroundColor = WTheme.background
    }
    
    public override func scrollToTop(animated: Bool) {
        exploreVC.scrollToTop(animated: animated)
    }
    
    public override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        UIView.animate(withDuration: 0.3) { [self] in
            searchBarContainerBottomConstraint?.constant = -view.safeAreaInsets.bottom
            view.layoutIfNeeded()
        }
    }
    
    func onChange(_ text: String) {
        exploreVC.searchString = text
        exploreVC.applySnapshot(animated: true)
    }
    
    func onSubmit(_ text: String) {
        @MainActor func error() {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        
        var urlString = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !urlString.contains("://") && !urlString.contains(".") {
            let searchURL = "https://www.google.com/search?q=\(urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? urlString)"
            if let url = URL(string: searchURL) {
                AppActions.openInBrowser(url)
            }
        } else {
            if !urlString.contains("://") {
                urlString = "https://" + urlString
            }
            guard let _url = URL(string: urlString), var components = URLComponents(url: _url, resolvingAgainstBaseURL: false) else {
                error()
                return
            }
            if components.scheme == nil {
                components.scheme = "https"
            }
            guard let url = components.url, url.host(percentEncoded: false)?.contains(".") == true else {
                error()
                return
            }
            AppActions.openInBrowser(url)
        }
        view.endEditing(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.searchBar?.text = nil
            self.searchBar?.setCenteredPlaceholder()
            self.searchBar?.onChange?("")
            self.view.endEditing(true)
            self.searchBar?.resignFirstResponder()
            self.newSearch?.viewModel.string = ""
        }
    }
}


extension ExploreTabVC: WKeyboardObserverDelegate {
    public func keyboardWillShow(info: WKeyboardDisplayInfo) {
        UIView.animate(withDuration: 0.25) { [self] in
            if let window = view.window {
                searchBarContainerBottomConstraint?.constant = -info.height + (window.bounds.height - view.frame.height) // keyboard height is in windows coordinates
                view.layoutIfNeeded()
            }
        }
    }
    
    public func keyboardWillHide(info: WKeyboardDisplayInfo) {
        UIView.animate(withDuration: 0.25) { [self] in
            searchBarContainerBottomConstraint?.constant = -view.safeAreaInsets.bottom
            view.layoutIfNeeded()
        }
    }
}
