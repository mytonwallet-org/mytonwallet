import UIKit

@MainActor
final class ContextMenuPageView: UIView {
    private struct LayoutResult {
        let frames: [CGRect]
        let contentSize: CGSize
    }

    private enum Element {
        case row(ContextMenuPageRowElement)
        case separator(ContextMenuSeparatorView)

        var view: UIView {
            switch self {
            case let .row(row):
                return row.view
            case let .separator(view):
                return view
            }
        }
    }

    let page: ContextMenuPage
    private let style: ContextMenuStyle
    private let sourceUserInterfaceLayoutDirection: UIUserInterfaceLayoutDirection
    private let customRowContext: ContextMenuCustomRowContext
    weak var delegate: ContextMenuPageViewDelegate?

    private let scrollView = ContextMenuScrollView()
    private let contentView = UIView()
    private let selectionView = UIView()
    private let selectionTouchView = ContextMenuSelectionTouchView()

    private var elements: [Element] = []
    private var highlightedRowIndex: Int?
    private var activeSelectionWindowPoint: CGPoint?
    private var autoScrollDisplayLink: CADisplayLink?
    private var autoScrollVelocity: CGFloat = 0.0
    private var allowsImmediateSelection = false
    private var isCancellingImmediateSelectionForHorizontalPan = false
    private let feedbackGenerator = UISelectionFeedbackGenerator()
    private var reorderHold: (rowIndex: Int, contentPoint: CGPoint, timer: Timer)?
    private var reorderTouchContentPoint: CGPoint?
    private var liftedRow: (view: UIView, touchOffsetY: CGFloat)?
    /// In a menu that scrolls the rows take their own touches, so a long press lifts a row there: a touch resting
    /// still on a row for the long-press time lifts it, and a touch that scrolls the menu first fails it
    private lazy var scrollingReorderRecognizer: UILongPressGestureRecognizer = {
        let recognizer = UILongPressGestureRecognizer(
            target: self,
            action: #selector(self.handleScrollingReorderPress(_:))
        )
        recognizer.minimumPressDuration = Self.reorderHoldDuration
        recognizer.allowableMovement = Self.reorderHoldSlop
        recognizer.delegate = self
        recognizer.isEnabled = false
        return recognizer
    }()
    private var scrollingReorderWindowPoint: CGPoint?

    var allowsBackNavigationGesture = false
    /// The menu's corner radius when the presentation sets it rather than the style, as a system popover does
    var menuCornerRadius: CGFloat?

    init(
        page: ContextMenuPage,
        style: ContextMenuStyle,
        sourceUserInterfaceLayoutDirection: UIUserInterfaceLayoutDirection,
        customRowContext: ContextMenuCustomRowContext
    ) {
        self.page = page
        self.style = style
        self.sourceUserInterfaceLayoutDirection = sourceUserInterfaceLayoutDirection
        self.customRowContext = customRowContext

        super.init(frame: .zero)

        self.semanticContentAttribute = sourceUserInterfaceLayoutDirection.contextMenuSemanticContentAttribute

        self.scrollView.showsVerticalScrollIndicator = false
        self.scrollView.alwaysBounceVertical = false
        self.scrollView.delaysContentTouches = true
        self.scrollView.canCancelContentTouches = true
        // Menu pages lay out their own insets, including underneath a navigation bar.
        self.scrollView.contentInsetAdjustmentBehavior = .never
        if #available(iOS 26.0, *) {
            self.scrollView.topEdgeEffect.isHidden = true
        }

        self.selectionView.alpha = 0.0
        self.selectionView.isUserInteractionEnabled = false
        self.selectionView.layer.cornerCurve = .continuous

        self.addSubview(self.scrollView)
        self.scrollView.addSubview(self.contentView)
        self.scrollView.addGestureRecognizer(self.scrollingReorderRecognizer)
        self.contentView.addSubview(self.selectionView)
        self.addSubview(self.selectionTouchView)

        self.selectionTouchView.isHidden = true
        self.selectionTouchView.onBegan = { [weak self] point in
            self?.handleSelectionTouchBegan(point)
        }
        self.selectionTouchView.onMoved = { [weak self] initialPoint, point in
            self?.handleSelectionTouchMoved(initialPoint: initialPoint, point: point)
        }
        self.selectionTouchView.onEnded = { [weak self] point, performAction in
            self?.handleSelectionTouchEnded(point: point, performAction: performAction)
        }

