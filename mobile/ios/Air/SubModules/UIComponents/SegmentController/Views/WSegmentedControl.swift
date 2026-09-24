//
//  WSegmentedControl.swift
//
//  Created by nikstar on 15.11.2025.
//

import Perception
import SwiftUI
import UIKit
import WalletContext

public final class WSegmentedControl: UIView, UIScrollViewDelegate {

    public let model: SegmentedControlModel
    private let scrollContentMargin: CGFloat
    private let isGlassInteractive: Bool

    private let backgroundContainer = UIView()
    private var backgroundView: UIView?

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let lensView = WSegmentedControlLensView()
    private let selectedScrollView = UIView()
    private let secondaryContainer = UIView()
    private let primaryContainer = UIView()
    private let interactionContainer = UIView()

    private struct ItemViews {
        let id: String
        let secondaryView: UIView
        let secondaryLabel: UILabel
        let primaryView: UIView
        let primaryLabel: UILabel
        let arrow: UIImageView?
        let interaction: SegmentedControlInteractionView
    }

    private var itemViews: [ItemViews] = []
    private var renderedItems: [SegmentedControlItem] = []

    private var hasAppliedSelection = false
    private var lastSelectedItemID: String?
    private var lastLayoutWidth: CGFloat = 0
    private var lastLayoutDirection: UIUserInterfaceLayoutDirection?
    private var autoScrollWorkItem: DispatchWorkItem?
    private var replacementCrossfadeCount = 0
    private var isLayingOutContent = false
    private var liftWorkItem: DispatchWorkItem?
    private var isLensLifted = false

    private var reorderingVC: SegmentedControlReorderingVC?
    private var isReorderingApplied = false

    private var isInReplacementCrossfade: Bool { replacementCrossfadeCount > 0 }
    private var shouldSuppressTransientAnimations: Bool { isInReplacementCrossfade }

    public init(
        model: SegmentedControlModel,
        scrollContentMargin: CGFloat = 0,
        isGlassInteractive: Bool = false
    ) {
        self.model = model
        self.scrollContentMargin = scrollContentMargin
        self.isGlassInteractive = isGlassInteractive
        super.init(frame: .zero)
        setupViews()
        rebuildItems()
        applyBackgroundStyle()
        observeModel()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { endLensLift(animated: false) }
        applyColors()
    }

