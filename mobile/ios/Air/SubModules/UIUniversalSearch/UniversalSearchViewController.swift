import UIComponents
import UIKit
import WalletContext

private let log = Log("UniversalSearch")

@MainActor
public final class UniversalSearchViewController: UIViewController, UICollectionViewDelegate {
    private static let defaultBottomContentInset: CGFloat = 24
    private static let keyboardDismissalDragThreshold: CGFloat = 12

    public typealias SelectionHandler = (UniversalSearchItem) -> Void
    public typealias HeaderAccessoryHandler = (UniversalSearchSection) -> Void

    public private(set) var sections: [UniversalSearchSection]
    public private(set) var preselectedItemID: String?
    public var onSelect: SelectionHandler?
    public var onHeaderAccessoryTap: HeaderAccessoryHandler?

    private struct ItemIdentifier: Hashable {
        let sectionID: String
        let modeID: Int?
        let itemID: String
    }

    private struct PresentationVisualSignature: Equatable {
        let sections: [SectionVisualSignature]
        let preselectedItemID: String?

        @MainActor init(sections: [UniversalSearchSection], preselectedItemID: String?) {
            self.sections = sections.map(SectionVisualSignature.init)
            self.preselectedItemID = preselectedItemID
        }
    }

    private struct SectionVisualSignature: Equatable {
        let id: String
        let title: String
        let headerAccessory: HeaderAccessoryVisualSignature?
        let layout: LayoutVisualSignature
        let rowHeight: CGFloat?
        let showsHeader: Bool
        let showsLeadingSeparator: Bool
        let items: [ItemVisualSignature]

        @MainActor init(_ section: UniversalSearchSection) {
            id = section.id
            title = section.title
            headerAccessory = section.headerAccessory.map(HeaderAccessoryVisualSignature.init)
            layout = LayoutVisualSignature(section.layout)
            rowHeight = section.rowHeight
            showsHeader = section.showsHeader
            showsLeadingSeparator = section.showsLeadingSeparator
            items = section.items.map(ItemVisualSignature.init)
        }
    }

    private enum HeaderAccessoryVisualSignature: Equatable {
        case toggle(primary: String, secondary: String, selected: Int)
        case text(String)

        @MainActor init(_ accessory: UniversalSearchSection.HeaderAccessory) {
            switch accessory {
            case .toggle(let primary, let secondary, let selected):
                self = .toggle(
                    primary: primary,
                    secondary: secondary,
                    selected: selected.rawValue
                )
            case .text(let text):
                self = .text(text)
            }
        }
    }

    private enum LayoutVisualSignature: Equatable {
        case list
        case paged(rowsPerPage: Int)
        case promptPages(rowsPerPage: Int)

        @MainActor init(_ layout: UniversalSearchSection.Layout) {
            switch layout {
            case .list:
                self = .list
            case .paged(let rowsPerPage):
                self = .paged(rowsPerPage: rowsPerPage)
            case .promptPages(let rowsPerPage):
                self = .promptPages(rowsPerPage: rowsPerPage)
            }
        }
    }

    // IconView owns its asynchronous image lifecycle. The signature tracks values whose
    // changes require the collection view to reconfigure an existing cell.
    private enum ItemVisualSignature: Equatable {
        case chat(id: String, title: String, subtitle: String)
        case token(
            id: String,
            title: String,
            badge: String?,
            price: String,
            amount: String?,
            balanceValue: String?
        )
        case collectible(id: String, title: String, subtitle: String)
        case collection(id: String, title: String, subtitle: String)
        case app(
            id: String,
            title: String,
            subtitle: String,
            showsTelegramBadge: Bool,
            actionTitle: String?
        )
        case wallet(id: String, title: String, subtitle: String)
        case shortcut(id: String, title: String, subtitle: String?)
        case askAgent(id: String, query: String)
        case recentSearch(id: String, title: String, subtitle: String)
        case site(id: String, title: String, subtitle: String)
        case openWebsite(id: String, title: String, subtitle: String)
        case google(id: String, query: String)
        case prompt(id: String, text: String)

