import UIKit
import WalletContext

enum TwoZoneAxis: Equatable {
    case horizontal, vertical
}

enum TwoZoneItemContext {
    case source
    case destination
    case dragging
}

protocol TwoZoneItem {
    var isLocked: Bool { get }
}

struct TwoZoneDragConfig<Item: TwoZoneItem> {
    var axis: TwoZoneAxis
    var destMaxItems: Int
    var sourceColumnCount: Int
    var itemHeight: CGFloat
    var itemSpacing: CGFloat
    var separatorThickness: CGFloat
    var destColumnWidth: CGFloat
    var destMargins: UIEdgeInsets = .zero
    var destInsets: UIEdgeInsets
    var sourceInsets: UIEdgeInsets = .zero
    var tileProvider: (Item, TwoZoneItemContext) -> UIView
    var onReorderHaptic: (() -> Void)?
}

final class TwoZoneDragView<Item: TwoZoneItem>: UIView, UIGestureRecognizerDelegate {

    private enum DestEntry {
        case real(Item)
        case placeholder

        var item: Item? {
            guard case .real(let i) = self else { return nil }
            return i
        }
        var isPlaceholder: Bool {
            if case .placeholder = self { return true }
            return false
        }
    }

    private struct ActiveDrag {
        enum Origin {
            case destination(index: Int)
            case source(index: Int)
        }
        let origin: Origin
        let snapshotView: UIView
        let sourceTileView: UIView
        let originCenterInSelf: CGPoint
        var liveDestIndex: Int?
        var removedFromDest: Item?
        var pendingInsertIndex: Int?
    }

    private let config: TwoZoneDragConfig<Item>

    var onDrop: (([Item], [Item]) -> Void)?

    var currentDestItems: [Item] { destEntries.compactMap(\.item) }
    var currentSourceItems: [Item] { sourceItems }

    private var destEntries: [DestEntry] = []
    private var sourceItems: [Item] = []
    private var destTileViews: [UIView] = []
    private var sourceTileViews: [UIView] = []

    private let destContainer = UIView()
    private let sourceContentView = UIView()
    
    let separatorView = UIView()
    let sourcePaletteScroll = UIScrollView()

    private var destTileWidth: CGFloat = 0
    private var sourceTileWidth: CGFloat = 0
    private var hasLaidOut = false
    private var lastScrollBoundsSize: CGSize = .zero

    private var activeDrag: ActiveDrag?
    private var dragCenterOffset: CGPoint = .zero
    private var lastLiveReorderLocation: CGPoint = .zero
    private var sourcePressStartLocation: CGPoint?
    private var sourcePressStartTime: Date?
    private var dragLongPress: UILongPressGestureRecognizer!
    private var sourceLongPress: UILongPressGestureRecognizer!