        self.rebuildElements()
        self.updateColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if previousTraitCollection?.userInterfaceStyle != self.traitCollection.userInterfaceStyle {
            self.updateSelectionColors()
        }
    }

    func preferredSize(constrainedTo constrainedSize: CGSize) -> CGSize {
        let clampedWidth = max(0.0, min(self.style.maxWidth, constrainedSize.width))
        let clampedMinWidth = min(self.style.minWidth, clampedWidth)
        let contentSize = self.measuredContentSize(maxWidth: clampedWidth)
        return CGSize(
            width: min(clampedWidth, max(clampedMinWidth, contentSize.width)).rounded(.up),
            height: min(constrainedSize.height, contentSize.height).rounded(.up)
        )
    }

    func applyLayout(size: CGSize) {
        self.scrollView.frame = CGRect(origin: .zero, size: size)
        self.selectionTouchView.frame = self.scrollView.frame

        let layoutResult = self.layoutResult(width: size.width)
        for (element, frame) in zip(self.elements, layoutResult.frames) {
            if element.view === self.liftedRow?.view {
                // The lifted row keeps following the finger
                element.view.bounds.size = frame.size
            } else {
                element.view.frame = frame
            }
            if case let .row(row) = element {
                row.applyLayout(size: frame.size)
            }
        }

        self.contentView.frame = CGRect(origin: .zero, size: layoutResult.contentSize)
        self.scrollView.contentSize = self.contentView.bounds.size
        self.updateImmediateSelectionAvailability(
            viewportSize: size,
            contentHeight: layoutResult.contentSize.height
        )

        if let liftedRow {
            self.selectionView.center = liftedRow.view.center
        } else if let highlightedRowIndex {
            self.updateHighlight(index: highlightedRowIndex, animated: false, emitFeedback: false)
        } else {
            self.selectionView.frame = .zero
        }
    }

    func restoreVisualState() {
        self.cancelReorderHold()
        self.dropLiftedRow()
        self.activeSelectionWindowPoint = nil
        self.isCancellingImmediateSelectionForHorizontalPan = false
        self.stopAutoScroll()
        self.updateHighlight(index: nil, animated: true, emitFeedback: false)
    }

    func beginExternalSelection(windowPoint: CGPoint) {
        self.activeSelectionWindowPoint = windowPoint
        self.feedbackGenerator.prepare()
        self.updateExternalSelection(windowPoint: windowPoint)
    }

    /// The finger that opened the menu from its source only selects, however long it rests on a row: a row lifts
    /// for a new touch that goes down on it and holds
    func updateExternalSelection(windowPoint: CGPoint) {
        self.activeSelectionWindowPoint = windowPoint

        let scrollPoint = self.scrollView.convert(windowPoint, from: nil)
        self.updateAutoScrollIfNeeded(scrollPoint: scrollPoint)

        let contentPoint = self.contentView.convert(windowPoint, from: nil)
        self.updateHighlight(index: self.rowIndex(at: contentPoint), animated: true, emitFeedback: true)
    }

    func endExternalSelection(performAction: Bool) {
        self.activeSelectionWindowPoint = nil
        self.stopAutoScroll()

        let highlightedIndex = self.highlightedRowIndex
        self.updateHighlight(index: nil, animated: true, emitFeedback: false)

        guard performAction, let highlightedIndex else {
            return
        }
        self.activateRow(at: highlightedIndex)
    }

    private func rebuildElements() {
        self.elements.forEach { $0.view.removeFromSuperview() }
        self.elements.removeAll()

        for item in self.page.items {
            switch item {
            case let .action(action):
                let rowView = ContextMenuRowView(
                    presentation: ContextMenuRowPresentation(
                        title: action.title,
                        subtitle: action.subtitle,
                        icon: action.icon,
                        badgeText: action.badgeText,
                        role: action.role,
                        isEnabled: action.isEnabled,
                        accessory: .none,
                        accessibilityIdentifier: action.accessibilityIdentifier,
                        animatedIcon: action.animatedIcon
                    ),
                    style: self.style,
                    sourceUserInterfaceLayoutDirection: self.sourceUserInterfaceLayoutDirection
                )
                let row = ContextMenuPageRowElement(
                    view: rowView,
                    controlView: rowView,
                    isSelectable: true,
                    isEnabled: action.isEnabled,
                    allowsImmediateSelectionCapture: true,
                    activation: .trigger(ContextMenuActivation(dismissesMenu: action.dismissesMenu, handler: action.handler)),
                    measuredSize: { rowView.measuredSize(maxWidth: $0) },
                    applyLayout: { rowView.applyLayout(size: $0) },
                    updateColors: {
                        rowView.updateColors()
                        rowView.updateBadge()
                    },
                    setDirectInteractionEnabled: { rowView.isUserInteractionEnabled = $0 },
                    onHighlight: { rowView.playIconAnimation() }
                )
                self.installHandlers(on: row)
                self.contentView.addSubview(rowView)
                self.elements.append(.row(row))
            case let .back(backAction):
                let rowView = ContextMenuRowView(
                    presentation: ContextMenuRowPresentation(
                        title: backAction.title,
                        subtitle: nil,
                        icon: backAction.icon,
                        badgeText: nil,
                        role: .normal,
                        isEnabled: backAction.isEnabled,
                        accessory: .none
                    ),
                    style: self.style,
                    sourceUserInterfaceLayoutDirection: self.sourceUserInterfaceLayoutDirection
                )
                let row = ContextMenuPageRowElement(
                    view: rowView,
                    controlView: rowView,
                    isSelectable: true,
                    isEnabled: backAction.isEnabled,
                    allowsImmediateSelectionCapture: true,
                    activation: .back,
                    measuredSize: { rowView.measuredSize(maxWidth: $0) },
                    applyLayout: { rowView.applyLayout(size: $0) },
                    updateColors: {
                        rowView.updateColors()
                        rowView.updateBadge()
                    },
                    setDirectInteractionEnabled: { rowView.isUserInteractionEnabled = $0 }
                )
                self.installHandlers(on: row)
                self.contentView.addSubview(rowView)
                self.elements.append(.row(row))
            case let .submenu(submenu):
                let rowView = ContextMenuRowView(
                    presentation: ContextMenuRowPresentation(
                        title: submenu.title,
                        subtitle: submenu.subtitle,
                        icon: submenu.icon,
                        badgeText: submenu.badgeText,
                        role: .normal,
                        isEnabled: submenu.isEnabled,
                        accessory: .disclosure
                    ),
                    style: self.style,
                    sourceUserInterfaceLayoutDirection: self.sourceUserInterfaceLayoutDirection
                )
                let row = ContextMenuPageRowElement(
                    view: rowView,
                    controlView: rowView,
                    isSelectable: true,
                    isEnabled: submenu.isEnabled,
                    allowsImmediateSelectionCapture: true,
                    activation: .submenu(submenu.makePage()),
                    measuredSize: { rowView.measuredSize(maxWidth: $0) },
                    applyLayout: { rowView.applyLayout(size: $0) },
                    updateColors: {
                        rowView.updateColors()
                        rowView.updateBadge()
                    },
                    setDirectInteractionEnabled: { rowView.isUserInteractionEnabled = $0 }
                )
                self.installHandlers(on: row)
                self.contentView.addSubview(rowView)
                self.elements.append(.row(row))
            case let .custom(customRow):
                let rowView = ContextMenuCustomRowView(item: customRow, context: self.customRowContext)
                let activation: ContextMenuPageAction?
                if let submenuPage = customRow.interaction.submenuPage {
                    activation = .submenu(submenuPage)
                } else if customRow.interaction.isSelectable {
                    activation = .trigger(ContextMenuActivation(
                        dismissesMenu: customRow.interaction.dismissesMenu,
                        handler: customRow.interaction.handler
                    ))
                } else {
                    activation = nil
                }
                let row = ContextMenuPageRowElement(
                    view: rowView,
                    controlView: customRow.interaction.isSelectable ? rowView : nil,
                    isSelectable: customRow.interaction.isSelectable,
                    isEnabled: customRow.interaction.isEnabled,
                    allowsImmediateSelectionCapture: !customRow.interaction.allowsContentInteraction,
                    activation: activation,
                    measuredSize: { rowView.measuredSize(maxWidth: $0) },
                    applyLayout: { rowView.applyLayout(size: $0) },
                    updateColors: { rowView.updateColors() },
                    setDirectInteractionEnabled: { isEnabled in
                        guard customRow.interaction.isSelectable else {
                            rowView.isUserInteractionEnabled = true
                            return
                        }
                        rowView.isUserInteractionEnabled = isEnabled
                    }
                )
                self.installHandlers(on: row)
                self.contentView.addSubview(rowView)
                self.elements.append(.row(row))
            case .separator:
                let separatorView = ContextMenuSeparatorView(style: self.style)
                self.contentView.addSubview(separatorView)
                self.elements.append(.separator(separatorView))
            }
        }
    }

    private func installHandlers(on row: ContextMenuPageRowElement) {
        guard let controlView = row.controlView, row.isSelectable else {
            return
        }
        controlView.addTarget(self, action: #selector(self.rowTouchDown(_:)), for: .touchDown)
        controlView.addTarget(self, action: #selector(self.rowTouchEnter(_:)), for: .touchDragEnter)
        controlView.addTarget(self, action: #selector(self.rowTouchExit(_:)), for: [.touchDragExit, .touchCancel, .touchUpOutside])
        controlView.addTarget(self, action: #selector(self.rowActivated(_:)), for: .touchUpInside)
    }

    private func measuredContentSize(maxWidth: CGFloat) -> CGSize {
        if case .grid = self.page.layout {
            return self.layoutResult(width: maxWidth).contentSize
        }

        var width = self.style.minWidth
        var height: CGFloat = 0.0
        var rowIndex = 0

        for element in self.elements {
            switch element {
            case let .row(row):
                if rowIndex == 0 {
                    height += self.style.listVerticalPadding
                }
                let measuredSize = row.measuredSize(maxWidth: maxWidth)
                width = max(width, measuredSize.width)
                height += measuredSize.height
                rowIndex += 1
            case .separator:
                height += self.style.separatorHeight
            }
        }

        if rowIndex > 0 {
            height += self.style.listVerticalPadding
        }

        return CGSize(width: width, height: height)
    }

    private func layoutResult(width: CGFloat) -> LayoutResult {
        switch self.page.layout {
        case .list:
            return self.listLayoutResult(width: width)
        case let .grid(layout):
            return self.gridLayoutResult(width: width, layout: layout)
        }
    }

    private func listLayoutResult(width: CGFloat) -> LayoutResult {
        var frames = Array(repeating: CGRect.zero, count: self.elements.count)
        var contentHeight: CGFloat = 0.0
        var firstRow = true

        for (index, element) in self.elements.enumerated() {
            switch element {
            case let .row(row):
                if firstRow {
                    contentHeight += self.style.listVerticalPadding
                    firstRow = false
                }
                let rowSize = row.measuredSize(maxWidth: width)
                let rowFrame = CGRect(x: 0.0, y: contentHeight, width: width, height: rowSize.height)
                frames[index] = rowFrame
                contentHeight += rowFrame.height
            case .separator:
                let separatorFrame = CGRect(
                    x: 0.0,
                    y: contentHeight,
                    width: width,
                    height: self.style.separatorHeight
                )
                frames[index] = separatorFrame
                contentHeight += separatorFrame.height
            }
        }

        if !firstRow {
            contentHeight += self.style.listVerticalPadding
        }
        return LayoutResult(
            frames: frames,
            contentSize: CGSize(width: width, height: contentHeight)
        )
    }

    private func gridLayoutResult(width: CGFloat, layout: ContextMenuGridLayout) -> LayoutResult {
        var frames = Array(repeating: CGRect.zero, count: self.elements.count)
        let columns = max(1, layout.columns)
        let availableWidth = max(
            0.0,
            width
                - layout.contentInsets.left
                - layout.contentInsets.right
        )
        let columnWidth = availableWidth / CGFloat(columns)
        var contentHeight = layout.contentInsets.top
        var elementIndex = 0

        while elementIndex < self.elements.count {
            switch self.elements[elementIndex] {
            case .separator:
                frames[elementIndex] = CGRect(
                    x: layout.contentInsets.left,
                    y: contentHeight,
                    width: availableWidth,
                    height: self.style.separatorHeight
                )
                contentHeight += self.style.separatorHeight
                elementIndex += 1
            case .row:
                var rowElementIndices: [Int] = []
                while elementIndex < self.elements.count,
                      rowElementIndices.count < columns,
                      case .row = self.elements[elementIndex] {
                    rowElementIndices.append(elementIndex)
                    elementIndex += 1
                }

                let rowHeight = rowElementIndices.reduce(CGFloat.zero) { partialResult, index in
                    guard case let .row(row) = self.elements[index] else {
                        return partialResult
                    }
                    return max(partialResult, row.measuredSize(maxWidth: columnWidth).height)
                }
                for (column, index) in rowElementIndices.enumerated() {
                    let visualColumn = self.sourceUserInterfaceLayoutDirection.contextMenuIsRightToLeft
                        ? columns - column - 1
                        : column
                    frames[index] = CGRect(
                        x: layout.contentInsets.left
                            + CGFloat(visualColumn) * columnWidth,
                        y: contentHeight,
                        width: columnWidth,
                        height: rowHeight
                    )
                }
                contentHeight += rowHeight
            }
        }

        contentHeight += layout.contentInsets.bottom
        return LayoutResult(
            frames: frames,
            contentSize: CGSize(width: width, height: contentHeight)
        )
    }

    private func updateImmediateSelectionAvailability(viewportSize: CGSize, contentHeight: CGFloat) {
        let hasSelectableRows = self.elements.contains { element in
            if case let .row(row) = element {
                return row.isSelectable && row.isEnabled
            }
            return false
        }
        let requiresScrolling = contentHeight > viewportSize.height + 0.5
        self.allowsImmediateSelection = !requiresScrolling && hasSelectableRows
        self.selectionTouchView.isHidden = !self.allowsImmediateSelection
        self.selectionTouchView.shouldCaptureTouch = self.allowsImmediateSelection ? { [weak self] point in
            self?.selectableRowIndex(atSelectionTouchPoint: point) != nil
        } : nil
        self.scrollView.isScrollEnabled = requiresScrolling
        self.scrollView.alwaysBounceVertical = requiresScrolling
        self.scrollView.delaysContentTouches = requiresScrolling
        self.scrollingReorderRecognizer.isEnabled = requiresScrolling && self.supportsReorder

        for element in self.elements {
            if case let .row(row) = element {
                let selectionViewHandlesTouches = self.allowsImmediateSelection
                    && row.isSelectable
                    && row.allowsImmediateSelectionCapture
                row.setDirectInteractionEnabled(!selectionViewHandlesTouches)
            }
        }
    }

    private func updateColors() {
        self.updateSelectionColors()

        self.elements.forEach { element in
            switch element {
            case let .row(row):
                row.updateColors()
            case let .separator(separatorView):
                separatorView.updateColors()
            }
        }
    }

    private func updateSelectionColors() {
        self.selectionView.backgroundColor = ContextMenuVisuals.highlightTintColor(for: self.traitCollection)
        self.selectionView.setContextMenuMonochromaticEffect(tintColor: self.selectionView.backgroundColor)
    }

    private func rowIndex(at contentPoint: CGPoint) -> Int? {
        var rowIndex = 0
        for element in self.elements {
            switch element {
            case let .row(row):
                guard row.isSelectable else {
                    continue
                }
                if row.view.frame.contains(contentPoint), row.isEnabled {
                    return rowIndex
                }
                rowIndex += 1
            case .separator:
                continue
            }
        }
        return nil
    }

    private func selectableRowViewFrame(for rowIndex: Int) -> CGRect? {
        var currentRowIndex = 0
        for element in self.elements {
            if case let .row(row) = element, row.isSelectable {
                defer { currentRowIndex += 1 }
                if currentRowIndex == rowIndex {
                    return row.view.frame
                }
            }
        }
        return nil
    }

    private func action(for rowIndex: Int) -> ContextMenuPageAction? {
        var currentRowIndex = 0
        for element in self.elements {
            if case let .row(row) = element, row.isSelectable {
                defer { currentRowIndex += 1 }
                if currentRowIndex == rowIndex {
                    return row.activation
                }
            }
        }
        return nil
    }

    private func updateHighlight(index: Int?, animated: Bool, emitFeedback: Bool) {
        guard self.highlightedRowIndex != index else {
            return
        }

        let previousIndex = self.highlightedRowIndex
        self.highlightedRowIndex = index

        if emitFeedback, previousIndex != index, index != nil {
            self.feedbackGenerator.selectionChanged()
        }
        if let index {
            self.selectableRow(at: index)?.notifyHighlighted()
        }

        guard let index, let targetRowFrame = self.selectableRowViewFrame(for: index) else {
            let animations = {
                self.selectionView.alpha = 0.0
            }
            if animated {
                UIView.animate(withDuration: 0.2, delay: 0.0, options: [.curveEaseInOut, .beginFromCurrentState]) {
                    animations()
                }
            } else {
                animations()
            }
            return
        }

        let targetFrame: CGRect
        let targetCornerRadius: CGFloat
        switch self.page.layout {
        case .list:
            targetFrame = CGRect(
                x: self.style.highlightHorizontalInset,
                y: targetRowFrame.minY,
                width: max(0.0, self.contentView.bounds.width - self.style.highlightHorizontalInset * 2.0),
                height: targetRowFrame.height
            )
            targetCornerRadius = min(self.listHighlightCornerRadius, targetFrame.height * 0.5)
        case let .grid(layout):
            targetFrame = CGRect(
                x: targetRowFrame.minX + layout.highlightInsets.left,
                y: targetRowFrame.minY + layout.highlightInsets.top,
                width: max(
                    0.0,
                    targetRowFrame.width - layout.highlightInsets.left - layout.highlightInsets.right
                ),
                height: max(
                    0.0,
                    targetRowFrame.height - layout.highlightInsets.top - layout.highlightInsets.bottom
                )
            )
            targetCornerRadius = min(layout.highlightCornerRadius, targetFrame.height * 0.5)
        }
        let animateIn = self.selectionView.alpha == 0.0
        if animateIn {
            if self.selectionView.layer.animation(forKey: "opacity") == nil {
                self.selectionView.frame = targetFrame
                self.selectionView.layer.cornerRadius = targetCornerRadius
            } else if animated {
                UIView.animate(withDuration: 0.16, delay: 0.0, options: [.curveEaseInOut, .beginFromCurrentState]) {
                    self.selectionView.frame = targetFrame
                    self.selectionView.layer.cornerRadius = targetCornerRadius
                }
            } else {
                self.selectionView.frame = targetFrame
                self.selectionView.layer.cornerRadius = targetCornerRadius
            }

            if animated {
                UIView.animate(withDuration: 0.2, delay: 0.0, options: [.curveEaseInOut, .beginFromCurrentState]) {
                    self.selectionView.alpha = ContextMenuVisuals.highlightAlpha()
                }
            } else {
                self.selectionView.alpha = ContextMenuVisuals.highlightAlpha()
            }
        } else {
            let animations = {
                self.selectionView.frame = targetFrame
                self.selectionView.layer.cornerRadius = targetCornerRadius
                self.selectionView.alpha = ContextMenuVisuals.highlightAlpha()
            }
            if animated {
                UIView.animate(withDuration: 0.16, delay: 0.0, options: [.curveEaseInOut, .beginFromCurrentState]) {
                    animations()
                }
            } else {
                animations()
            }
        }
    }

    /// Concentric with the menu's corners: their radius less the highlight's inset from the menu's sides. The list's
    /// top and bottom padding, the same by default, keep the first and the last row's highlight as far from the ends.
    private var listHighlightCornerRadius: CGFloat {
        max(0.0, (self.menuCornerRadius ?? self.style.panelCornerRadius) - self.style.highlightHorizontalInset)
    }

    private func activateRow(at rowIndex: Int) {
        guard let action = self.action(for: rowIndex) else {
            return
        }
        self.delegate?.pageView(self, didActivate: action)
    }

    private func updateAutoScrollIfNeeded(scrollPoint: CGPoint) {
        let overflow = max(0.0, self.scrollView.contentSize.height - self.scrollView.bounds.height)
        guard overflow > 0.0 else {
            self.stopAutoScroll()
            return
        }

        let zoneHeight: CGFloat = 44.0
        var velocity: CGFloat = 0.0
        if scrollPoint.y < zoneHeight {
            velocity = -((zoneHeight - scrollPoint.y) / zoneHeight) * 260.0
        } else if scrollPoint.y > self.scrollView.bounds.height - zoneHeight {
            velocity = ((scrollPoint.y - (self.scrollView.bounds.height - zoneHeight)) / zoneHeight) * 260.0
        }
        self.autoScrollVelocity = velocity

        if abs(velocity) > 1.0 {
            self.startAutoScroll()
        } else {
            self.stopAutoScroll()
        }
    }

    private func startAutoScroll() {
        guard self.autoScrollDisplayLink == nil else {
            return
        }
        let displayLink = CADisplayLink(target: self, selector: #selector(self.handleAutoScrollTick(_:)))
        displayLink.add(to: .main, forMode: .common)
        self.autoScrollDisplayLink = displayLink
    }

    private func stopAutoScroll() {
        self.autoScrollDisplayLink?.invalidate()
        self.autoScrollDisplayLink = nil
        self.autoScrollVelocity = 0.0
    }

    private func updateImmediateSelection(locationInSelectionView: CGPoint, emitFeedback: Bool) {
        let contentPoint = self.contentView.convert(locationInSelectionView, from: self.selectionTouchView)
        self.updateHighlight(index: self.rowIndex(at: contentPoint), animated: true, emitFeedback: emitFeedback)
    }

    private func endImmediateSelection(performAction: Bool) {
        let highlightedIndex = self.highlightedRowIndex
        self.updateHighlight(index: nil, animated: true, emitFeedback: false)

        guard performAction, let highlightedIndex else {
            return
        }
        self.activateRow(at: highlightedIndex)
    }

    @objc private func handleAutoScrollTick(_ displayLink: CADisplayLink) {
        guard abs(self.autoScrollVelocity) > 1.0 else {
            self.stopAutoScroll()
            return
        }

        let maxOffset = max(0.0, self.scrollView.contentSize.height - self.scrollView.bounds.height)
        guard maxOffset > 0.0 else {
            self.stopAutoScroll()
            return
        }

        let deltaTime = CGFloat(displayLink.targetTimestamp - displayLink.timestamp)
        let targetOffsetY = min(max(self.scrollView.contentOffset.y + self.autoScrollVelocity * deltaTime, 0.0), maxOffset)
        if abs(targetOffsetY - self.scrollView.contentOffset.y) < 0.1 {
            self.stopAutoScroll()
            return
        }

        self.scrollView.contentOffset.y = targetOffsetY
        if let activeSelectionWindowPoint {
            self.updateExternalSelection(windowPoint: activeSelectionWindowPoint)
        } else if self.liftedRow != nil, let scrollingReorderWindowPoint {
            self.moveLiftedRow(to: self.contentView.convert(scrollingReorderWindowPoint, from: nil))
        }
    }

    private func handleSelectionTouchBegan(_ point: CGPoint) {
        guard self.allowsImmediateSelection else {
            return
        }
        self.isCancellingImmediateSelectionForHorizontalPan = false
        self.feedbackGenerator.prepare()
        self.updateImmediateSelection(locationInSelectionView: point, emitFeedback: false)
        self.updateReorderHold(contentPoint: self.contentView.convert(point, from: self.selectionTouchView))
    }

    private func handleSelectionTouchMoved(initialPoint: CGPoint, point: CGPoint) {
        guard self.allowsImmediateSelection else {
            return
        }

        let contentPoint = self.contentView.convert(point, from: self.selectionTouchView)
        if self.liftedRow != nil {
            self.moveLiftedRow(to: contentPoint)
            return
        }

        let translation = CGPoint(x: point.x - initialPoint.x, y: point.y - initialPoint.y)
        let backTranslationX = self.sourceUserInterfaceLayoutDirection.contextMenuIsRightToLeft
            ? -translation.x
            : translation.x
        if self.allowsBackNavigationGesture,
           !self.isCancellingImmediateSelectionForHorizontalPan,
           backTranslationX > 10.0,
           backTranslationX > abs(translation.y) * 1.5 {
            self.isCancellingImmediateSelectionForHorizontalPan = true
            self.cancelReorderHold()
            self.endImmediateSelection(performAction: false)
            return
        }

        guard !self.isCancellingImmediateSelectionForHorizontalPan else {
            return
        }

        self.updateImmediateSelection(locationInSelectionView: point, emitFeedback: true)
        self.updateReorderHold(contentPoint: contentPoint)
    }

    private func handleSelectionTouchEnded(point: CGPoint, performAction: Bool) {
        guard self.allowsImmediateSelection else {
            return
        }

        self.cancelReorderHold()
        if self.liftedRow != nil {
            self.dropLiftedRow()
            return
        }

        if self.isCancellingImmediateSelectionForHorizontalPan {
            self.isCancellingImmediateSelectionForHorizontalPan = false
            self.endImmediateSelection(performAction: false)
            return
        }

        self.updateImmediateSelection(locationInSelectionView: point, emitFeedback: false)
        self.endImmediateSelection(performAction: performAction)
    }

    @objc private func rowTouchDown(_ sender: UIControl) {
        guard self.activeSelectionWindowPoint == nil, self.allowsDirectInteraction(for: sender) else {
            return
        }
        self.updateHighlight(index: self.rowIndex(for: sender), animated: true, emitFeedback: false)
    }

    @objc private func rowTouchEnter(_ sender: UIControl) {
        guard self.activeSelectionWindowPoint == nil, self.allowsDirectInteraction(for: sender) else {
            return
        }
        self.updateHighlight(index: self.rowIndex(for: sender), animated: true, emitFeedback: false)
    }

    @objc private func rowTouchExit(_ sender: UIControl) {
        // The touch a lifted row takes over ends for the row's control, and the row stays highlighted
        guard self.activeSelectionWindowPoint == nil, self.liftedRow == nil, self.allowsDirectInteraction(for: sender) else {
            return
        }
        if self.rowIndex(for: sender) == self.highlightedRowIndex {
            self.updateHighlight(index: nil, animated: true, emitFeedback: false)
        }
    }

    @objc private func rowActivated(_ sender: UIControl) {
        guard self.activeSelectionWindowPoint == nil, self.allowsDirectInteraction(for: sender) else {
            return
        }
        defer {
            self.updateHighlight(index: nil, animated: true, emitFeedback: false)
        }
        guard let rowIndex = self.rowIndex(for: sender) else {
            return
        }
        self.activateRow(at: rowIndex)
    }

    private func rowIndex(for rowView: UIControl) -> Int? {
        var rowIndex = 0
        for element in self.elements {
            if case let .row(row) = element, row.isSelectable, let candidate = row.controlView {
                defer { rowIndex += 1 }
                if candidate === rowView {
                    return rowIndex
                }
            }
        }
        return nil
    }

    private func selectableRowIndex(atSelectionTouchPoint point: CGPoint) -> Int? {
        let contentPoint = self.contentView.convert(point, from: self.selectionTouchView)
        guard let rowIndex = self.rowIndex(at: contentPoint),
              self.selectableRow(at: rowIndex)?.allowsImmediateSelectionCapture == true
        else {
            return nil
        }
        return rowIndex
    }

    private func allowsDirectInteraction(for rowView: UIControl) -> Bool {
        guard self.allowsImmediateSelection else {
            return true
        }
        guard let rowIndex = self.rowIndex(for: rowView) else {
            return false
        }
        return self.selectableRow(at: rowIndex)?.allowsImmediateSelectionCapture == false
    }

    private func selectableRow(at targetIndex: Int) -> ContextMenuPageRowElement? {
        var rowIndex = 0
        for element in self.elements {
            if case let .row(row) = element, row.isSelectable {
                defer { rowIndex += 1 }
                if rowIndex == targetIndex {
                    return row
                }
            }
        }
        return nil
    }

    // MARK: - Reordering

    private static let reorderHoldDuration: TimeInterval = 0.5
    private static let reorderHoldSlop: CGFloat = 10.0
    private static let liftedRowScale: CGFloat = 1.04

    private var supportsReorder: Bool {
        guard self.page.onReorder != nil, case .list = self.page.layout else {
            return false
        }
        return self.page.items.allSatisfy { item in
            if case .action = item {
                return true
            }
            return false
        }
    }

    /// Arms the lift for the row under the finger, and re-arms it whenever the finger
    /// leaves that row or moves on it, so only a finger resting on one row lifts it
    private func updateReorderHold(contentPoint: CGPoint) {
        guard self.supportsReorder, self.liftedRow == nil else {
            return
        }
        self.reorderTouchContentPoint = contentPoint
        let rowIndex = self.rowIndex(at: contentPoint)
        if let reorderHold, reorderHold.rowIndex == rowIndex,
           hypot(contentPoint.x - reorderHold.contentPoint.x, contentPoint.y - reorderHold.contentPoint.y) <= Self.reorderHoldSlop {
            return
        }
        self.cancelReorderHold()
        guard let rowIndex else {
            return
        }
        ContextMenuHaptics.prepare()
        let timer = Timer.scheduledTimer(withTimeInterval: Self.reorderHoldDuration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.liftRow(at: rowIndex)
            }
        }
        self.reorderHold = (rowIndex, contentPoint, timer)
    }

    @objc private func handleScrollingReorderPress(_ recognizer: UILongPressGestureRecognizer) {
        let windowPoint = recognizer.location(in: nil)
        switch recognizer.state {
        case .began:
            let contentPoint = self.contentView.convert(windowPoint, from: nil)
            guard let rowIndex = self.rowIndex(at: contentPoint) else {
                return
            }
            self.reorderTouchContentPoint = contentPoint
            self.scrollingReorderWindowPoint = windowPoint
            self.liftRow(at: rowIndex)
        case .changed:
            guard self.liftedRow != nil else {
                return
            }
            self.scrollingReorderWindowPoint = windowPoint
            self.moveLiftedRow(to: self.contentView.convert(windowPoint, from: nil))
            // The scroll view's frame starts at this view's origin, so this is the point in the visible part
            self.updateAutoScrollIfNeeded(scrollPoint: self.convert(windowPoint, from: nil))
        default:
            self.scrollingReorderWindowPoint = nil
            self.stopAutoScroll()
            self.dropLiftedRow()
        }
    }

    private func cancelReorderHold() {
        self.reorderHold?.timer.invalidate()
        self.reorderHold = nil
    }

    private func liftRow(at index: Int) {
        self.reorderHold = nil
        guard self.liftedRow == nil,
              self.elements.indices.contains(index),
              let contentPoint = self.reorderTouchContentPoint
        else {
            return
        }
        let rowView = self.elements[index].view
        self.liftedRow = (rowView, contentPoint.y - rowView.frame.minY)
        self.stopAutoScroll()
        ContextMenuHaptics.playRowLift()

        self.contentView.bringSubviewToFront(rowView)
        self.contentView.insertSubview(self.selectionView, belowSubview: rowView)
        self.updateHighlight(index: index, animated: true, emitFeedback: false)
        UIView.animate(
            withDuration: 0.3,
            delay: 0.0,
            usingSpringWithDamping: 0.7,
            initialSpringVelocity: 0.0,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            rowView.transform = CGAffineTransform(scaleX: Self.liftedRowScale, y: Self.liftedRowScale)
            self.selectionView.transform = CGAffineTransform(scaleX: Self.liftedRowScale, y: Self.liftedRowScale)
        }
    }

    private func moveLiftedRow(to contentPoint: CGPoint) {
        guard let liftedRow,
              let index = self.elements.firstIndex(where: { $0.view === liftedRow.view })
        else {
            return
        }
        let width = self.contentView.bounds.width
        let frames = self.listLayoutResult(width: width).frames
        let rowFrame = frames[index]
        let minY = frames.first!.minY
        let maxY = frames.last!.maxY - rowFrame.height
        let originY = min(max(contentPoint.y - liftedRow.touchOffsetY, minY), maxY)
        let center = CGPoint(x: rowFrame.midX, y: originY + rowFrame.height * 0.5)
        liftedRow.view.center = center
        self.selectionView.center = center

        let destinationIndex = Self.reorderDestination(of: index, at: originY, among: frames)
        guard destinationIndex != index else {
            return
        }

        let element = self.elements.remove(at: index)
        self.elements.insert(element, at: destinationIndex)
        self.highlightedRowIndex = destinationIndex
        self.feedbackGenerator.selectionChanged()
        self.page.onReorder?(index, destinationIndex)

        let newFrames = self.listLayoutResult(width: width).frames
        UIView.animate(
            withDuration: 0.35,
            delay: 0.0,
            usingSpringWithDamping: 0.85,
            initialSpringVelocity: 0.0,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            for (element, frame) in zip(self.elements, newFrames) where element.view !== liftedRow.view {
                element.view.frame = frame
            }
        }
    }

    /// The place the row at `index` takes with its top at `originY`, among rows laid out in `frames` in their current
    /// order. The row passes a neighbor once its near edge crosses the neighbor's middle, so with its top held inside
    /// the list it still reaches the first and the last place
    static func reorderDestination(of index: Int, at originY: CGFloat, among frames: [CGRect]) -> Int {
        let maxY = originY + frames[index].height
        var destinationIndex = index
        while destinationIndex > 0, originY < frames[destinationIndex - 1].midY {
            destinationIndex -= 1
        }
        while destinationIndex < frames.count - 1, maxY > frames[destinationIndex + 1].midY {
            destinationIndex += 1
        }
        return destinationIndex
    }

    private func dropLiftedRow() {
        guard let liftedRow else {
            return
        }
        self.liftedRow = nil
        self.reorderTouchContentPoint = nil
        guard let index = self.elements.firstIndex(where: { $0.view === liftedRow.view }) else {
            liftedRow.view.transform = .identity
            self.selectionView.transform = .identity
            return
        }
        let frame = self.listLayoutResult(width: self.contentView.bounds.width).frames[index]
        let center = CGPoint(x: frame.midX, y: frame.midY)
        UIView.animate(
            withDuration: 0.35,
            delay: 0.0,
            usingSpringWithDamping: 0.8,
            initialSpringVelocity: 0.0,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            liftedRow.view.transform = .identity
            liftedRow.view.center = center
            self.selectionView.transform = .identity
            self.selectionView.center = center
        }
        self.updateHighlight(index: nil, animated: true, emitFeedback: false)
    }
}

extension ContextMenuPageView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // A touch that may become a hold readies its haptic
        ContextMenuHaptics.prepare()
        return true
    }
}