        @MainActor init(_ item: UniversalSearchItem) {
            switch item.content {
            case .chat(let result):
                self = .chat(id: item.id, title: result.title, subtitle: result.subtitle)
            case .token(let result):
                self = .token(
                    id: item.id,
                    title: result.title,
                    badge: result.badge,
                    price: result.price,
                    amount: result.amount,
                    balanceValue: result.balanceValue
                )
            case .collectible(let result):
                self = .collectible(
                    id: item.id,
                    title: result.title,
                    subtitle: result.subtitle
                )
            case .collection(let result):
                self = .collection(
                    id: item.id,
                    title: result.title,
                    subtitle: result.subtitle
                )
            case .app(let result):
                self = .app(
                    id: item.id,
                    title: result.title,
                    subtitle: result.subtitle,
                    showsTelegramBadge: result.showsTelegramBadge,
                    actionTitle: result.actionTitle
                )
            case .wallet(let result):
                self = .wallet(id: item.id, title: result.title, subtitle: result.subtitle)
            case .shortcut(let result):
                self = .shortcut(id: item.id, title: result.title, subtitle: result.subtitle)
            case .askAgent(let query):
                self = .askAgent(id: item.id, query: query)
            case .recentSearch(let result):
                self = .recentSearch(
                    id: item.id,
                    title: result.title,
                    subtitle: result.subtitle
                )
            case .site(let result):
                self = .site(id: item.id, title: result.title, subtitle: result.subtitle)
            case .openWebsite(let result):
                self = .openWebsite(
                    id: item.id,
                    title: result.title,
                    subtitle: result.subtitle
                )
            case .google(let query):
                self = .google(id: item.id, query: query)
            case .prompt(let prompt):
                self = .prompt(id: item.id, text: prompt.text)
            }
        }
    }

    private lazy var collectionView = UICollectionView(
        frame: .zero,
        collectionViewLayout: makeLayout()
    )
    private var dataSource: UICollectionViewDiffableDataSource<String, ItemIdentifier>!
    private var itemsByIdentifier: [ItemIdentifier: UniversalSearchItem] = [:]
    private var sectionsByID: [String: UniversalSearchSection] = [:]
    private var snapshotGeneration: UInt64 = 0
    private var presentationVisualSignature: PresentationVisualSignature?
    private var bottomContentInset = defaultBottomContentInset
    private var dragStartContentOffsetY: CGFloat?
    private var didDismissKeyboardForCurrentDrag = false

    public init(
        sections: [UniversalSearchSection],
        preselectedItemID: String? = nil,
        onSelect: SelectionHandler? = nil,
        onHeaderAccessoryTap: HeaderAccessoryHandler? = nil
    ) {
        self.sections = sections
        self.sectionsByID = Self.indexedSections(sections)
        self.preselectedItemID = preselectedItemID
        self.onSelect = onSelect
        self.onHeaderAccessoryTap = onHeaderAccessoryTap
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .air.background
        configureCollectionView()
        configureDataSource()
        applySnapshot(
            sections: sections,
            preselectedItemID: preselectedItemID,
            animatingDifferences: false
        )
    }

    public func setSections(
        _ sections: [UniversalSearchSection],
        animated: Bool = true,
        completion: (() -> Void)? = nil
    ) {
        setSections(
            sections,
            preselectedItemID: preselectedItemID,
            animated: animated,
            completion: completion
        )
    }

    public func setSections(
        _ sections: [UniversalSearchSection],
        preselectedItemID: String?,
        animated: Bool = true,
        completion: (() -> Void)? = nil
    ) {
        guard isViewLoaded else {
            self.sections = sections
            sectionsByID = Self.indexedSections(sections)
            self.preselectedItemID = preselectedItemID
            completion?()
            return
        }
        applySnapshot(
            sections: sections,
            preselectedItemID: preselectedItemID,
            animatingDifferences: animated,
            completion: completion
        )
    }

    @discardableResult
    public func selectPreselectedItem() -> Bool {
        guard let identifier = preselectedIdentifier(),
              let item = itemsByIdentifier[identifier] else {
            return false
        }
        onSelect?(item)
        return true
    }