    init(config: TwoZoneDragConfig<Item>) {
        self.config = config
        super.init(frame: .zero)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    func load(dest: [Item], source: [Item]) {
        destTileViews.forEach { $0.removeFromSuperview() }
        sourceTileViews.forEach { $0.removeFromSuperview() }
        destTileViews = []
        sourceTileViews = []
        destEntries = dest.map { .real($0) }
        sourceItems = source

        guard hasLaidOut else { return }

        for item in dest {
            let v = makeTile(for: item, context: .destination)
            destContainer.addSubview(v)
            destTileViews.append(v)
        }
        layoutDestZone(animated: false)

        for item in source {
            let v = makeTile(for: item, context: .source)
            sourceContentView.addSubview(v)
            sourceTileViews.append(v)
        }
        layoutSourceGrid(animated: false)
    }

    private func setupViews() {
        [destContainer, separatorView, sourcePaletteScroll].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        sourcePaletteScroll.alwaysBounceVertical = false
        sourcePaletteScroll.addSubview(sourceContentView)

        let barH = config.destInsets.vertical + config.itemHeight
        switch config.axis {
        case .horizontal:
            if #available(iOS 26, *) {
                let glassView = UIVisualEffectView(effect: UIGlassEffect())
                glassView.translatesAutoresizingMaskIntoConstraints = false
                glassView.layer.cornerRadius = barH / 2
                glassView.layer.cornerCurve = .continuous
                glassView.clipsToBounds = true
                glassView.backgroundColor = .air.groupedItem
                destContainer.addSubview(glassView)
                NSLayoutConstraint.activate([
                    glassView.topAnchor.constraint(equalTo: destContainer.topAnchor),
                    glassView.leadingAnchor.constraint(equalTo: destContainer.leadingAnchor),
                    glassView.trailingAnchor.constraint(equalTo: destContainer.trailingAnchor),
                    glassView.bottomAnchor.constraint(equalTo: destContainer.bottomAnchor),
                ])
            } else {
                destContainer.backgroundColor = .secondarySystemGroupedBackground
                destContainer.layer.cornerRadius = barH / 2
                destContainer.layer.cornerCurve = .continuous
                destContainer.layer.masksToBounds = true
            }
        case .vertical:
            break
        }

        let ins = config.destInsets
        let mg = config.destMargins
        switch config.axis {
        case .horizontal:
            let destH = ins.top + config.itemHeight + ins.bottom
            NSLayoutConstraint.activate([
                destContainer.topAnchor.constraint(equalTo: topAnchor, constant: mg.top),
                destContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: mg.left),
                destContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -mg.right),
                destContainer.heightAnchor.constraint(equalToConstant: destH),

                separatorView.topAnchor.constraint(equalTo: destContainer.bottomAnchor),
                separatorView.leadingAnchor.constraint(equalTo: leadingAnchor),
                separatorView.trailingAnchor.constraint(equalTo: trailingAnchor),
                separatorView.heightAnchor.constraint(equalToConstant: config.separatorThickness),

                sourcePaletteScroll.topAnchor.constraint(equalTo: separatorView.bottomAnchor),
                sourcePaletteScroll.leadingAnchor.constraint(equalTo: leadingAnchor),
                sourcePaletteScroll.trailingAnchor.constraint(equalTo: trailingAnchor),
                sourcePaletteScroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])

        case .vertical:
            NSLayoutConstraint.activate([
                destContainer.topAnchor.constraint(equalTo: topAnchor, constant: mg.top),
                destContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: mg.left),
                destContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -mg.bottom),
                destContainer.widthAnchor.constraint(equalToConstant: config.destColumnWidth),

                separatorView.topAnchor.constraint(equalTo: topAnchor),
                separatorView.leadingAnchor.constraint(equalTo: destContainer.trailingAnchor),
                separatorView.bottomAnchor.constraint(equalTo: bottomAnchor),
                separatorView.widthAnchor.constraint(equalToConstant: config.separatorThickness),

                sourcePaletteScroll.topAnchor.constraint(equalTo: topAnchor),
                sourcePaletteScroll.leadingAnchor.constraint(equalTo: separatorView.trailingAnchor),
                sourcePaletteScroll.trailingAnchor.constraint(equalTo: trailingAnchor),
                sourcePaletteScroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
        
        dragLongPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        dragLongPress.minimumPressDuration = 0
        dragLongPress.delegate = self
        destContainer.addGestureRecognizer(dragLongPress)

        sourceLongPress = UILongPressGestureRecognizer(target: self, action: #selector(handleSourceLongPress(_:)))
        sourceLongPress.minimumPressDuration = 0
        sourceLongPress.delegate = self
        sourcePaletteScroll.addGestureRecognizer(sourceLongPress)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = computeTileWidths()
        guard w.dest > 0 else { return }

        if !hasLaidOut {
            destTileWidth = w.dest
            sourceTileWidth = w.source
            buildInitialViews()
            hasLaidOut = true
            lastScrollBoundsSize = sourcePaletteScroll.bounds.size
        } else {
            let widthChanged = w.dest != destTileWidth || w.source != sourceTileWidth
            let scrollChanged = sourcePaletteScroll.bounds.size != lastScrollBoundsSize
            if widthChanged {
                destTileWidth = w.dest
                sourceTileWidth = w.source
                layoutDestZone(animated: false)
            }
            if widthChanged || scrollChanged {
                lastScrollBoundsSize = sourcePaletteScroll.bounds.size
                layoutSourceGrid(animated: false)
            }
        }
    }

