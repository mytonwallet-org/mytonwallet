import UIComponents
import UIKit
import UIUniversalSearch
import WalletContext
import WalletCore

/// Settings' picture of the home screen's two bars: the top bar with its tabs and the toolbar itself, both arranged by
/// dragging, with dots for the screen between them, above the actions the toolbar can still take.
@MainActor
final class ToolbarsPreviewView: UIView, HomeToolbarEditorHost, UIGestureRecognizerDelegate {
    /// The height the view needs has changed; the view is animating to it
    var onHeightChange: (() -> Void)?

    let toolbar = UniversalSearchFieldView(configuration: .init(placeholder: lang("Search"), showsMicrophone: false))
    private(set) lazy var editor = HomeToolbarEditor(toolbar: toolbar, host: self)

    private let stageView = UIView()
    private let tabsView = ToolbarsPreviewTabsView()
    private let accountButton = WalletAccountButton()
    private let gapDots = (0..<3).map { _ in UIView() }
    private let separatorView = UIView()
    private let actionsPanel = ToolbarsActionsPanel()
    private let accountHoldRecognizer = UILongPressGestureRecognizer()
    private var configuration = ToolbarSettings.configuration()
    private var isAccountDragActive = false

    private static let horizontalInset: CGFloat = 12
    private static let topInset: CGFloat = 20
    private static let topBarHeight: CGFloat = 44
    private static let topBarSpacing: CGFloat = 10
    /// The screen between the two bars, which the dots stand for
    private static let barsGap: CGFloat = 52
    private static let dotSize: CGFloat = 4
    private static let dotSpacing: CGFloat = 8
    private static let panelSpacing: CGFloat = 16
    private static let holdDuration: TimeInterval = 0.25

    private static var stageHeight: CGFloat {
        topBarHeight + barsGap + HomeToolbarLayout.buttonSize
    }

