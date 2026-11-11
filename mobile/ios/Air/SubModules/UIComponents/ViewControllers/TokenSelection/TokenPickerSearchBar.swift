import UIKit
import WalletContext

public final class TokenPickerSearchBar: UISearchBar {
    public var onTextChange: ((String) -> Void)?
    private var scrollViews: [UIScrollView] = []

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        delegate = self
        searchBarStyle = .minimal
        placeholder = lang("Search")
        autocapitalizationType = .none
        autocorrectionType = .no
        spellCheckingType = .no
        searchTextField.accessibilityIdentifier = "token_picker_search"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func install(in view: UIView) {
        view.addSubview(self)
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 8),
            trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            heightAnchor.constraint(equalToConstant: 56),
        ])
        if IOS_26_MODE_ENABLED, #available(iOS 26, *) {
            let interaction = UIScrollEdgeElementContainerInteraction()
            interaction.edge = .bottom
            addInteraction(interaction)
        }
    }

    func setScrollViews(_ scrollViews: [UIScrollView], activeScrollView: UIScrollView?) {
        self.scrollViews = scrollViews
        if #available(iOS 26, *) {
            interactions.compactMap { $0 as? UIScrollEdgeElementContainerInteraction }.first?.scrollView = activeScrollView
        }
        updateContentInsets()
    }

    func updateContentInsets() {
        for scrollView in scrollViews {
            let searchFrame = convert(bounds, to: scrollView)
            let bottomInset = max(0, scrollView.bounds.maxY - searchFrame.minY - scrollView.safeAreaInsets.bottom)
            guard scrollView.contentInset.bottom != bottomInset else { continue }
            scrollView.contentInset.bottom = bottomInset
            scrollView.verticalScrollIndicatorInsets.bottom = bottomInset
        }
    }
}

extension TokenPickerSearchBar: UISearchBarDelegate {
    public func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        onTextChange?(searchText)
    }

    public func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        setShowsCancelButton(true, animated: true)
    }

    public func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        setShowsCancelButton(false, animated: true)
    }

    public func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        endEditing(true)
    }

    public func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        text = ""
        onTextChange?("")
        endEditing(true)
    }
}