    private func computeTileWidths() -> (dest: CGFloat, source: CGFloat) {
        let ci = sourcePaletteScroll.contentInset
        let spacing = CGFloat(config.sourceColumnCount - 1) * config.itemSpacing
        switch config.axis {
        case .horizontal:
            let ins = config.destInsets
            let mg = config.destMargins
            let destW = bounds.width - mg.left - mg.right - ins.left - ins.right
            let dw = (destW - spacing) / CGFloat(config.sourceColumnCount)
            let si = config.sourceInsets
            let paletteW = bounds.width - ci.left - ci.right - si.left - si.right
            let sw = (paletteW - spacing) / CGFloat(config.sourceColumnCount)
            return (dw, sw)
        case .vertical:
            let dw = config.destColumnWidth - config.destInsets.left - config.destInsets.right
            let si = config.sourceInsets
            let paletteW = sourcePaletteScroll.bounds.width - ci.left - ci.right - si.left - si.right
            guard paletteW > 0 else { return (dw, 0) }
            let sw = (paletteW - spacing) / CGFloat(config.sourceColumnCount)
            return (dw, sw)
        }
    }
    
    private func makeTile(for item: Item, context: TwoZoneItemContext) -> UIView {
        config.tileProvider(item, context)
    }

    private func buildInitialViews() {
        for entry in destEntries {
            let v: UIView = entry.item.map { makeTile(for: $0, context: .destination) } ?? {
                let spacer = UIView(); spacer.isHidden = true; return spacer
            }()
            destContainer.addSubview(v)
            destTileViews.append(v)
        }
        layoutDestZone(animated: false)

        for item in sourceItems {
            let v = makeTile(for: item, context: .source)
            sourceContentView.addSubview(v)
            sourceTileViews.append(v)
        }
        layoutSourceGrid(animated: false)
    }

    private func layoutDestZone(animated: Bool, duration: TimeInterval = 0.52) {
        guard destTileWidth > 0 else { return }
        let block: () -> Void

        let ins = config.destInsets
        switch config.axis {
        case .horizontal:
            block = {
                let n = self.destTileViews.count
                let avail = self.destContainer.bounds.width - ins.left - ins.right
                let totalW = CGFloat(n) * self.destTileWidth + CGFloat(max(n - 1, 0)) * self.config.itemSpacing
                let startX = ins.left + (avail - totalW) / 2
                for (i, v) in self.destTileViews.enumerated() {
                    let x = startX + CGFloat(i) * (self.destTileWidth + self.config.itemSpacing)
                    v.frame = CGRect(x: x, y: ins.top,
                                     width: self.destTileWidth, height: self.config.itemHeight)
                }
            }

        case .vertical:
            block = {
                for (i, v) in self.destTileViews.enumerated() {
                    let y = ins.top + CGFloat(i) * (self.config.itemHeight + self.config.itemSpacing)
                    v.frame = CGRect(x: ins.left, y: y,
                                     width: self.destTileWidth, height: self.config.itemHeight)
                }
            }
        }

        if animated {
            springAnimate(duration: duration, damping: 0.62, block)
        } else {
            block()
        }
    }

    private func layoutSourceGrid(animated: Bool, duration: TimeInterval = 0.52) {
        guard sourceTileWidth > 0 else { return }
        let block = {
            let si = self.config.sourceInsets
            for (i, v) in self.sourceTileViews.enumerated() {
                let col = i % self.config.sourceColumnCount
                let row = i / self.config.sourceColumnCount
                let x = si.left + CGFloat(col) * (self.sourceTileWidth + self.config.itemSpacing)
                let y = si.top + CGFloat(row) * (self.config.itemHeight + self.config.itemSpacing)
                v.frame = CGRect(x: x, y: y, width: self.sourceTileWidth, height: self.config.itemHeight)
            }
            let numRows = max((self.sourceTileViews.count + self.config.sourceColumnCount - 1) / self.config.sourceColumnCount, 1)
            let contentH = si.top + CGFloat(numRows) * self.config.itemHeight +
                           CGFloat(max(numRows - 1, 0)) * self.config.itemSpacing + si.bottom
            let ci = self.sourcePaletteScroll.contentInset
            let contentW = max(self.sourcePaletteScroll.bounds.width - ci.left - ci.right, 1)
            self.sourceContentView.frame = .fromSize(width: contentW, height: contentH)
            self.sourcePaletteScroll.contentSize = CGSize(width: contentW, height: contentH)
        }
        if animated {
            springAnimate(duration: duration, damping: 0.62, block)
        } else {
            block()
        }
    }

