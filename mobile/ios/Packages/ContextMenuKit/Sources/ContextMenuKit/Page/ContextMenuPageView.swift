import UIKit

@MainActor
final class ContextMenuPageView: UIView {
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

    var allowsBackNavigationGesture = false

    init(page: ContextMenuPage, style: ContextMenuStyle, customRowContext: ContextMenuCustomRowContext) {
        self.page = page
        self.style = style
        self.customRowContext = customRowContext

        super.init(frame: .zero)

        self.scrollView.showsVerticalScrollIndicator = false
        self.scrollView.alwaysBounceVertical = false
        self.scrollView.delaysContentTouches = true
        self.scrollView.canCancelContentTouches = true

        self.selectionView.alpha = 0.0
        self.selectionView.isUserInteractionEnabled = false
        self.selectionView.layer.cornerCurve = .continuous

        self.addSubview(self.scrollView)
        self.scrollView.addSubview(self.contentView)
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
            self.updateColors()
        }
    }

    func preferredSize(constrainedTo constrainedSize: CGSize) -> CGSize {
        let clampedWidth = min(self.style.maxWidth, constrainedSize.width)
        let contentSize = self.measuredContentSize(maxWidth: clampedWidth)
        return CGSize(
            width: min(self.style.maxWidth, max(self.style.minWidth, contentSize.width)).rounded(.up),
            height: min(constrainedSize.height, contentSize.height).rounded(.up)
        )
    }

    func applyLayout(size: CGSize) {
        self.scrollView.frame = CGRect(origin: .zero, size: size)
        self.selectionTouchView.frame = self.scrollView.frame

        var contentHeight: CGFloat = 0.0
        var firstRow = true
        for element in self.elements {
            switch element {
            case let .row(row):
                if firstRow {
                    contentHeight += self.style.listVerticalPadding
                    firstRow = false
                }
                let rowSize = row.measuredSize(maxWidth: size.width)
                let rowFrame = CGRect(x: 0.0, y: contentHeight, width: size.width, height: rowSize.height)
                row.view.frame = rowFrame
                row.applyLayout(size: rowFrame.size)
                contentHeight += rowFrame.height
            case let .separator(separatorView):
                let separatorFrame = CGRect(x: 0.0, y: contentHeight, width: size.width, height: self.style.separatorHeight)
                separatorView.frame = separatorFrame
                contentHeight += separatorFrame.height
            }
        }

        if !firstRow {
            contentHeight += self.style.listVerticalPadding
        }

        self.contentView.frame = CGRect(x: 0.0, y: 0.0, width: size.width, height: contentHeight)
        self.scrollView.contentSize = self.contentView.bounds.size
        self.updateImmediateSelectionAvailability(viewportSize: size, contentHeight: contentHeight)

        if let highlightedRowIndex {
            self.updateHighlight(index: highlightedRowIndex, animated: false, emitFeedback: false)
        } else {
            self.selectionView.frame = .zero
        }
    }

    func restoreVisualState() {
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
                        accessory: .none
                    ),
                    style: self.style
                )
                let row = ContextMenuPageRowElement(
                    view: rowView,
                    controlView: rowView,
                    isSelectable: true,
                    isEnabled: action.isEnabled,
                    activation: .trigger(ContextMenuActivation(dismissesMenu: action.dismissesMenu, handler: action.handler)),
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
                    style: self.style
                )
                let row = ContextMenuPageRowElement(
                    view: rowView,
                    controlView: rowView,
                    isSelectable: true,
                    isEnabled: backAction.isEnabled,
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
                    style: self.style
                )
                let row = ContextMenuPageRowElement(
                    view: rowView,
                    controlView: rowView,
                    isSelectable: true,
                    isEnabled: submenu.isEnabled,
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
                let row = ContextMenuPageRowElement(
                    view: rowView,
                    controlView: customRow.interaction.isSelectable ? rowView : nil,
                    isSelectable: customRow.interaction.isSelectable,
                    isEnabled: customRow.interaction.isEnabled,
                    activation: customRow.interaction.isSelectable
                        ? .trigger(ContextMenuActivation(
                            dismissesMenu: customRow.interaction.dismissesMenu,
                            handler: customRow.interaction.handler
                        ))
                        : nil,
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

        for element in self.elements {
            if case let .row(row) = element {
                row.setDirectInteractionEnabled(!self.allowsImmediateSelection || !row.isSelectable)
            }
        }
    }

    private func updateColors() {
        self.selectionView.backgroundColor = ContextMenuVisuals.highlightTintColor(for: self.traitCollection)
        self.selectionView.setContextMenuMonochromaticEffect(tintColor: self.selectionView.backgroundColor)

        self.elements.forEach { element in
            switch element {
            case let .row(row):
                row.updateColors()
            case let .separator(separatorView):
                separatorView.updateColors()
            }
        }
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

        let targetFrame = CGRect(
            x: self.style.highlightHorizontalInset,
            y: targetRowFrame.minY,
            width: max(0.0, self.contentView.bounds.width - self.style.highlightHorizontalInset * 2.0),
            height: targetRowFrame.height
        )
        let targetCornerRadius = min(20.0, targetFrame.height * 0.5)
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
        }
    }

    private func handleSelectionTouchBegan(_ point: CGPoint) {
        guard self.allowsImmediateSelection else {
            return
        }
        self.isCancellingImmediateSelectionForHorizontalPan = false
        self.feedbackGenerator.prepare()
        self.updateImmediateSelection(locationInSelectionView: point, emitFeedback: false)
    }

    private func handleSelectionTouchMoved(initialPoint: CGPoint, point: CGPoint) {
        guard self.allowsImmediateSelection else {
            return
        }

        let translation = CGPoint(x: point.x - initialPoint.x, y: point.y - initialPoint.y)
        if self.allowsBackNavigationGesture,
           !self.isCancellingImmediateSelectionForHorizontalPan,
           translation.x > 10.0,
           translation.x > abs(translation.y) * 1.5 {
            self.isCancellingImmediateSelectionForHorizontalPan = true
            self.endImmediateSelection(performAction: false)
            return
        }

        guard !self.isCancellingImmediateSelectionForHorizontalPan else {
            return
        }

        self.updateImmediateSelection(locationInSelectionView: point, emitFeedback: true)
    }

    private func handleSelectionTouchEnded(point: CGPoint, performAction: Bool) {
        guard self.allowsImmediateSelection else {
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
        guard self.activeSelectionWindowPoint == nil, !self.allowsImmediateSelection else {
            return
        }
        self.updateHighlight(index: self.rowIndex(for: sender), animated: true, emitFeedback: false)
    }

    @objc private func rowTouchEnter(_ sender: UIControl) {
        guard self.activeSelectionWindowPoint == nil, !self.allowsImmediateSelection else {
            return
        }
        self.updateHighlight(index: self.rowIndex(for: sender), animated: true, emitFeedback: false)
    }

    @objc private func rowTouchExit(_ sender: UIControl) {
        guard self.activeSelectionWindowPoint == nil, !self.allowsImmediateSelection else {
            return
        }
        if self.rowIndex(for: sender) == self.highlightedRowIndex {
            self.updateHighlight(index: nil, animated: true, emitFeedback: false)
        }
    }

    @objc private func rowActivated(_ sender: UIControl) {
        guard self.activeSelectionWindowPoint == nil, !self.allowsImmediateSelection else {
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
        return self.rowIndex(at: contentPoint)
    }
}