    init() {
        super.init(frame: .zero)

        addSubview(stageView)
        for dot in gapDots {
            dot.backgroundColor = UIColor.air.secondaryLabel.withAlphaComponent(0.45)
            dot.layer.cornerRadius = Self.dotSize / 2
            dot.isUserInteractionEnabled = false
            stageView.addSubview(dot)
        }

        stageView.addSubview(tabsView)
        accountButton.translatesAutoresizingMaskIntoConstraints = true
        accountButton.accessibilityLabel = HomeToolbarItem.accounts.title
        stageView.addSubview(accountButton)

        // The stage supplies the frame; the toolbar's own constraints still need that width
        toolbar.translatesAutoresizingMaskIntoConstraints = true
        toolbar.setHomeConfiguration(configuration, animated: false)
        toolbar.setPresentation(.homeToolbar, animated: false)
        toolbar.accessibilityElementsHidden = true
        stageView.addSubview(toolbar)
        editor.dragsFixedItems = true
        editor.holdRecognizer.minimumPressDuration = Self.holdDuration
        toolbar.addGestureRecognizer(editor.holdRecognizer)

        accountHoldRecognizer.minimumPressDuration = Self.holdDuration
        accountHoldRecognizer.delegate = self
        accountHoldRecognizer.addTarget(self, action: #selector(handleAccountHold(_:)))
        stageView.addGestureRecognizer(accountHoldRecognizer)

        separatorView.backgroundColor = .air.separator
        addSubview(separatorView)

        actionsPanel.onLayoutChange = { [weak self] in self?.animateLayout() }
        actionsPanel.onAdd = { [weak self] item in self?.add(item) }
        actionsPanel.onDragBegin = { [weak self] item, standIn, frame, touch in
            self?.editor.beginExternalDrag(item: item, standIn: standIn, frame: frame, touch: touch) ?? false
        }
        actionsPanel.onDragMove = { [weak self] point in self?.editor.moveDrag(to: point) }
        actionsPanel.onDragEnd = { [weak self] point in
            guard let self else { return }
            if let point { editor.endDrag(at: point) } else { editor.cancel() }
        }
        addSubview(actionsPanel)

        stageView.isAccessibilityElement = true
        stageView.accessibilityLabel = lang("Toolbars")
        updateContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(account: MAccount?) {
        accountButton.configure(account: account)
        accountButton.accessibilityLabel = HomeToolbarItem.accounts.title
        toolbar.accountsButton.configure(account: account)
    }

    func setConfiguration(_ configuration: HomeToolbarConfiguration, animated: Bool) {
        guard !editor.isDragging else { return }
        let hasChanged = configuration != self.configuration
        self.configuration = configuration
        toolbar.setHomeConfiguration(configuration, animated: animated && window != nil)
        updateContent()
        guard hasChanged else { return }
        if animated, window != nil {
            animateLayout()
        } else {
            setNeedsLayout()
            notifyHeightChange()
        }
    }

    func getPreferredHeight(width: CGFloat) -> CGFloat {
        var height = Self.topInset + Self.stageHeight
        if actionsPanel.hasContent {
            height += Self.panelSpacing * 2 + actionsPanel.getSize(width: width - Self.horizontalInset * 2).height
        }
        return height + 14
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let isRightToLeft = effectiveUserInterfaceLayoutDirection == .rightToLeft
        stageView.frame = CGRect(
            x: Self.horizontalInset, y: Self.topInset,
            width: bounds.width - Self.horizontalInset * 2, height: Self.stageHeight
        )
        let content = stageView.bounds

        // The top bar: the tabs leave room for the account button on its side, and at both ends while it is dragged
        let isOnTop = !configuration.showsAccounts
        let reserve = Self.topBarHeight + Self.topBarSpacing
        let reservesStart = isAccountDragActive || (isOnTop && configuration.isAccountsAtStart)
        let reservesEnd = isAccountDragActive || (isOnTop && !configuration.isAccountsAtStart)
        var tabsFrame = CGRect(x: content.minX, y: content.minY, width: content.width, height: Self.topBarHeight)
        let (leftReserve, rightReserve) = isRightToLeft ? (reservesEnd, reservesStart) : (reservesStart, reservesEnd)
        if leftReserve {
            tabsFrame.origin.x += reserve
            tabsFrame.size.width -= reserve
        }
        if rightReserve { tabsFrame.size.width -= reserve }
        tabsView.frame = tabsFrame
        accountButton.frame = getAccountSlot(isAtStart: configuration.isAccountsAtStart)
        accountButton.setToolbarAppearance(showsBackground: isOnTop, showsContent: isOnTop)
        accountButton.isUserInteractionEnabled = false

        toolbar.frame = CGRect(
            x: content.minX, y: content.maxY - HomeToolbarLayout.buttonSize,
            width: content.width, height: HomeToolbarLayout.buttonSize
        )
        let dotsHeight = CGFloat(gapDots.count) * Self.dotSize + CGFloat(gapDots.count - 1) * Self.dotSpacing
        let dotsTop = Self.topBarHeight + (Self.barsGap - dotsHeight) / 2
        for (index, dot) in gapDots.enumerated() {
            dot.frame = CGRect(
                x: content.midX - Self.dotSize / 2, y: dotsTop + CGFloat(index) * (Self.dotSize + Self.dotSpacing),
                width: Self.dotSize, height: Self.dotSize
            )
        }

        let hasPanel = actionsPanel.hasContent
        separatorView.alpha = hasPanel ? 1 : 0
        actionsPanel.alpha = hasPanel ? 1 : 0
        separatorView.frame = CGRect(
            x: 16, y: stageView.frame.maxY + Self.panelSpacing,
            width: bounds.width - 32, height: 1 / max(1, traitCollection.displayScale)
        )
        let panelSize = actionsPanel.getSize(width: bounds.width - Self.horizontalInset * 2)
        actionsPanel.frame = CGRect(
            x: isRightToLeft ? bounds.width - Self.horizontalInset - panelSize.width : Self.horizontalInset,
            y: separatorView.frame.maxY + Self.panelSpacing,
            width: panelSize.width, height: panelSize.height
        )
        actionsPanel.layoutIfNeeded()
    }

    private func getAccountSlot(isAtStart: Bool) -> CGRect {
        let content = stageView.bounds
        let isOnLeft = isAtStart != (effectiveUserInterfaceLayoutDirection == .rightToLeft)
        return CGRect(
            x: isOnLeft ? content.minX : content.maxX - Self.topBarHeight, y: content.minY,
            width: Self.topBarHeight, height: Self.topBarHeight
        )
    }

    /// The actions the toolbar does not show, and whether it has room for one more
    private func updateContent() {
        let items = HomeToolbarItem.actionItems.filter { !configuration.isShown($0) }
        actionsPanel.items = items
        actionsPanel.isFull = items.first.map { !toolbar.canHoldHomeItem($0, in: configuration) } ?? false
        stageView.accessibilityValue = configuration.visibleItems.map(\.title).joined(separator: ", ")
        stageView.accessibilityCustomActions = configuration.visibleItems.filter(\.isHideable).map { item in
            UIAccessibilityCustomAction(name: "\(lang("Remove")): \(item.title)") { [weak self] _ in
                self?.update { $0.setShown(false, item) }
                return true
            }
        } + (configuration.showsAccounts ? [] : [
            UIAccessibilityCustomAction(name: "\(lang("Add")): \(HomeToolbarItem.accounts.title)") { [weak self] _ in
                self?.add(.accounts)
                return true
            },
        ])
    }

    private func add(_ item: HomeToolbarItem) {
        guard toolbar.canHoldHomeItem(item, in: configuration) else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        update { configuration in
            configuration.setShown(true, item)
            // A tapped button joins the ones after the search field ahead of the actions button, which stays last
            guard let itemIndex = configuration.order.firstIndex(of: item),
                  let actionsIndex = configuration.order.firstIndex(of: .actions),
                  let searchIndex = configuration.order.firstIndex(of: .search),
                  searchIndex < actionsIndex, actionsIndex < itemIndex else { return }
            configuration.order.remove(at: itemIndex)
            configuration.order.insert(item, at: actionsIndex)
        }
    }

    private func update(_ change: (inout HomeToolbarConfiguration) -> Void) {
        var configuration = ToolbarSettings.configuration()
        change(&configuration)
        ToolbarSettings.setConfiguration(configuration)
        setConfiguration(configuration, animated: true)
    }

    private func animateLayout() {
        setNeedsLayout()
        UIView.animate(withDuration: 0.42, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0,
                       options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.layoutIfNeeded()
        }
        notifyHeightChange()
    }

    private func notifyHeightChange() {
        // SwiftUI measures and updates this view during its own update pass
        DispatchQueue.main.async { [weak self] in
            self?.onHeightChange?()
        }
    }

    @objc private func handleAccountHold(_ recognizer: UILongPressGestureRecognizer) {
        editor.handleTopAccountHold(recognizer, isAtStart: configuration.isAccountsAtStart)
    }

    // MARK: - HomeToolbarEditorHost

    var toolbarEditorConfiguration: HomeToolbarConfiguration { ToolbarSettings.configuration() }
    var canEditToolbar: Bool { window != nil }
    var toolbarEditorShelf: (any HomeToolbarEditorShelf)? { actionsPanel }

    func getToolbarEditorDisplayedConfiguration(_ configuration: HomeToolbarConfiguration) -> HomeToolbarConfiguration {
        configuration
    }

    func commitToolbarEditorConfiguration(_ configuration: HomeToolbarConfiguration) {
        ToolbarSettings.setConfiguration(configuration)
        self.configuration = configuration
        updateContent()
        animateLayout()
    }

    func getTopAccountFrame(isAtStart: Bool) -> CGRect? {
        guard window != nil else { return nil }
        return stageView.convert(getAccountSlot(isAtStart: isAtStart), to: nil)
    }

    func setTopAccountHeld(_ isHeld: Bool) {
        accountButton.alpha = isHeld ? 0 : 1
    }

    func setTopAccountDragActive(_ isActive: Bool) {
        guard isActive != isAccountDragActive else { return }
        isAccountDragActive = isActive
        animateLayout()
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !configuration.showsAccounts && accountButton.frame.contains(touch.location(in: stageView))
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // A finger resting on the account button is not scrolling the settings
        otherGestureRecognizer is UIPanGestureRecognizer
    }
}

// MARK: - Top bar tabs

/// The top bar's tabs as a still picture
@MainActor
private final class ToolbarsPreviewTabsView: UIView {
    private let glassView = ToolbarsGlassView(maximumCornerRadius: nil, isInteractive: false)
    private let clipView = UIView()
    private let selectionView = UIView()
    private let labels: [UILabel] = [lang("Wallet"), lang("Market"), lang("Agent"), lang("Explore")].map { title in
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textAlignment = .center
        return label
    }

    private static let tabWidth: CGFloat = 84

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        addSubview(glassView)
        clipView.clipsToBounds = true
        clipView.layer.cornerCurve = .continuous
        glassView.contentView.addSubview(clipView)
        selectionView.backgroundColor = UIColor.label.withAlphaComponent(0.08)
        selectionView.layer.cornerCurve = .continuous
        clipView.addSubview(selectionView)
        for (index, label) in labels.enumerated() {
            label.textColor = index == 0 ? .tintColor : .air.secondaryLabel
            clipView.addSubview(label)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        glassView.frame = bounds
        clipView.frame = bounds
        clipView.layer.cornerRadius = bounds.height / 2
        let isRightToLeft = effectiveUserInterfaceLayoutDirection == .rightToLeft
        // The tabs keep their width and run off the far end, as the real ones scroll
        for (index, label) in labels.enumerated() {
            let x = 4 + CGFloat(index) * Self.tabWidth
            label.frame = CGRect(
                x: isRightToLeft ? bounds.width - x - Self.tabWidth : x, y: 0,
                width: Self.tabWidth, height: bounds.height
            )
        }
        selectionView.frame = labels[0].frame.insetBy(dx: 0, dy: 4)
        selectionView.layer.cornerRadius = selectionView.bounds.height / 2
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        labels[0].textColor = tintColor
    }
}

// MARK: - More actions

/// A glass button that opens into the actions the toolbar does not show. A tap on an action adds it to the toolbar,
/// and a held action lifts to be dropped there. A button dragged off the toolbar drops here, and the grid keeps its
/// place while it would.
@MainActor
private final class ToolbarsActionsPanel: UIView, UIGestureRecognizerDelegate, HomeToolbarEditorShelf {
    /// The panel needs another size or arrangement, which its owner animates
    var onLayoutChange: (() -> Void)?
    var onAdd: ((HomeToolbarItem) -> Void)?
    /// A held action lifts as `standIn`, at a frame and under a finger in window coordinates
    var onDragBegin: ((HomeToolbarItem, UIView, CGRect, CGPoint) -> Bool)?
    var onDragMove: ((CGPoint) -> Void)?
    /// `nil` for a drag the system took away
    var onDragEnd: ((CGPoint?) -> Void)?

    /// The actions the toolbar does not show
    var items: [HomeToolbarItem] = [] {
        didSet {
            if items != oldValue { reloadTiles() }
        }
    }
    var isFull = false {
        didSet {
            if isFull != oldValue { setNeedsLayout() }
        }
    }
    private(set) var isExpanded = false
    var hasContent: Bool { !displayedItems.isEmpty }

    // The glass does not react to touches: a held action would leave it pressed for the whole drag
    private let glassView = ToolbarsGlassView(maximumCornerRadius: 24, isInteractive: false)
    private let clipView = UIView()
    private let headerControl = UIControl()
    private let plusView = UIImageView(image: UIImage(
        systemName: "plus",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
    ))
    private let titleLabel = UILabel()
    private let fullLabel = UILabel()
    private var tiles: [HomeToolbarItem: ToolbarsActionTile] = [:]
    /// The button being dragged, and whether a drop now would leave it here
    private var drag: (item: HomeToolbarItem, staysOnShelf: Bool)?
    /// A held action of this panel is being dragged
    private var isTrackingHold = false

    private static let headerHeight: CGFloat = 44
    private static let columns = 4
    private static let rowHeight: CGFloat = 76
    private static let holdDuration: TimeInterval = 0.25

    /// The grid as a drop now would leave it: without a button the toolbar is taking, and with one it is giving up
    private var displayedItems: [HomeToolbarItem] {
        guard let drag else { return items }
        var shown = Set(items)
        if drag.staysOnShelf { shown.insert(drag.item) } else { shown.remove(drag.item) }
        return HomeToolbarItem.actionItems.filter(shown.contains)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(glassView)
        clipView.clipsToBounds = true
        clipView.layer.cornerCurve = .continuous
        glassView.contentView.addSubview(clipView)

        plusView.contentMode = .center
        titleLabel.text = lang("More Actions")
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        headerControl.addSubview(plusView)
        headerControl.addSubview(titleLabel)
        headerControl.isAccessibilityElement = true
        headerControl.accessibilityLabel = titleLabel.text
        headerControl.accessibilityTraits = .button
        headerControl.accessibilityIdentifier = "appearance.toolbar.moreActions"
        headerControl.addTarget(self, action: #selector(toggle), for: .touchUpInside)
        headerControl.addTarget(self, action: #selector(highlightHeader), for: [.touchDown, .touchDragEnter])
        headerControl.addTarget(self, action: #selector(unhighlightHeader), for: [.touchUpInside, .touchDragExit, .touchCancel])
        clipView.addSubview(headerControl)

        let fullText = NSMutableAttributedString(
            string: lang("$toolbar_full_title"),
            attributes: [.font: UIFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: UIColor.label]
        )
        fullText.append(NSAttributedString(
            string: "\n" + lang("$toolbar_full_hint"),
            attributes: [.font: UIFont.systemFont(ofSize: 13), .foregroundColor: UIColor.air.secondaryLabel]
        ))
        fullLabel.attributedText = fullText
        fullLabel.numberOfLines = 0
        fullLabel.textAlignment = .center
        clipView.addSubview(fullLabel)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.delegate = self
        clipView.addGestureRecognizer(tap)
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(handleHold(_:)))
        hold.minimumPressDuration = Self.holdDuration
        hold.delegate = self
        clipView.addGestureRecognizer(hold)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The button's own size, or the panel's in a column `width` wide
    func getSize(width: CGFloat) -> CGSize {
        guard isExpanded else {
            return CGSize(width: min(width, 14 + 20 + 6 + ceil(titleLabel.intrinsicContentSize.width) + 18), height: Self.headerHeight)
        }
        // A panel a drag has emptied keeps a row for the button to come back to
        let rows = max(1, (displayedItems.count + Self.columns - 1) / Self.columns)
        var height = Self.headerHeight + CGFloat(rows) * Self.rowHeight + 6
        if isFull { height += getFullLabelHeight(width: width) + 12 }
        return CGSize(width: width, height: height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        glassView.frame = bounds
        clipView.frame = bounds
        clipView.layer.cornerRadius = min(24, bounds.height / 2)
        let isRightToLeft = effectiveUserInterfaceLayoutDirection == .rightToLeft
        headerControl.frame = CGRect(x: 0, y: 0, width: bounds.width, height: Self.headerHeight)
        let titleWidth = ceil(titleLabel.intrinsicContentSize.width)
        plusView.bounds.size = CGSize(width: 20, height: 20)
        plusView.center = CGPoint(x: isRightToLeft ? bounds.width - 24 : 24, y: Self.headerHeight / 2)
        // Open, the plus is the cross that closes the panel
        plusView.transform = isExpanded ? CGAffineTransform(rotationAngle: .pi / 4) : .identity
        titleLabel.frame = CGRect(
            x: isRightToLeft ? bounds.width - 40 - titleWidth : 40, y: 0,
            width: titleWidth, height: Self.headerHeight
        )
        // Closed, the button itself is where a dragged button would drop
        let headerColor: UIColor = drag?.staysOnShelf == true && !isExpanded ? .tintColor : .label
        plusView.tintColor = headerColor
        titleLabel.textColor = headerColor

        // The tiles keep their places in the open panel's grid, where the closed button clips them away
        let displayedItems = displayedItems
        let gridWidth = getGridWidth()
        let tileWidth = gridWidth / CGFloat(Self.columns)
        for (item, tile) in tiles {
            guard let index = displayedItems.firstIndex(of: item) else {
                tile.alpha = 0
                continue
            }
            let column = index % Self.columns
            tile.frame = CGRect(
                x: CGFloat(isRightToLeft ? Self.columns - 1 - column : column) * tileWidth,
                y: Self.headerHeight + CGFloat(index / Self.columns) * Self.rowHeight,
                width: tileWidth, height: Self.rowHeight
            )
            tile.alpha = getTileAlpha(item)
        }
        let rows = max(1, (displayedItems.count + Self.columns - 1) / Self.columns)
        fullLabel.frame = CGRect(
            x: 16, y: Self.headerHeight + CGFloat(rows) * Self.rowHeight + 4,
            width: gridWidth - 32, height: getFullLabelHeight(width: gridWidth)
        )
        fullLabel.alpha = isExpanded && isFull ? 1 : 0
    }

    private func getGridWidth() -> CGFloat {
        isExpanded ? bounds.width : (superview?.bounds.width ?? bounds.width) - 24
    }

    /// A dragged button's place in the grid stays empty until its copy has landed on it
    private func getTileAlpha(_ item: HomeToolbarItem) -> CGFloat {
        guard isExpanded, item != drag?.item else { return 0 }
        return isFull ? 0.4 : 1
    }

    private func getFullLabelHeight(width: CGFloat) -> CGFloat {
        ceil(fullLabel.sizeThatFits(CGSize(width: width - 32, height: .greatestFiniteMagnitude)).height)
    }

    private func reloadTiles() {
        let needed = Set(items).union(drag.map { [$0.item] } ?? [])
        for (item, tile) in tiles where !needed.contains(item) {
            tile.removeFromSuperview()
            tiles[item] = nil
        }
        for item in needed where tiles[item] == nil {
            let tile = ToolbarsActionTile(item: item)
            tile.onActivate = { [weak self] in self?.onAdd?(item) }
            tile.alpha = 0
            // A new tile comes up in its place rather than from the panel's corner
            if let index = displayedItems.firstIndex(of: item) {
                let tileWidth = getGridWidth() / CGFloat(Self.columns)
                let column = index % Self.columns
                let isRightToLeft = effectiveUserInterfaceLayoutDirection == .rightToLeft
                tile.frame = CGRect(
                    x: CGFloat(isRightToLeft ? Self.columns - 1 - column : column) * tileWidth,
                    y: Self.headerHeight + CGFloat(index / Self.columns) * Self.rowHeight,
                    width: tileWidth, height: Self.rowHeight
                )
            }
            clipView.addSubview(tile)
            tiles[item] = tile
        }
        if !hasContent { isExpanded = false }
        setNeedsLayout()
    }

    private func getItem(at point: CGPoint) -> HomeToolbarItem? {
        guard isExpanded else { return nil }
        return displayedItems.first { tiles[$0]?.frame.contains(point) == true }
    }

    // MARK: HomeToolbarEditorShelf

    func setDraggedItem(_ item: HomeToolbarItem, staysOnShelf: Bool) {
        drag = (item, staysOnShelf)
        reloadTiles()
        onLayoutChange?()
    }

    func getLandingFrame(for item: HomeToolbarItem) -> (frame: CGRect, isAbsorbed: Bool) {
        superview?.layoutIfNeeded()
        if isExpanded, let tile = tiles[item], displayedItems.contains(item) {
            return (tile.convert(tile.circleFrame, to: nil), false)
        }
        return (plusView.convert(plusView.bounds, to: nil), true)
    }

    func endDrag() {
        guard let item = drag?.item else { return }
        drag = nil
        // The landed copy is gone in the same frame, so the tile takes its place at once
        UIView.performWithoutAnimation {
            tiles[item]?.alpha = items.contains(item) ? getTileAlpha(item) : 0
        }
        reloadTiles()
        onLayoutChange?()
    }

    // MARK: Touches

    @objc private func highlightHeader() {
        plusView.alpha = 0.4
        titleLabel.alpha = 0.4
    }

    @objc private func unhighlightHeader() {
        UIView.animate(withDuration: 0.25) {
            self.plusView.alpha = 1
            self.titleLabel.alpha = 1
        }
    }

    @objc private func toggle() {
        isExpanded.toggle()
        UISelectionFeedbackGenerator().selectionChanged()
        onLayoutChange?()
        UIAccessibility.post(notification: .layoutChanged, argument: isExpanded ? items.first.flatMap { tiles[$0] } : headerControl)
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard let item = getItem(at: recognizer.location(in: clipView)) else { return }
        onAdd?(item)
    }

    @objc private func handleHold(_ recognizer: UILongPressGestureRecognizer) {
        let point = recognizer.location(in: nil)
        switch recognizer.state {
        case .began:
            guard let item = getItem(at: recognizer.location(in: clipView)), let tile = tiles[item] else { return }
            isTrackingHold = onDragBegin?(item, tile.makeStandIn(), tile.convert(tile.circleFrame, to: nil), point) == true
        case .changed:
            if isTrackingHold { onDragMove?(point) }
        case .ended, .cancelled, .failed:
            guard isTrackingHold else { return }
            isTrackingHold = false
            onDragEnd?(recognizer.state == .ended ? point : nil)
        default:
            break
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        drag == nil && getItem(at: touch.location(in: clipView)) != nil
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // A finger resting on an action is not scrolling the settings
        gestureRecognizer is UILongPressGestureRecognizer && otherGestureRecognizer is UIPanGestureRecognizer
    }
}

@MainActor
private final class ToolbarsActionTile: UIView {
    /// VoiceOver activated the tile, which takes no touches of its own
    var onActivate: (() -> Void)?

    private let circleView = UIView()
    private let imageView = UIImageView()
    private let titleLabel = UILabel()

    private static let circleSize = HomeToolbarLayout.buttonSize

    var circleFrame: CGRect { circleView.frame }

    init(item: HomeToolbarItem) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        circleView.backgroundColor = UIColor.label.withAlphaComponent(0.06)
        circleView.layer.cornerRadius = Self.circleSize / 2
        addSubview(circleView)
        imageView.image = item.makeToolbarImage()
        imageView.tintColor = .label
        imageView.contentMode = .center
        circleView.addSubview(imageView)
        titleLabel.text = item.title
        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .air.secondaryLabel
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.8
        addSubview(titleLabel)
        isAccessibilityElement = true
        accessibilityLabel = item.title
        accessibilityHint = lang("Add")
        accessibilityTraits = .button
        accessibilityIdentifier = "appearance.toolbar.add.\(item.rawValue)"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        circleView.frame = CGRect(x: bounds.midX - Self.circleSize / 2, y: 2, width: Self.circleSize, height: Self.circleSize)
        imageView.frame = circleView.bounds
        titleLabel.frame = CGRect(x: 2, y: circleView.frame.maxY + 5, width: bounds.width - 4, height: 14)
    }

    /// The tile's circle, for the copy that leaves the panel under the finger
    func makeStandIn() -> UIView {
        let view = UIView(frame: CGRect(origin: .zero, size: circleView.bounds.size))
        view.backgroundColor = circleView.backgroundColor
        view.layer.cornerRadius = circleView.layer.cornerRadius
        let image = UIImageView(image: imageView.image)
        image.tintColor = imageView.tintColor
        image.contentMode = .center
        image.frame = view.bounds
        image.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(image)
        return view
    }

    override func accessibilityActivate() -> Bool {
        onActivate?()
        return true
    }
}

/// A piece of glass, or of blur material before iOS 26
@MainActor
private final class ToolbarsGlassView: UIView {
    var contentView: UIView { effectView.contentView }
    private let effectView = UIVisualEffectView()
    private let maximumCornerRadius: CGFloat?

    /// - Parameter maximumCornerRadius: The corners of a view too tall to be a capsule; `nil` keeps it a capsule
    init(maximumCornerRadius: CGFloat?, isInteractive: Bool) {
        self.maximumCornerRadius = maximumCornerRadius
        super.init(frame: .zero)
        if IOS_26_MODE_ENABLED, #available(iOS 26, *) {
            let effect = UIGlassEffect(style: .regular)
            effect.isInteractive = isInteractive
            effectView.effect = effect
        } else {
            effectView.effect = UIBlurEffect(style: .systemMaterial)
            effectView.clipsToBounds = true
            effectView.layer.cornerCurve = .continuous
        }
        addSubview(effectView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        effectView.frame = bounds
        let radius = min(maximumCornerRadius ?? .greatestFiniteMagnitude, bounds.height / 2)
        if IOS_26_MODE_ENABLED, #available(iOS 26, *) {
            effectView.cornerConfiguration = .corners(radius: .fixed(radius))
        } else {
            effectView.layer.cornerRadius = radius
        }
    }
}