    private func springAnimate(
        duration: TimeInterval, damping: CGFloat,
        options: UIView.AnimationOptions = [.allowUserInteraction, .beginFromCurrentState],
        _ block: @escaping () -> Void,
        completion: ((Bool) -> Void)? = nil) {
        UIView.animate(withDuration: duration, delay: 0,
                       usingSpringWithDamping: damping,
                       initialSpringVelocity: 0,
                       options: options,
                       animations: block,
                       completion: completion)
    }

    private func sourceInsertionIndex(for dropCenter: CGPoint) -> Int {
        guard sourceTileWidth > 0 else { return sourceItems.count }
        let pt = convert(dropCenter, to: sourceContentView)
        let col = min(max(Int(pt.x / (sourceTileWidth + config.itemSpacing)), 0), config.sourceColumnCount - 1)
        let row = max(Int(pt.y / (config.itemHeight + config.itemSpacing)), 0)
        return min(row * config.sourceColumnCount + col, sourceItems.count)
    }

    private func separatorRectInSelf() -> CGRect {
        separatorView.convert(separatorView.bounds, to: self)
    }

    private func isOverDest(_ center: CGPoint) -> Bool {
        let sep = separatorRectInSelf()
        switch config.axis {
        case .horizontal: return center.y < sep.minY
        case .vertical: return center.x < sep.minX
        }
    }

    private func isOverSource(_ center: CGPoint) -> Bool {
        let sep = separatorRectInSelf()
        switch config.axis {
        case .horizontal: return center.y > sep.maxY
        case .vertical: return center.x > sep.maxX
        }
    }

    private var realDestCount: Int { destEntries.filter { !$0.isPlaceholder }.count }

    private func destItem(at index: Int) -> Item? { destEntries[safe: index]?.item }

    private func nearestDestIndex(for center: CGPoint) -> Int {
        guard !destTileViews.isEmpty else { return 0 }
        let pt = convert(center, to: destContainer)
        var best = (index: 0, dist: CGFloat.greatestFiniteMagnitude)
        for (i, v) in destTileViews.enumerated() {
            let d: CGFloat = config.axis == .horizontal ? abs(v.frame.midX - pt.x) : abs(v.frame.midY - pt.y)
            if d < best.dist { best = (i, d) }
        }
        return best.index
    }

    private func insertionIndexForDrop(at center: CGPoint) -> Int {
        let pt = convert(center, to: destContainer)
        for (i, v) in destTileViews.enumerated() {
            let past = config.axis == .horizontal ? pt.x < v.frame.midX : pt.y < v.frame.midY
            if past { return i }
        }
        return destTileViews.count
    }

    private func insertionIndexForPlaceholder(at center: CGPoint) -> Int {
        let pt = convert(center, to: destContainer)
        for (i, v) in destTileViews.enumerated() {
            guard !destEntries[i].isPlaceholder else { continue }
            let past = config.axis == .horizontal ? pt.x < v.frame.midX : pt.y < v.frame.midY
            if past { return i }
        }
        for i in stride(from: destTileViews.count - 1, through: 0, by: -1) {
            if !destEntries[i].isPlaceholder { return i + 1 }
        }
        return 0
    }