    public override func didMoveToSuperview() {
        super.didMoveToSuperview()
        // Match Telegram's header-panel overlay so the lifted lens can extend beyond the glass.
        var ancestor = superview
        var container: UIView?
        if #available(iOS 26, *) {
            while let view = ancestor {
                if let effect = view as? UIVisualEffectView, effect.effect is UIGlassContainerEffect {
                    container = effect.contentView
                    break
                }
                ancestor = view.superview
            }
        }
        lensView.setLiftedContainer(container)
    }

    public override func tintColorDidChange() {
        super.tintColorDidChange()
        applyColors()
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        applyColors()
        updateLens(animated: false)
    }

    private func setupViews() {
        clipsToBounds = false
        backgroundColor = .clear

        backgroundContainer.isUserInteractionEnabled = false
        addSubview(backgroundContainer)

        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.clipsToBounds = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.decelerationRate = .fast
        scrollView.alwaysBounceVertical = false
        scrollView.scrollsToTop = false
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = true
        scrollView.delegate = self
        addSubview(lensView)
        lensView.contentView.addSubview(scrollView)
        selectedScrollView.clipsToBounds = true
        lensView.selectedContentView.addSubview(selectedScrollView)

        contentView.clipsToBounds = false
        scrollView.addSubview(contentView)

        secondaryContainer.isUserInteractionEnabled = false
        contentView.addSubview(secondaryContainer)
        primaryContainer.isUserInteractionEnabled = false
        selectedScrollView.addSubview(primaryContainer)
        contentView.addSubview(interactionContainer)
    }

    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled, self.point(inside: point, with: event) else { return nil }
        if isReorderingApplied { return super.hitTest(point, with: event) }
        return scrollView.hitTest(convert(point, to: scrollView), with: event)
    }

    private func observeModel() {
        withPerceptionTracking {
            _ = model.items
            _ = model.selection
            _ = model.isReordering
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.syncFromModel()
                self?.observeModel()
            }
        }
    }

    private func syncFromModel() {
        let willRebuild = model.items != renderedItems
        if willRebuild || shouldSuppressTransientAnimations {
            UIView.performWithoutAnimation {
                self.applyModelState(didRebuild: willRebuild)
            }
        } else {
            applyModelState(didRebuild: false)
        }
    }

    private func applyModelState(didRebuild willRebuild: Bool) {
        var didRebuild = willRebuild
        if model.items != renderedItems {
            cancelSelectionAnimations()
            model.elementSizes.removeAll(keepingCapacity: true)
            rebuildItems()
            didRebuild = true
        }
        updateReorderingState()
        if didRebuild {
            scrollView.contentOffset = .zero
        }

        // When the item set changes (e.g. `replace(items:)`), consumers crossfade a snapshot of the
        // old bar over the new one. The new bar must appear already settled, so snap the capsule/size
        // into place instead of springing it from the previous selection underneath the crossfade.
        let suppressAnimation = didRebuild || shouldSuppressTransientAnimations
        let currentSelectedID = model.selectedItem?.id
        let selectionChanged = currentSelectedID != lastSelectedItemID
        let isInteractiveProgress = isInteractiveSelectionProgress()
        let hadAppliedSelection = hasAppliedSelection
        let animated = hadAppliedSelection
            && !suppressAnimation
            && shouldAnimateCurrentSelection()
            && selectionChanged

        setNeedsLayout()
        if !animated {
            layoutIfNeeded()
        }
        updateSelection(animated: animated)

        lastSelectedItemID = currentSelectedID
        if suppressAnimation {
            autoScrollWorkItem?.cancel()
            autoScrollToSelected(animated: false)
        } else if isInteractiveProgress {
            // Keep the capsule centered while pager/swipe progress updates in real time.
            autoScrollWorkItem?.cancel()
            autoScrollToSelected(animated: false)
        } else if selectionChanged {
            if hadAppliedSelection {
                scheduleAutoScrollToSelected()
            } else {
                autoScrollWorkItem?.cancel()
                autoScrollToSelected(animated: false)
            }
        }

        if isReorderingApplied {
            reorderingVC?.updateFrom(items: model.items, selection: model.selection)
        }
    }

    internal func applyPendingModelChangesWithoutAnimation() {
        UIView.performWithoutAnimation {
            syncFromModel()
        }
    }

    internal func beginReplacementCrossfade() {
        replacementCrossfadeCount += 1
        cancelSelectionAnimations()
    }

    internal func endReplacementCrossfade() {
        replacementCrossfadeCount = max(0, replacementCrossfadeCount - 1)
    }

    private func shouldAnimateCurrentSelection() -> Bool {
        !isInteractiveSelectionProgress()
    }

    private func isInteractiveSelectionProgress() -> Bool {
        guard let selection = model.selection else { return false }
        guard selection.item2 != nil, let progress = selection.progress else { return false }
        return progress > 0.0001 && progress < 0.9999
    }

    private func rebuildItems() {
        for views in itemViews {
            views.secondaryView.removeFromSuperview()
            views.primaryView.removeFromSuperview()
            views.interaction.removeFromSuperview()
        }
        itemViews.removeAll()
        renderedItems = model.items

        let font = model.font
        let attrs: [NSAttributedString.Key: Any] = [.font: font]

        for item in renderedItems {
            let width = (item.title as NSString).size(withAttributes: attrs).width + 2 * model.constants.innerPadding
            model.setSize(itemId: item.id, size: CGSize(width: width, height: model.constants.height))

            let secondaryView = UIView()
            secondaryView.isUserInteractionEnabled = false
            secondaryContainer.addSubview(secondaryView)

            let secondaryLabel = makeLabel(title: item.title, color: model.secondaryColor, font: font)
            secondaryLabel.isAccessibilityElement = false
            secondaryView.addSubview(secondaryLabel)

            let primaryView = UIView()
            primaryView.isUserInteractionEnabled = false
            primaryContainer.addSubview(primaryView)
            let primaryLabel = makeLabel(title: item.title, color: model.primaryColor, font: font)
            primaryLabel.isAccessibilityElement = false
            primaryView.addSubview(primaryLabel)

            var arrow: UIImageView?
            if item.shouldShowMenuIconWhenActive {
                let imageView = UIImageView(image: UIImage.airBundle("SegmentedControlArrow").withRenderingMode(.alwaysTemplate))
                imageView.tintColor = model.secondaryColor
                imageView.alpha = 0.5
                imageView.contentMode = .center
                primaryView.addSubview(imageView)
                arrow = imageView
            }

            let interaction = SegmentedControlInteractionView()
            interactionContainer.addSubview(interaction)

            itemViews.append(ItemViews(
                id: item.id,
                secondaryView: secondaryView,
                secondaryLabel: secondaryLabel,
                primaryView: primaryView,
                primaryLabel: primaryLabel,
                arrow: arrow,
                interaction: interaction
            ))
        }

        updateInteractions()
        accessibilityElements = reorderingVC.map { [$0.view!] } ?? itemViews.map(\.interaction)
        invalidateIntrinsicContentSize()
    }

    private func applyColors() {
        let primaryColor = model.primaryColor.resolvedColor(with: traitCollection)
        let secondaryColor = model.secondaryColor
        for views in itemViews {
            if views.secondaryLabel.textColor != secondaryColor {
                views.secondaryLabel.textColor = secondaryColor
            }
            if views.primaryLabel.textColor != primaryColor {
                views.primaryLabel.textColor = primaryColor
            }
            if let arrow = views.arrow, arrow.tintColor != primaryColor {
                arrow.tintColor = primaryColor
            }
        }
    }

    private func makeLabel(title: String, color: UIColor, font: UIFont) -> UILabel {
        let label = UILabel()
        label.text = title
        label.textColor = color
        label.font = font
        label.textAlignment = .center
        label.numberOfLines = 1
        return label
    }

    private func updateInteractions() {
        let selectedID = model.selection?.effectiveSelectedItemID
        for (index, views) in itemViews.enumerated() {
            guard index < renderedItems.count else { continue }
            let item = renderedItems[index]
            views.interaction.update(
                isSelected: selectedID == item.id,
                itemId: item.id,
                title: item.title,
                contextMenuProvider: item.contextMenuProvider,
                segmentedControl: self,
                allowsSimultaneousGlassInteraction: isGlassInteractive,
                onSelect: { [weak self] in
                    self?.beginLensLift()
                    self?.model.onSelect(item)
                }
            )
        }
    }

    public override func layoutSubviews() {
        if shouldSuppressTransientAnimations {
            UIView.performWithoutAnimation {
                self.layoutSegmentedContent()
            }
        } else {
            layoutSegmentedContent()
        }
    }

    private func layoutSegmentedContent() {
        super.layoutSubviews()
        isLayingOutContent = true
        defer { isLayingOutContent = false }

        let c = model.constants
        let availableWidth = max(0, bounds.width - 2 * c.backgroundPadding)
        let availableHeight = c.height
        let naturalWidth = model.calculateContentWidth(includeBackground: false)
        let distributesItemsEvenly = model.style == .compactRootHeader && !renderedItems.isEmpty
            && naturalWidth <= availableWidth
        let inner: CGFloat
        if distributesItemsEvenly {
            let spacingWidth = CGFloat(renderedItems.count - 1) * c.spacing
            let slotWidth = max(0, (availableWidth - spacingWidth) / CGFloat(renderedItems.count))
            for item in renderedItems {
                model.setSize(
                    itemId: item.id,
                    size: CGSize(width: slotWidth, height: availableHeight)
                )
            }
            inner = availableWidth
        } else {
            // Restore measured widths after a compact header stops fitting (rotation/localization).
            let attributes: [NSAttributedString.Key: Any] = [.font: model.font]
            for item in renderedItems {
                let width = (item.title as NSString).size(withAttributes: attributes).width + 2 * c.innerPadding
                model.setSize(itemId: item.id, size: CGSize(width: width, height: availableHeight))
            }
            inner = naturalWidth
        }

        backgroundContainer.frame = bounds
        backgroundView?.frame = backgroundContainer.bounds
        (backgroundView as? WCapsuleGlassBackgroundView)?.updateCornerRadius(bounds.height / 2)

        lensView.frame = CGRect(
            x: c.backgroundPadding,
            y: c.topInset + c.backgroundPadding,
            width: availableWidth,
            height: availableHeight
        )
        scrollView.frame = CGRect(origin: .zero, size: lensView.bounds.size)
        scrollView.layer.cornerRadius = availableHeight / 2
        scrollView.layer.cornerCurve = .continuous
        scrollView.clipsToBounds = true
        selectedScrollView.layer.cornerRadius = availableHeight / 2
        selectedScrollView.layer.cornerCurve = .continuous

        let fits = inner <= availableWidth
        scrollView.isScrollEnabled = !fits
        let totalContent = max(inner + 2 * scrollContentMargin, availableWidth)
        scrollView.contentSize = CGSize(width: totalContent, height: availableHeight)

        let contentLeft = ((totalContent - inner) / 2).rounded()
        contentView.frame = CGRect(x: contentLeft, y: 0, width: inner, height: availableHeight)
        primaryContainer.frame = contentView.frame
        secondaryContainer.frame = contentView.bounds
        interactionContainer.frame = contentView.bounds

        layoutItemSlots()
        applyColors()

        reorderingVC?.view.frame = CGRect(x: 0, y: 0, width: bounds.width, height: c.fullHeight)

        let layoutDirection = effectiveUserInterfaceLayoutDirection
        let widthChanged = abs(bounds.width - lastLayoutWidth) > 0.5
        let layoutDirectionChanged = layoutDirection != lastLayoutDirection
        lastLayoutWidth = bounds.width
        lastLayoutDirection = layoutDirection
        if widthChanged || layoutDirectionChanged || !hasAppliedSelection {
            updateSelection(animated: false)
        }
        if (widthChanged || layoutDirectionChanged), !shouldSuppressTransientAnimations {
            autoScrollWorkItem?.cancel()
            autoScrollToSelected(animated: false)
        }
        updateLens(animated: false)
    }

    private func layoutItemSlots() {
        guard let layouts = model.itemLayouts() else { return }
        let c = model.constants
        for (index, layout) in layouts.enumerated() {
            guard index < itemViews.count else { continue }
            let views = itemViews[index]
            let slot = resolvedFrame(for: layout.labelFrame)
            let slotCenter = CGPoint(x: slot.midX, y: slot.midY)
            let slotBounds = CGRect(origin: .zero, size: slot.size)
            views.secondaryView.bounds = slotBounds
            views.secondaryView.center = slotCenter
            views.secondaryLabel.frame = slotBounds
            let interactionFrame = resolvedFrame(for: layout.interactionFrame)
            views.primaryView.frame = interactionFrame
            views.primaryLabel.frame = slot.offsetBy(dx: -interactionFrame.minX, dy: -interactionFrame.minY)
            views.interaction.frame = interactionFrame

            if let arrow = views.arrow {
                let arrowSize = c.accessoryWidth
                let logicalArrowCenterX = layout.labelFrame.maxX - c.innerPadding + 4 + arrowSize / 2
                arrow.bounds = CGRect(x: 0, y: 0, width: arrowSize, height: c.height)
                arrow.center = CGPoint(x: resolvedX(for: logicalArrowCenterX) - interactionFrame.minX, y: c.height / 2)
                let scale = max(0.001, layout.accessoryVisibility)
                arrow.transform = CGAffineTransform(scaleX: scale, y: scale)
                arrow.alpha = 0.5
            }
        }
    }

    private var usesRightToLeftLayout: Bool {
        effectiveUserInterfaceLayoutDirection == .rightToLeft
    }

    private var resolvedSelectionFrame: CGRect? {
        model.selectionFrame.map { resolvedFrame(for: $0) }
    }

    private func resolvedFrame(for logicalFrame: CGRect) -> CGRect {
        guard usesRightToLeftLayout else { return logicalFrame }
        return CGRect(
            x: contentView.bounds.width - logicalFrame.maxX,
            y: logicalFrame.minY,
            width: logicalFrame.width,
            height: logicalFrame.height
        )
    }

    private func resolvedX(for logicalX: CGFloat) -> CGFloat {
        usesRightToLeftLayout ? contentView.bounds.width - logicalX : logicalX
    }

    private func updateSelection(animated: Bool) {
        updateInteractions()
        let apply = { [self] in
            layoutItemSlots()
        }

        if animated {
            UIView.animate(
                withDuration: 0.32,
                delay: 0,
                usingSpringWithDamping: 0.9,
                initialSpringVelocity: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: apply
            )
        } else {
            apply()
        }
        updateLens(animated: animated)
        hasAppliedSelection = true
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !isLayingOutContent else { return }
        updateLens(animated: false)
    }

    private func updateLens(animated: Bool) {
        selectedScrollView.frame = CGRect(origin: .zero, size: lensView.bounds.size)
        selectedScrollView.bounds.origin = scrollView.contentOffset
        let selection = resolvedSelectionFrame?.offsetBy(
            dx: contentView.frame.minX - scrollView.contentOffset.x, dy: 0
        )
        lensView.update(selectionFrame: selection, isLifted: isLensLifted,
                        color: model.capsuleColor, animated: animated)
    }

    private func beginLensLift() {
        guard !shouldSuppressTransientAnimations, traitCollection.userInterfaceIdiom != .pad,
              UIView.areAnimationsEnabled, !UIAccessibility.isReduceMotionEnabled else { return }
        liftWorkItem?.cancel()
        isLensLifted = true
        updateLens(animated: true)
        let work = DispatchWorkItem { [weak self] in self?.endLensLift(animated: true) }
        liftWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func endLensLift(animated: Bool) {
        liftWorkItem?.cancel()
        liftWorkItem = nil
        isLensLifted = false
        updateLens(animated: animated)
    }

    private func cancelSelectionAnimations() {
        autoScrollWorkItem?.cancel()
        lensView.cancelAnimations()
        endLensLift(animated: false)
        scrollView.layer.removeAllAnimations()
        primaryContainer.layer.removeAllAnimations()
        for item in itemViews {
            item.primaryView.layer.removeAllAnimations()
            item.secondaryView.layer.removeAllAnimations()
        }
    }

    func contextMenuActivationView(forItemId itemId: String) -> UIView? {
        guard let item = itemViews.first(where: { $0.id == itemId }) else { return nil }
        return model.selection?.effectiveSelectedItemID == itemId ? item.primaryView : item.secondaryView
    }

    private func scheduleAutoScrollToSelected() {
        guard !shouldSuppressTransientAnimations else { return }
        autoScrollWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.autoScrollToSelected(animated: true)
        }
        autoScrollWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    private func autoScrollToSelected(animated: Bool) {
        guard !isReorderingApplied else { return }
        guard scrollView.isScrollEnabled else { return }
        if scrollView.isDragging || scrollView.isTracking { return }
        guard let frame = resolvedSelectionFrame else { return }

        let viewportWidth = scrollView.bounds.width
        guard viewportWidth > 0 else { return }

        let selectionMidX = contentView.frame.minX + frame.midX
        let maxOffset = max(0, scrollView.contentSize.width - viewportWidth)
        let target = clamp(selectionMidX - viewportWidth / 2, to: 0 ... maxOffset)
        guard abs(scrollView.contentOffset.x - target) > 0.5 else { return }

        if animated {
            UIView.animate(
                withDuration: 0.35,
                delay: 0,
                options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction]
            ) {
                self.scrollView.contentOffset = CGPoint(x: target, y: 0)
            }
        } else {
            UIView.performWithoutAnimation {
                self.scrollView.contentOffset = CGPoint(x: target, y: 0)
            }
        }
    }

    private func updateReorderingState() {
        let shouldReorder = model.isReordering
        guard shouldReorder != isReorderingApplied else { return }
        isReorderingApplied = shouldReorder

        if shouldReorder {
            cancelSelectionAnimations()
            let vc = SegmentedControlReorderingVC(
                items: model.items,
                selection: model.selection,
                primaryColor: model.primaryColor,
                secondaryColor: model.secondaryColor,
                capsuleColor: model.capsuleColor,
                font: model.font,
                constants: model.constants,
                scrollContentMargin: scrollContentMargin,
                onChange: { [weak self] items in self?.model.requestItemsReorder(items) }
            )
            reorderingVC = vc
            vc.view.frame = CGRect(x: 0, y: 0, width: bounds.width, height: model.constants.fullHeight)
            vc.view.alpha = 0
            addSubview(vc.view)
            accessibilityElements = [vc.view!]

            UIView.animate(withDuration: 0.15) {
                self.lensView.alpha = 0
                self.backgroundContainer.alpha = 0
                vc.view.alpha = 1
            }
        } else if let vc = reorderingVC {
            reorderingVC = nil
            accessibilityElements = itemViews.map(\.interaction)
            UIView.animate(withDuration: 0.15) {
                self.lensView.alpha = 1
                self.backgroundContainer.alpha = 1
                vc.view.alpha = 0
            } completion: { _ in
                vc.view.removeFromSuperview()
            }
        }
    }

    private func applyBackgroundStyle() {
        backgroundView?.removeFromSuperview()
        backgroundView = nil

        let c = model.constants
        let cornerRadius = (c.height + c.backgroundPadding * 2) / 2

        switch model.style {
        case .regular:
            return
        case .colorHeader:
            let view = WCapsuleGlassBackgroundView(
                style: .colorHeader,
                cornerRadius: cornerRadius,
                isInteractive: isGlassInteractive
            )
            backgroundContainer.addSubview(view)
            backgroundView = view
        case .header, .rootHeader, .compactRootHeader:
            let view = WCapsuleGlassBackgroundView(
                style: .header,
                cornerRadius: cornerRadius,
                isInteractive: isGlassInteractive
            )
            backgroundContainer.addSubview(view)
            backgroundView = view
        }
        if isGlassInteractive,
           let backgroundView = backgroundView as? WCapsuleGlassBackgroundView,
           backgroundView.hostContentIfSupported(lensView) {
            backgroundContainer.isUserInteractionEnabled = true
        }
        setNeedsLayout()
    }

    public override var intrinsicContentSize: CGSize {
        CGSize(
            width: model.calculateContentWidth(includeBackground: true),
            height: model.constants.fullHeightWithBackground
        )
    }

    public func embed(in navigationItem: UINavigationItem) {
        removeFromSuperview()
        navigationItem.titleView = _NavBarContainer(segmentedControl: self)
    }
}

