import UIKit
import WalletCore
import WalletContext

public enum TokenPickerCategory: String, CaseIterable {
    case all, fiat, stablecoins, tokens

    var title: String {
        switch self {
        case .all: lang("All")
        case .fiat: lang("Fiat")
        case .stablecoins: lang("Stablecoins")
        case .tokens: lang("Tokens")
        }
    }

    public static func getAvailableCategories(tokenSlugs: [String], hasFiat: Bool = false) -> [Self] {
        let stablecoinSlugs = getStablecoinSlugs()
        guard tokenSlugs.contains(where: { stablecoinSlugs.contains($0) }),
              tokenSlugs.contains(where: { !stablecoinSlugs.contains($0) }) else { return [.all] }
        return hasFiat ? allCases : [.all, .stablecoins, .tokens]
    }

    public func shouldInclude(tokenSlug: String) -> Bool {
        switch self {
        case .all: true
        case .fiat: false
        case .stablecoins: getStablecoinSlugs().contains(tokenSlug)
        case .tokens: !getStablecoinSlugs().contains(tokenSlug)
        }
    }
}

public final class TokenPickerContentView: UIView, WSegmentedController.Delegate {
    public let searchBar = TokenPickerSearchBar()
    public private(set) var categories: [TokenPickerCategory] = []
    private weak var parent: UIViewController?
    private let makeCollectionView: (TokenPickerCategory) -> UICollectionView
    private var pages: [TokenPickerCategory: TokenPickerListController] = [:]
    private var segmentedController: WSegmentedController?
    private var paletteWidth: NSLayoutConstraint?

    public init(parent: UIViewController, makeCollectionView: @escaping (TokenPickerCategory) -> UICollectionView) {
        self.parent = parent
        self.makeCollectionView = makeCollectionView
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        parent.view.addSubview(self)
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: parent.view.topAnchor),
            bottomAnchor.constraint(equalTo: parent.view.bottomAnchor),
            leadingAnchor.constraint(equalTo: parent.view.leadingAnchor),
            trailingAnchor.constraint(equalTo: parent.view.trailingAnchor),
        ])
        searchBar.install(in: self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        segmentedController?.setBackNavigation(in: parent?.navigationController)
    }

    public func updateCategories(_ categories: [TokenPickerCategory]) {
        guard self.categories != categories, let parent else { return }
        self.categories = categories
        var addedPages: [TokenPickerListController] = []
        let items = categories.map { category in
            let page: TokenPickerListController
            if let existing = pages[category] {
                page = existing
            } else {
                page = TokenPickerListController(collectionView: makeCollectionView(category))
                pages[category] = page
                parent.addChild(page)
                addedPages.append(page)
            }
            return SegmentedControlItem(
                id: category.rawValue,
                title: category.title,
                isDeletable: false,
                accessibilityIdentifier: "token_picker_tab_\(category.rawValue)",
                viewController: page
            )
        }
        let controller: WSegmentedController
        if let segmentedController {
            controller = segmentedController
            controller.replace(items: items)
        } else {
            controller = WSegmentedController(
                items: items,
                animationSpeed: .slow,
                primaryTextColor: UIColor(hex: "#0088FF"),
                secondaryTextColor: .label,
                style: .tokenPicker,
                delegate: self
            )
            segmentedController = controller
            insertSubview(controller, belowSubview: searchBar)
            NSLayoutConstraint.activate([
                controller.leadingAnchor.constraint(equalTo: leadingAnchor),
                controller.trailingAnchor.constraint(equalTo: trailingAnchor),
                controller.topAnchor.constraint(equalTo: topAnchor),
                controller.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            controller.blurView.isHidden = true
            controller.separator.isHidden = true
        }
        addedPages.forEach { $0.didMove(toParent: parent) }
        controller.scrollView.isScrollEnabled = categories.count > 1
        controller.setBackNavigation(in: parent.navigationController)
        installPalette(controller.segmentedControl)
        updateSearchScrollViews()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        paletteWidth?.constant = safeAreaLayoutGuide.layoutFrame.width
        searchBar.updateContentInsets()
    }

    public func updateEmptyState(_ isEmpty: Bool, for category: TokenPickerCategory) {
        pages[category]?.updateEmptyState(isEmpty)
    }

    private func installPalette(_ control: WSegmentedControl) {
        guard let parent else { return }
        control.removeFromSuperview()
        paletteWidth = nil
        guard categories.count > 1 else {
            PrivateAPI.setBottomPalette(of: parent.navigationItem, contentView: nil)
            return
        }
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(control)
        let width = container.widthAnchor.constraint(equalToConstant: safeAreaLayoutGuide.layoutFrame.width)
        paletteWidth = width
        NSLayoutConstraint.activate([
            width,
            control.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            control.centerXAnchor.constraint(equalTo: container.safeAreaLayoutGuide.centerXAnchor),
            control.widthAnchor.constraint(equalTo: container.safeAreaLayoutGuide.widthAnchor, constant: -32),
        ])
        container.frame.size.height = 56
        PrivateAPI.setBottomPalette(of: parent.navigationItem, contentView: container)
    }

    private func updateSearchScrollViews() {
        let selectedId = segmentedController?.model.selectedItem?.id
        let selected = selectedId.flatMap(TokenPickerCategory.init(rawValue:)) ?? .all
        searchBar.setScrollViews(categories.compactMap { pages[$0]?.collectionView }, activeScrollView: pages[selected]?.collectionView)
    }

    public func segmentedController(scrollOffsetChangedTo progress: CGFloat) {
        updateSearchScrollViews()
    }
}

private final class TokenPickerListController: UIViewController, WSegmentedControllerContent, UICollectionViewDelegate {
    let collectionView: UICollectionView
    private let emptyLabel = UILabel()
    var onScroll: ((CGFloat) -> Void)?
    var scrollingView: UIScrollView? { collectionView }

    init(collectionView: UICollectionView) {
        self.collectionView = collectionView
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .air.pickerBackground
        collectionView.keyboardDismissMode = .onDrag
        collectionView.delaysContentTouches = false
        collectionView.delegate = self
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
        ])
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(hideKeyboard))
        tapGesture.cancelsTouchesInView = false
        collectionView.addGestureRecognizer(tapGesture)
        emptyLabel.text = lang("Not Found")
        emptyLabel.textAlignment = .center
        emptyLabel.textColor = .air.secondaryLabel
        emptyLabel.applyTextStyle(.body)
    }

    func updateEmptyState(_ isEmpty: Bool) {
        collectionView.backgroundView = isEmpty ? emptyLabel : nil
    }

    func scrollToTop(animated: Bool) {
        collectionView.setContentOffset(CGPoint(x: 0, y: -collectionView.adjustedContentInset.top), animated: animated)
    }

    func calculateHeight(isHosted: Bool) -> CGFloat { collectionView.contentSize.height }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        onScroll?(scrollView.contentOffset.y)
    }

    @objc private func hideKeyboard() {
        parent?.view.endEditing(false)
    }
}