    public func setPreselectedItemID(_ itemID: String?) {
        preselectedItemID = itemID
        guard isViewLoaded else { return }
        UIView.performWithoutAnimation {
            collectionView.collectionViewLayout.invalidateLayout()
            collectionView.layoutIfNeeded()
            applyPreselection()
        }
    }

    public func setBottomContentInset(_ bottomInset: CGFloat) {
        bottomContentInset = max(0, bottomInset)
        guard isViewLoaded else { return }
        applyBottomContentInset()
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        didSelectItemAt indexPath: IndexPath
    ) {
        guard let identifier = dataSource.itemIdentifier(for: indexPath),
              let item = itemsByIdentifier[identifier] else { return }
        if identifier != preselectedIdentifier() {
            collectionView.deselectItem(at: indexPath, animated: true)
            applyPreselection()
        }
        onSelect?(item)
    }

    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        dragStartContentOffsetY = scrollView.contentOffset.y
        didDismissKeyboardForCurrentDrag = false
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !didDismissKeyboardForCurrentDrag,
              scrollView.isDragging,
              let dragStartContentOffsetY,
              abs(scrollView.contentOffset.y - dragStartContentOffsetY)
                >= Self.keyboardDismissalDragThreshold
        else { return }

        didDismissKeyboardForCurrentDrag = true
        view.window?.endEditing(true)
    }

    public func scrollViewDidEndDragging(
        _ scrollView: UIScrollView,
        willDecelerate decelerate: Bool
    ) {
        dragStartContentOffsetY = nil
        didDismissKeyboardForCurrentDrag = false
    }

    private func configureCollectionView() {
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .air.background
        collectionView.alwaysBounceVertical = true
        collectionView.delaysContentTouches = false
        collectionView.keyboardDismissMode = .none
        collectionView.delegate = self
        applyBottomContentInset()
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func applyBottomContentInset() {
        collectionView.contentInset.bottom = bottomContentInset
        collectionView.verticalScrollIndicatorInsets.bottom = bottomContentInset
    }

    private func configureDataSource() {
        let textRegistration = UICollectionView.CellRegistration<
            UniversalSearchTextResultCell,
            ItemIdentifier
        > { [weak self] cell, _, identifier in
            guard let item = self?.itemsByIdentifier[identifier] else { return }
            switch item.content {
            case .chat(let result):
                cell.configure(
                    icon: UniversalSearchIcon(UniversalSearchIconConfiguration(
                        systemName: "sparkles.2",
                        foregroundColor: .label
                    )),
                    title: result.title,
                    subtitle: result.subtitle
                )
            case .collectible(let result):
                cell.configure(icon: result.icon, title: result.title, subtitle: result.subtitle)
            case .collection(let result):
                cell.configure(
                    icon: UniversalSearchIcon(UniversalSearchIconConfiguration(
                        systemName: "cube.transparent",
                        foregroundColor: .label
                    )),
                    title: result.title,
                    subtitle: result.subtitle
                )
            case .wallet(let result):
                cell.configure(icon: result.icon, title: result.title, subtitle: result.subtitle)
            case .shortcut(let result):
                cell.configure(icon: result.icon, title: result.title, subtitle: result.subtitle ?? "",
                               centersTitle: result.subtitle == nil)
            case .recentSearch(let result):
                cell.configure(
                    icon: UniversalSearchIcon(UniversalSearchIconConfiguration(
                        systemName: "clock",
                        foregroundColor: .label
                    )),
                    title: result.title,
                    subtitle: result.subtitle,
                    titleStyle: .regular
                )
            case .site(let result):
                cell.configure(
                    icon: UniversalSearchIcon(UniversalSearchIconConfiguration(
                        systemName: "clock",
                        foregroundColor: .label
                    )),
                    title: result.title,
                    subtitle: result.subtitle
                )
            case .openWebsite(let result):
                cell.configure(
                    icon: UniversalSearchIcon(UniversalSearchIconConfiguration(
                        systemName: "safari",
                        foregroundColor: .label
                    )),
                    title: result.title,
                    subtitle: result.subtitle
                )
            default:
                assertionFailure("Unexpected item for text cell")
            }
        }

        let tokenRegistration = UICollectionView.CellRegistration<
            UniversalSearchTokenCell,
            ItemIdentifier
        > { [weak self] cell, _, identifier in
            guard let item = self?.itemsByIdentifier[identifier],
                  case .token(let result) = item.content else { return }
            cell.configure(result)
        }

        let appRegistration = UICollectionView.CellRegistration<
            UniversalSearchAppCell,
            ItemIdentifier
        > { [weak self] cell, _, identifier in
            guard let self,
                  let item = itemsByIdentifier[identifier],
                  case .app(let result) = item.content else { return }
            cell.configure(result) { [weak self] in
                self?.onSelect?(item)
            }
        }

        let actionRegistration = UICollectionView.CellRegistration<
            UniversalSearchActionCell,
            ItemIdentifier
        > { [weak self] cell, _, identifier in
            guard let item = self?.itemsByIdentifier[identifier] else { return }
            switch item.content {
            case .askAgent(let query):
                cell.configure(kind: .agent, title: query)
            case .google(let query):
                cell.configure(kind: .webSearch, title: query)
            default:
                assertionFailure("Unexpected item for action cell")
            }
        }

        let promptRegistration = UICollectionView.CellRegistration<
            UniversalSearchPromptCell,
            ItemIdentifier
        > { [weak self] cell, _, identifier in
            guard let item = self?.itemsByIdentifier[identifier],
                  case .prompt(let prompt) = item.content else { return }
            cell.configure(prompt)
        }

        dataSource = UICollectionViewDiffableDataSource<String, ItemIdentifier>(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, identifier in
            guard let self, let item = itemsByIdentifier[identifier] else { return nil }
            let cell: UICollectionViewCell
            switch item.content {
            case .chat, .collectible, .collection, .wallet, .recentSearch, .site,
                 .openWebsite, .shortcut:
                cell = collectionView.dequeueConfiguredReusableCell(
                    using: textRegistration,
                    for: indexPath,
                    item: identifier
                )
            case .token:
                cell = collectionView.dequeueConfiguredReusableCell(
                    using: tokenRegistration,
                    for: indexPath,
                    item: identifier
                )
            case .app:
                cell = collectionView.dequeueConfiguredReusableCell(
                    using: appRegistration,
                    for: indexPath,
                    item: identifier
                )
            case .askAgent, .google:
                cell = collectionView.dequeueConfiguredReusableCell(
                    using: actionRegistration,
                    for: indexPath,
                    item: identifier
                )
            case .prompt:
                cell = collectionView.dequeueConfiguredReusableCell(
                    using: promptRegistration,
                    for: indexPath,
                    item: identifier
                )
            }
            if let cell = cell as? UniversalSearchBaseCell {
                cell.isPersistentlySelected = identifier == preselectedIdentifier()
            }
            return cell
        }

        let headerRegistration = UICollectionView.SupplementaryRegistration<
            UniversalSearchSectionHeaderView
        >(elementKind: UniversalSearchSectionHeaderView.elementKind) { [weak self] header, _, indexPath in
            self?.configure(header: header, at: indexPath)
        }

        dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(
                using: headerRegistration,
                for: indexPath
            )
        }
    }

    private func updateVisibleHeaders(animated: Bool) {
        for indexPath in collectionView.indexPathsForVisibleSupplementaryElements(
            ofKind: UniversalSearchSectionHeaderView.elementKind
        ) {
            guard let header = collectionView.supplementaryView(
                forElementKind: UniversalSearchSectionHeaderView.elementKind,
                at: indexPath
            ) as? UniversalSearchSectionHeaderView else { continue }
            configure(header: header, at: indexPath, animated: animated)
        }
    }

    private func configure(
        header: UniversalSearchSectionHeaderView,
        at indexPath: IndexPath,
        animated: Bool = false
    ) {
        guard let section = sectionModel(at: indexPath.section) else { return }
        let onAccessoryTap: (() -> Void)? = if case .toggle = section.headerAccessory {
            { [weak self] in self?.onHeaderAccessoryTap?(section) }
        } else {
            nil
        }
        header.configure(
            section: section,
            showsSeparator: indexPath.section > 0 && section.showsLeadingSeparator,
            onAccessoryTap: onAccessoryTap,
            animated: animated
        )
    }

    private func applySnapshot(
        sections newSections: [UniversalSearchSection],
        preselectedItemID newPreselectedItemID: String?,
        animatingDifferences: Bool,
        completion: (() -> Void)? = nil
    ) {
        snapshotGeneration &+= 1
        let generation = snapshotGeneration
        sections = newSections
        sectionsByID = Self.indexedSections(newSections)
        preselectedItemID = newPreselectedItemID

        var newItemsByIdentifier: [ItemIdentifier: UniversalSearchItem] = [:]
        var snapshot = NSDiffableDataSourceSnapshot<String, ItemIdentifier>()
        for section in newSections {
            snapshot.appendSections([section.id])
            let modeID = modeID(for: section)
            var identifiers: [ItemIdentifier] = []
            for item in section.items {
                let identifier = ItemIdentifier(
                    sectionID: section.id,
                    modeID: modeID,
                    itemID: item.id
                )
                guard newItemsByIdentifier[identifier] == nil else {
#if DEBUG
                    log.error("duplicate search item ID section=\(section.id, .public) item=\(item.id, .public)")
#endif
                    continue
                }
                newItemsByIdentifier[identifier] = item
                identifiers.append(identifier)
            }
            snapshot.appendItems(identifiers, toSection: section.id)
        }

        let newVisualSignature = PresentationVisualSignature(
            sections: newSections,
            preselectedItemID: newPreselectedItemID
        )
        guard newVisualSignature != presentationVisualSignature else {
            itemsByIdentifier = newItemsByIdentifier
            completion?()
            return
        }
        presentationVisualSignature = newVisualSignature

        let existingIdentifiers = Set(dataSource.snapshot().itemIdentifiers)
        let identifiersToReconfigure = snapshot.itemIdentifiers.filter { identifier in
            guard existingIdentifiers.contains(identifier),
                  let oldItem = itemsByIdentifier[identifier],
                  let newItem = newItemsByIdentifier[identifier] else {
                return false
            }
            return ItemVisualSignature(oldItem) != ItemVisualSignature(newItem)
        }
        if !identifiersToReconfigure.isEmpty {
            snapshot.reconfigureItems(identifiersToReconfigure)
        }
        itemsByIdentifier.merge(newItemsByIdentifier) { _, new in new }

        let finish = { [weak self] in
            guard let self else {
                completion?()
                return
            }
            if generation == snapshotGeneration {
                itemsByIdentifier = newItemsByIdentifier
                applyPreselection()
            }
            completion?()
        }

        if animatingDifferences, collectionView.window != nil {
            updateVisibleHeaders(animated: true)
            collectionView.collectionViewLayout.invalidateLayout()
            dataSource.apply(snapshot, animatingDifferences: true, completion: finish)
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            UIView.performWithoutAnimation {
                updateVisibleHeaders(animated: false)
                dataSource.apply(snapshot, animatingDifferences: false)
                collectionView.collectionViewLayout.invalidateLayout()
                collectionView.layoutIfNeeded()
            }
            CATransaction.commit()
            finish()
        }
    }

    private func applyPreselection() {
        updateVisiblePreselectionAppearance()
        for indexPath in collectionView.indexPathsForSelectedItems ?? [] {
            collectionView.deselectItem(at: indexPath, animated: false)
        }
        guard let identifier = preselectedIdentifier(),
              let indexPath = dataSource.indexPath(for: identifier) else { return }
        collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
    }

    private func updateVisiblePreselectionAppearance() {
        for case let cell as UniversalSearchBaseCell in collectionView.visibleCells {
            guard let indexPath = collectionView.indexPath(for: cell),
                  let identifier = dataSource.itemIdentifier(for: indexPath) else { continue }
            cell.isPersistentlySelected = identifier == preselectedIdentifier()
        }
    }

    private func preselectedIdentifier() -> ItemIdentifier? {
        guard let preselectedItemID else { return nil }
        let sectionIDs = dataSource?.snapshot().sectionIdentifiers ?? sections.map(\.id)
        for sectionID in sectionIDs {
            guard let section = sectionsByID[sectionID],
                  section.items.contains(where: { $0.id == preselectedItemID }) else {
                continue
            }
            return ItemIdentifier(
                sectionID: section.id,
                modeID: modeID(for: section),
                itemID: preselectedItemID
            )
        }
        return nil
    }

    private func sectionModel(at sectionIndex: Int) -> UniversalSearchSection? {
        if let dataSource {
            let sectionIDs = dataSource.snapshot().sectionIdentifiers
            if sectionIDs.indices.contains(sectionIndex) {
                return sectionsByID[sectionIDs[sectionIndex]]
            }
        }
        guard sections.indices.contains(sectionIndex) else { return nil }
        return sections[sectionIndex]
    }

    private static func indexedSections(
        _ sections: [UniversalSearchSection]
    ) -> [String: UniversalSearchSection] {
        var result: [String: UniversalSearchSection] = [:]
        for section in sections {
#if DEBUG
            if result[section.id] != nil {
                log.error("duplicate search section ID section=\(section.id, .public)")
            }
#endif
            result[section.id] = section
        }
        return result
    }

    private func modeID(for section: UniversalSearchSection) -> Int? {
        if case .toggle(_, _, let selected) = section.headerAccessory {
            selected.rawValue
        } else {
            nil
        }
    }

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        let configuration = UICollectionViewCompositionalLayoutConfiguration()
        configuration.scrollDirection = .vertical
        configuration.interSectionSpacing = 8
        return UICollectionViewCompositionalLayout(
            sectionProvider: { [weak self] sectionIndex, environment in
                self?.makeLayoutSection(at: sectionIndex, environment: environment)
            },
            configuration: configuration
        )
    }

    private func makeLayoutSection(
        at sectionIndex: Int,
        environment: NSCollectionLayoutEnvironment
    ) -> NSCollectionLayoutSection? {
        guard let model = sectionModel(at: sectionIndex) else { return nil }
        // A compositional group has one fixed row height. Mixed content is supported
        // only when its kinds share that height (for example, collectibles and collections).
        let rowHeight = model.rowHeight ?? rowHeight(for: model.items.first)
        let pageWidth = max(1, environment.container.effectiveContentSize.width - 64)
        let section: NSCollectionLayoutSection

        switch model.layout {
        case .list:
            let rowsPerPage = 3
            section = model.items.count > rowsPerPage
                ? pagedSection(
                    rowHeight: rowHeight,
                    rowsPerPage: rowsPerPage,
                    interRowSpacing: 0,
                    pageWidth: pageWidth
                )
                : listSection(rowHeight: rowHeight)
        case .paged(let rowsPerPage):
            let rows = max(1, rowsPerPage)
            section = model.items.count > rows
                ? pagedSection(
                    rowHeight: rowHeight,
                    rowsPerPage: rows,
                    interRowSpacing: 0,
                    pageWidth: pageWidth
                )
                : listSection(rowHeight: rowHeight)
        case .promptPages(let rowsPerPage):
            section = promptPagesSection(
                items: model.items,
                rowsPerPage: max(1, rowsPerPage),
                maximumColumnWidth: pageWidth
            )
        }

        let promptInsets: (top: CGFloat, bottom: CGFloat) = switch model.layout {
        case .promptPages:
            (model.showsHeader ? 12 : 4, 12)
        default:
            (0, 0)
        }
        let preselectedItemInset: CGFloat = preselectedIdentifier()?.sectionID == model.id ? 4 : 0
        section.contentInsets = NSDirectionalEdgeInsets(
            top: promptInsets.top + preselectedItemInset,
            leading: 32,
            bottom: promptInsets.bottom,
            trailing: 32
        )
        if model.showsHeader {
            let showsLeadingSeparator = sectionIndex > 0 && model.showsLeadingSeparator
            let headerHeight: CGFloat = showsLeadingSeparator ? 43 : 34
            let header = NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .absolute(headerHeight)
                ),
                elementKind: UniversalSearchSectionHeaderView.elementKind,
                alignment: .top
            )
            section.boundarySupplementaryItems = [header]
        }
        return section
    }

    private func listSection(
        rowHeight: CGFloat,
        interRowSpacing: CGFloat = 0
    ) -> NSCollectionLayoutSection {
        let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .absolute(rowHeight)
        ))
        let group = NSCollectionLayoutGroup.vertical(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .absolute(rowHeight)
            ),
            subitems: [item]
        )
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = interRowSpacing
        return section
    }

    private func pagedSection(
        rowHeight: CGFloat,
        rowsPerPage: Int,
        interRowSpacing: CGFloat,
        pageWidth: CGFloat
    ) -> NSCollectionLayoutSection {
        let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .absolute(rowHeight)
        ))
        let height = rowHeight * CGFloat(rowsPerPage)
            + interRowSpacing * CGFloat(max(0, rowsPerPage - 1))
        let group = NSCollectionLayoutGroup.vertical(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .absolute(pageWidth),
                heightDimension: .absolute(height)
            ),
            repeatingSubitem: item,
            count: rowsPerPage
        )
        group.interItemSpacing = .fixed(interRowSpacing)
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 20
        section.orthogonalScrollingBehavior = .groupPagingCentered
        return section
    }

    private func promptPagesSection(
        items: [UniversalSearchItem],
        rowsPerPage: Int,
        maximumColumnWidth: CGFloat
    ) -> NSCollectionLayoutSection {
        let rowHeight = UniversalSearchPromptCell.height
        let rowSpacing: CGFloat = 12
        let columnSpacing: CGFloat = 20
        let rows = max(1, rowsPerPage)
        let itemWidths = items.map { item -> CGFloat in
            guard case .prompt(let prompt) = item.content else { return maximumColumnWidth }
            return UniversalSearchPromptCell.width(for: prompt.text, maximumWidth: maximumColumnWidth)
        }
        let columnCount = max(1, Int(ceil(Double(items.count) / Double(rows))))
        let columnWidths = (0..<columnCount).map { columnIndex -> CGFloat in
            let start = columnIndex * rows
            let end = min(start + rows, itemWidths.count)
            return start < end ? itemWidths[start..<end].max() ?? 1 : 1
        }
        var columnOrigins: [CGFloat] = []
        var nextColumnOrigin: CGFloat = 0
        for columnWidth in columnWidths {
            columnOrigins.append(nextColumnOrigin)
            nextColumnOrigin += columnWidth + columnSpacing
        }
        let totalWidth = max(1, nextColumnOrigin - columnSpacing)
        let populatedRows = max(1, min(rows, items.count))
        let totalHeight = rowHeight * CGFloat(populatedRows)
            + rowSpacing * CGFloat(max(0, populatedRows - 1))
        let customItems = itemWidths.enumerated().map { index, width in
            let column = index / rows
            let row = index % rows
            return NSCollectionLayoutGroupCustomItem(frame: CGRect(
                x: columnOrigins[column],
                y: CGFloat(row) * (rowHeight + rowSpacing),
                width: width,
                height: rowHeight
            ))
        }
        let group = NSCollectionLayoutGroup.custom(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .absolute(totalWidth),
                heightDimension: .absolute(totalHeight)
            )
        ) { _ in
            customItems
        }
        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .continuous
        return section
    }

    private func rowHeight(for item: UniversalSearchItem?) -> CGFloat {
        guard let item else { return 56 }
        switch item.content {
        case .askAgent:
            return 52
        case .google:
            return 43
        case .prompt:
            return 40
        case .shortcut(let result):
            return result.subtitle == nil ? 52 : 56
        default:
            return 56
        }
    }
}