private final class WCapsuleGlassBackgroundView: UIView {

    enum Style {
        case colorHeader
        case header
    }

    private let style: Style
    private var cornerRadius: CGFloat
    private let isInteractive: Bool

    private var glassView: UIView?
    private var overlayView: UIView?

    init(style: Style, cornerRadius: CGFloat, isInteractive: Bool) {
        self.style = style
        self.cornerRadius = cornerRadius
        self.isInteractive = isInteractive
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func updateCornerRadius(_ radius: CGFloat) {
        guard abs(radius - cornerRadius) > 0.5 else { return }
        cornerRadius = radius
        setNeedsLayout()
    }

    @discardableResult
    func hostContentIfSupported(_ contentView: UIView) -> Bool {
        guard #available(iOS 26, iOSApplicationExtension 26, *),
              isInteractive,
              let glassView = glassView as? UIVisualEffectView else {
            return false
        }
        isUserInteractionEnabled = true
        glassView.contentView.addSubview(contentView)
        return true
    }

    private func setup() {
        switch style {
        case .colorHeader:
            if #available(iOS 27, *) {
                let effect = UIGlassEffect()
                effect.isInteractive = isInteractive
                let view = UIVisualEffectView(effect: effect)
                addSubview(view)
                glassView = view
            } else if #available(iOS 26, *) {
                // UIKit's iOS 26 glass follows the light content behind the navbar,
                // despite its dark override. SwiftUI clear glass preserves this header's colors.
                let view = HostingView {
                    Color.clear.glassEffect(.clear, in: .capsule)
                }
                view.translatesAutoresizingMaskIntoConstraints = true
                addSubview(view)
                glassView = view
            } else if #available(iOS 17, *) {
                let view = ThinGlassView()
                view.fillColor = UIColor.white.withAlphaComponent(0.05)
                addSubview(view)
                glassView = view
            } else {
                // iOS 16: ThinGlassView has issues with continuous paths at ~20pt corner radii;
                // use a plain filled view with a hairline border stroke instead.
                let fill = UIView()
                fill.backgroundColor = UIColor.white.withAlphaComponent(0.05)
                addSubview(fill)
                glassView = fill

                let border = UIView()
                border.layer.borderColor = UIColor.white.withAlphaComponent(0.3).cgColor
                border.layer.borderWidth = 0.7
                border.backgroundColor = .clear
                addSubview(border)
                overlayView = border
            }
        case .header:
            if #available(iOS 26, *) {
                let effect = UIGlassEffect(style: .regular)
                effect.isInteractive = isInteractive
                let view = UIVisualEffectView(effect: effect)
                addSubview(view)
                glassView = view
            } else {
                let base = UIView()
                base.backgroundColor = UIColor.air.sheetBackground
                addSubview(base)
                overlayView = base

                let view = ThinGlassView()
                view.fillColor = UIColor.white.withAlphaComponent(0.05)
                addSubview(view)
                glassView = view

                layer.shadowColor = UIColor.black.cgColor
                layer.shadowOpacity = 0.1
                layer.shadowRadius = 8
                layer.shadowOffset = CGSize(width: 0, height: 2)
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        for subview in subviews {
            subview.frame = bounds
        }
        (glassView as? ThinGlassView)?.cornerRadius = cornerRadius

        overlayView?.layer.cornerRadius = cornerRadius
        overlayView?.layer.cornerCurve = .continuous
        overlayView?.clipsToBounds = true

        if #available(iOS 26, *), let effectView = glassView as? UIVisualEffectView {
            effectView.cornerConfiguration = .corners(radius: UICornerRadius(floatLiteral: cornerRadius))
        } else if let glassView, glassView is UIVisualEffectView {
            glassView.layer.cornerRadius = cornerRadius
            glassView.layer.cornerCurve = .continuous
            glassView.clipsToBounds = true
        }
    }
}