    private func makeDragView(for item: Item, originalTile: UIView) -> UIView {
        let tile = makeTile(for: item, context: .dragging)
        let frame = originalTile.superview?.convert(originalTile.frame, to: self) ?? originalTile.frame
        tile.frame = frame
        tile.layoutIfNeeded()

        if #available(iOS 26, *) {
            let container = UIView(frame: frame)
            let effect =  UIGlassEffect()
            effect.isInteractive = true
            let glassView = UIVisualEffectView(effect: effect)
            glassView.frame = container.bounds
            glassView.layer.cornerRadius = frame.height / 2
            glassView.layer.cornerCurve = .continuous
            glassView.clipsToBounds = true
            container.addSubview(glassView)

            tile.frame = container.bounds
            tile.backgroundColor = .clear
            container.addSubview(tile)
            return container
        }
        return tile
    }

    private func landSnapshot(_ snapshot: UIView, on targetView: UIView) {
        let targetCenter = targetView.superview?.convert(targetView.center, to: self) ?? .zero
        let d = hypot(snapshot.center.x - targetCenter.x, snapshot.center.y - targetCenter.y)
        springAnimate(duration: max(0.25, min(d / 1000, 0.42)), damping: 0.72, options: .allowUserInteraction,
            {
                snapshot.center = targetCenter
                snapshot.transform = .identity
            },
            completion: { _ in
                snapshot.removeFromSuperview()
                targetView.isHidden = false
            }
        )
    }

    private func lockPaletteScroll() {
        sourcePaletteScroll.isScrollEnabled = false
        sourcePaletteScroll.panGestureRecognizer.isEnabled = false
    }

    private func unlockPaletteScroll() {
        sourcePaletteScroll.isScrollEnabled = true
        sourcePaletteScroll.panGestureRecognizer.isEnabled = true
    }

    private func insertPlaceholderInDest(at index: Int) {
        destEntries.insert(.placeholder, at: index)
        let spacer = UIView()
        spacer.isHidden = true
        destTileViews.insert(spacer, at: index)
        destContainer.addSubview(spacer)
    }

    private func removePlaceholderFromDest(drag: inout ActiveDrag) {
        guard let idx = drag.pendingInsertIndex else { return }
        drag.pendingInsertIndex = nil
        destEntries.remove(at: idx)
        destTileViews.remove(at: idx).removeFromSuperview()
        layoutDestZone(animated: true)
    }

    private var canScrollSource: Bool {
        sourcePaletteScroll.contentSize.height > sourcePaletteScroll.bounds.height
    }

    private func startDrag(origin: ActiveDrag.Origin, tileView: UIView, at location: CGPoint) {
        if case .destination = origin {
            lockPaletteScroll()
        } else if !canScrollSource {
            lockPaletteScroll()
        }
        let centerInSelf = tileView.superview?.convert(tileView.center, to: self) ?? .zero
        let item: Item
        switch origin {
        case .destination(let i):
            guard let destItem = destEntries[i].item else { return }
            item = destItem
        case .source(let i):
            item = sourceItems[i]
        }
        let dragView = makeDragView(for: item, originalTile: tileView)
        addSubview(dragView)
        tileView.isHidden = true
        dragCenterOffset = CGPoint(x: location.x - centerInSelf.x, y: location.y - centerInSelf.y)
        lastLiveReorderLocation = location
        var liveDestIdx: Int? = nil
        if case .destination(let i) = origin { liveDestIdx = i }
        activeDrag = ActiveDrag(origin: origin, snapshotView: dragView,
                                sourceTileView: tileView, originCenterInSelf: centerInSelf,
                                liveDestIndex: liveDestIdx)
        UIView.animate(withDuration: 0.18, delay: 0, options: .curveEaseOut) {
            dragView.transform = CGAffineTransform(scaleX: 1.06, y: 1.06)
        }
        config.onReorderHaptic?()
    }

    private func cancelActiveDrag() {
        guard var drag = activeDrag else { return }
        activeDrag = nil
        sourcePressStartLocation = nil
        sourcePressStartTime = nil
        drag.snapshotView.removeFromSuperview()
        unlockPaletteScroll()

        switch drag.origin {
        case .source:
            if drag.pendingInsertIndex != nil {
                removePlaceholderFromDest(drag: &drag)
            }
            drag.sourceTileView.isHidden = false

        case .destination(let originalIdx):
            if let item = drag.removedFromDest {
                if let placeholderIdx = drag.liveDestIndex,
                   destEntries[safe: placeholderIdx]?.isPlaceholder == true {
                    destEntries[placeholderIdx] = .real(item)
                    destTileViews[placeholderIdx].removeFromSuperview()
                    destTileViews[placeholderIdx] = drag.sourceTileView
                } else {
                    let insertIdx = min(originalIdx, destEntries.count)
                    destEntries.insert(.real(item), at: insertIdx)
                    destTileViews.insert(drag.sourceTileView, at: insertIdx)
                }
                destContainer.addSubview(drag.sourceTileView)
                drag.sourceTileView.isHidden = false
                layoutDestZone(animated: true)
            } else {
                drag.sourceTileView.isHidden = false
                layoutDestZone(animated: true)
            }
        }
    }

    private func dragChanged(at location: CGPoint) {
        guard var drag = activeDrag else { return }

        var center = CGPoint(x: location.x - dragCenterOffset.x, y: location.y - dragCenterOffset.y)

        if case .destination = drag.origin,
           let idx = drag.liveDestIndex,
           destItem(at: idx)?.isLocked == true {
            let snapW = drag.snapshotView.bounds.width
            let snapH = drag.snapshotView.bounds.height
            let destFrame = destContainer.frame
            switch config.axis {
            case .horizontal:
                center.y = drag.originCenterInSelf.y
                center.x = clamp(center.x, to: destFrame.minX + snapW/2 ... destFrame.maxX - snapW/2)
            case .vertical:
                center.x = drag.originCenterInSelf.x
                center.y = clamp(center.y, to: destFrame.minY + snapH/2 ... destFrame.maxY - snapH/2)
            }
        }

        drag.snapshotView.center = center

        switch drag.origin {
        case .destination:
            if isOverDest(center), let currentIdx = drag.liveDestIndex, let entry = destEntries[safe: currentIdx], !entry.isPlaceholder {
                let moved = max(abs(location.x - lastLiveReorderLocation.x), abs(location.y - lastLiveReorderLocation.y)) >= 8
                if moved {
                    let newIdx = nearestDestIndex(for: center)
                    if newIdx != currentIdx {
                        destEntries.swapBetween(currentIdx, newIdx)
                        destTileViews.swapBetween(currentIdx, newIdx)
                        drag.liveDestIndex = newIdx
                        lastLiveReorderLocation = location
                        layoutDestZone(animated: true)
                        config.onReorderHaptic?()
                    }
                }
            }
            manageDraggedDestSlot(drag: &drag, center: center)
        case .source:
            updateSourcePlaceholder(drag: &drag, center: center)
        }

        activeDrag = drag
    }

    private func manageDraggedDestSlot(drag: inout ActiveDrag, center: CGPoint) {
        let overDest = isOverDest(center)

        if !overDest {
            guard let slotIdx = drag.liveDestIndex else { return }
            if let item = destEntries[slotIdx].item { drag.removedFromDest = item }
            destEntries.remove(at: slotIdx)
            destTileViews.remove(at: slotIdx).removeFromSuperview()
            drag.liveDestIndex = nil
            layoutDestZone(animated: true)
        } else if drag.liveDestIndex == nil {
            let idx = min(insertionIndexForPlaceholder(at: center), destEntries.count)
            insertPlaceholderInDest(at: idx)
            drag.liveDestIndex = idx
            layoutDestZone(animated: true)
        } else if let currentIdx = drag.liveDestIndex,
                  destEntries[safe: currentIdx]?.isPlaceholder == true {
            let targetIdx = insertionIndexForPlaceholder(at: center)
            guard targetIdx != currentIdx, targetIdx != currentIdx + 1 else { return }
            let adj = min(targetIdx > currentIdx ? targetIdx - 1 : targetIdx, destEntries.count - 1)
            guard adj != currentIdx else { return }
            destEntries.swapBetween(currentIdx, adj)
            destTileViews.swapBetween(currentIdx, adj)
            drag.liveDestIndex = adj
            layoutDestZone(animated: true)
        }
    }

    private func updateSourcePlaceholder(drag: inout ActiveDrag, center: CGPoint) {
        guard isOverDest(center) && realDestCount < config.destMaxItems else {
            removePlaceholderFromDest(drag: &drag)
            return
        }
        let targetIdx = insertionIndexForPlaceholder(at: center)
        if let currentIdx = drag.pendingInsertIndex {
            guard targetIdx != currentIdx, targetIdx != currentIdx + 1 else { return }
            let adj = min(targetIdx > currentIdx ? targetIdx - 1 : targetIdx, destEntries.count - 1)
            guard adj != currentIdx else { return }
            destEntries.swapBetween(currentIdx, adj)
            destTileViews.swapBetween(currentIdx, adj)
            drag.pendingInsertIndex = adj
            layoutDestZone(animated: true)
        } else {
            let clamped = min(targetIdx, destEntries.count)
            insertPlaceholderInDest(at: clamped)
            drag.pendingInsertIndex = clamped
            layoutDestZone(animated: true)
        }
    }

    private func dragEnded() {
        guard var drag = activeDrag else { return }
        activeDrag = nil
        defer { unlockPaletteScroll() }

        let center = drag.snapshotView.center
        let inDest = isOverDest(center)
        let inSource = isOverSource(center)

        switch drag.origin {
        case .destination(let originalIndex):
            let realItem: Item? = {
                if let idx = drag.liveDestIndex { return destItem(at: idx) ?? drag.removedFromDest }
                return drag.removedFromDest
            }()
            guard let realItem else {
                drag.snapshotView.removeFromSuperview()
                drag.sourceTileView.isHidden = false
                break
            }

            if !realItem.isLocked && inSource {
                if let slotIdx = drag.liveDestIndex {
                    if let item = destEntries[slotIdx].item { drag.removedFromDest = item }
                    destEntries.remove(at: slotIdx)
                    destTileViews.remove(at: slotIdx).removeFromSuperview()
                    drag.liveDestIndex = nil
                    layoutDestZone(animated: true)
                }
                guard let item = drag.removedFromDest else {
                    drag.snapshotView.removeFromSuperview(); break
                }
                let insertIdx = sourceInsertionIndex(for: center)
                sourceItems.insert(item, at: insertIdx)
                let nv = makeTile(for: item, context: .source)
                nv.isHidden = true
                sourceContentView.addSubview(nv)
                sourceTileViews.insert(nv, at: insertIdx)
                let col = insertIdx % config.sourceColumnCount
                let row = insertIdx / config.sourceColumnCount
                nv.frame = CGRect(
                    x: CGFloat(col) * (sourceTileWidth + config.itemSpacing),
                    y: CGFloat(row) * (config.itemHeight + config.itemSpacing),
                    width: sourceTileWidth, height: config.itemHeight
                )
                layoutSourceGrid(animated: true)
                landSnapshot(drag.snapshotView, on: nv)
                onDrop?(currentDestItems, currentSourceItems)

            } else if let liveIdx = drag.liveDestIndex {
                if destEntries[safe: liveIdx]?.isPlaceholder == true,
                   let restored = drag.removedFromDest {
                    destEntries[liveIdx] = .real(restored)
                    destTileViews[liveIdx].removeFromSuperview()
                    let rv = drag.sourceTileView
                    rv.isHidden = true
                    destTileViews[liveIdx] = rv
                    destContainer.addSubview(rv)
                    layoutDestZone(animated: false)
                    landSnapshot(drag.snapshotView, on: rv)
                } else {
                    layoutDestZone(animated: false)
                    landSnapshot(drag.snapshotView, on: drag.sourceTileView)
                }
                onDrop?(currentDestItems, currentSourceItems)

            } else {
                let reinsertIdx = min(originalIndex, destEntries.count)
                destEntries.insert(.real(realItem), at: reinsertIdx)
                let rv = drag.sourceTileView
                rv.isHidden = true
                destTileViews.insert(rv, at: reinsertIdx)
                destContainer.addSubview(rv)
                layoutDestZone(animated: false)
                landSnapshot(drag.snapshotView, on: rv)
            }

        case .source(let originalIndex):
            if inDest, let insertIdx = drag.pendingInsertIndex {
                let item = sourceItems.remove(at: originalIndex)
                drag.pendingInsertIndex = nil
                sourceTileViews.remove(at: originalIndex).removeFromSuperview()
                layoutSourceGrid(animated: true)

                destEntries[insertIdx] = .real(item)
                destTileViews[insertIdx].removeFromSuperview()
                let nv = makeTile(for: item, context: .destination)
                nv.isHidden = true
                destTileViews[insertIdx] = nv
                destContainer.addSubview(nv)
                layoutDestZone(animated: false)
                landSnapshot(drag.snapshotView, on: nv)
                onDrop?(currentDestItems, currentSourceItems)

            } else if inDest && realDestCount < config.destMaxItems {
                let insertIdx = min(insertionIndexForDrop(at: center), destEntries.count)
                let item = sourceItems.remove(at: originalIndex)
                destEntries.insert(.real(item), at: insertIdx)
                sourceTileViews.remove(at: originalIndex).removeFromSuperview()
                layoutSourceGrid(animated: true)
                let nv = makeTile(for: item, context: .destination)
                nv.isHidden = true
                destTileViews.insert(nv, at: insertIdx)
                destContainer.addSubview(nv)
                layoutDestZone(animated: false)
                landSnapshot(drag.snapshotView, on: nv)
                onDrop?(currentDestItems, currentSourceItems)

            } else {
                removePlaceholderFromDest(drag: &drag)
                landSnapshot(drag.snapshotView, on: drag.sourceTileView)
            }
        }
    }

    override func gestureRecognizerShouldBegin(_ gr: UIGestureRecognizer) -> Bool {
        switch gr {
        case dragLongPress:
            let pt = gr.location(in: destContainer)
            return destTileViews.enumerated().contains { i, v in
                !destEntries[i].isPlaceholder && v.frame.contains(pt)
            }
        case sourceLongPress:
            let pt = gr.location(in: sourceContentView)
            return sourceTileViews.contains { !$0.isHidden && $0.frame.contains(pt) }
        default:
            return true
        }
    }

    func gestureRecognizer(_ gr: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        guard gr === sourceLongPress,
              other === sourcePaletteScroll.panGestureRecognizer else { return false }
        return canScrollSource
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            let pt = gesture.location(in: destContainer)
            guard let hit = destTileViews.enumerated().first(where: {
                !destEntries[$0.offset].isPlaceholder && $0.element.frame.contains(pt)
            }) else { return }
            startDrag(origin: .destination(index: hit.offset),
                      tileView: hit.element,
                      at: gesture.location(in: self))
        case .changed:
            dragChanged(at: gesture.location(in: self))
        case .ended, .cancelled:
            dragEnded()
        default: break
        }
    }

    @objc private func handleSourceLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            let pt = gesture.location(in: sourceContentView)
            guard let hit = sourceTileViews.enumerated().first(where: {
                !$0.element.isHidden && $0.element.frame.contains(pt)
            }) else { return }
            sourcePressStartLocation = gesture.location(in: self)
            sourcePressStartTime = Date()
            startDrag(origin: .source(index: hit.offset), tileView: hit.element, at: gesture.location(in: self))

        case .changed:
            guard let drag = activeDrag else { return }
            if case .source = drag.origin, let start = sourcePressStartLocation {
                let current = gesture.location(in: self)
                let dragCenter = CGPoint(x: current.x - dragCenterOffset.x,
                                        y: current.y - dragCenterOffset.y)
                if isOverDest(dragCenter) {
                    sourcePressStartLocation = nil
                    sourcePressStartTime = nil
                    lockPaletteScroll()
                } else {
                    let dy = current.y - start.y
                    let distance = hypot(current.x - start.x, dy)
                    if distance > 8 {
                        let elapsed = max(-(sourcePressStartTime ?? Date()).timeIntervalSinceNow, 0.001)
                        if abs(dy) / elapsed > 450 {
                            cancelActiveDrag()
                            return
                        }
                        sourcePressStartLocation = nil
                        sourcePressStartTime = nil
                        lockPaletteScroll()
                    }
                }
            }
            dragChanged(at: gesture.location(in: self))

        case .ended, .cancelled:
            sourcePressStartLocation = nil
            sourcePressStartTime = nil
            if activeDrag != nil { dragEnded() }

        default: break
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }

    mutating func swapBetween(_ from: Int, _ to: Int) {
        let element = remove(at: from)
        insert(element, at: to)
    }
}