private final class _NavBarContainer: UIView {
    private let segmentedControl: WSegmentedControl
    private var centerXConstraint: NSLayoutConstraint!
    private var centerYConstraint: NSLayoutConstraint!
    private var widthConstraint: NSLayoutConstraint!

    init(segmentedControl: WSegmentedControl) {
        self.segmentedControl = segmentedControl

        super.init(frame: .zero)
        
        autoresizingMask = [.flexibleWidth, .flexibleHeight]

        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        addSubview(segmentedControl)
        centerXConstraint = segmentedControl.centerXAnchor.constraint(equalTo: centerXAnchor)
        centerYConstraint = segmentedControl.centerYAnchor.constraint(equalTo: centerYAnchor)
        widthConstraint = segmentedControl.widthAnchor.constraint(equalToConstant: 200)
        NSLayoutConstraint.activate([
            centerXConstraint,
            centerYConstraint,
            widthConstraint,
        ])
        
        observeModel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func observeModel() {
        withPerceptionTracking {
            _ = segmentedControl.model.items
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.invalidateIntrinsicContentSize()
                self?.setNeedsLayout()
                self?.observeModel()
            }
        }
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.layoutFittingExpandedSize.width, height: segmentedControl.model.constants.fullHeightWithBackground)
    }
    
    override func didMoveToWindow() {
        super.didMoveToWindow()
        layoutSegmentControl()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutSegmentControl()
    }

    private func layoutSegmentControl() {
        var navBar: UIView?
        do {
            var v: UIView? = superview
            while let view = v {
                if let nb = view as? UINavigationBar {
                    navBar = nb
                    break
                }
                v = view.superview
            }
        }
        
        guard let navBar else { return }
        
        let model = segmentedControl.model
        let width = min(bounds.width, model.calculateContentWidth(includeBackground: true))
        let navMidInContainer = navBar.convert(CGPoint(x: navBar.bounds.inset(by: navBar.safeAreaInsets).midX, y: 0), to: self).x
        let offset = navMidInContainer - bounds.midX
        let halfSlack = max(0, bounds.width - width) / 2
        centerXConstraint.constant = clamp(offset, to: -halfSlack...halfSlack)
        centerYConstraint.constant = -model.constants.topInset / 2
        widthConstraint.constant = CGFloat(width)
    }

}
