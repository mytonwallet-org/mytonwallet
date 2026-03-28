import UIKit

public class WrappingFlowView: UIView {
    public enum Alignment {
        case left
        case center
    }
    
    public var horizontalSpacing: CGFloat = 8 {
        didSet { if oldValue != horizontalSpacing { setNeedsLayout() }}
    }

    public var verticalSpacing: CGFloat = 8 {
        didSet { if oldValue != verticalSpacing { setNeedsLayout() }}
    }
    
    public var maxRowCount: Int? {
        didSet { if oldValue != maxRowCount { setNeedsLayout() }}
    }

    public var maxItemCount: Int? {
        didSet { if oldValue != maxItemCount { setNeedsLayout() } }
    }
    
    var horAlignment: Alignment = .left {
        didSet { if oldValue != horAlignment { setNeedsLayout() } }
    }

    @MainActor
    private class ArrangedView {
        private var cachedDimensions: CGSize?

        let view: UIView
        var forcedWidth: CGFloat?
        var isAccessory = false

        init(view: UIView) {
            self.view = view
        }
        
        @MainActor var size: CGSize {
            if let s = cachedDimensions {
                return s
            }
            let target = CGSize(
                width: UIView.layoutFittingExpandedSize.width,
                height: UIView.layoutFittingExpandedSize.height
            )
            let s = view.systemLayoutSizeFitting(
                target,
                withHorizontalFittingPriority: .defaultLow,
                verticalFittingPriority: .defaultLow
            )
            cachedDimensions = s
            return s
        }
    }

    private var arrangedSubviews: [ArrangedView] = []
    private var cachedLayoutHeight: CGFloat = 0
    private var layoutCalculatedWidth: CGFloat?
    private var trailingAccessoryFactory: ((Int) -> UIView?)?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        semanticContentAttribute = .forceLeftToRight
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: cachedLayoutHeight)
    }

    public func setArrangedSubviews(_ views: [UIView], trailingAccessoryFactory: ((Int) -> UIView?)? = nil) {
        self.arrangedSubviews = views.map { .init(view: $0) }
        self.trailingAccessoryFactory = trailingAccessoryFactory
        layoutCalculatedWidth = nil
        setNeedsLayout()
    }
    
    override public func layoutSubviews() {
        super.layoutSubviews()
        
        let w = bounds.width
        if  w > 0, layoutCalculatedWidth != w {
            layoutCalculatedWidth = w
            recalculateAndPositionContent(contentWidth: w)
        }
    }
    
    @MainActor
    private func recalculateAndPositionContent(contentWidth: CGFloat) {
        @MainActor
        struct Row {
            var views: [ArrangedView] = []
            var maxHeight: CGFloat { views.map(\.size.height).max() ?? 0 }
            var count: Int { views.count }
            
            func totalWidth(spacer: CGFloat, withAdding extraView: ArrangedView? = nil) -> CGFloat {
                var result: CGFloat = 0
                var totalCount = views.count
                if let extraView {
                    totalCount += 1
                    result += extraView.size.width
                }
                views.forEach { result += $0.size.width }
                return result + CGFloat(totalCount - 1) * spacer
            }
        }
        var rows: [Row] = []
        var currentRow = Row()
        let maxRowCount = self.maxRowCount ?? Int.max
        let maxItemCount = self.maxItemCount ?? Int.max

        // Not optimized but should work for a small count of subviews
        var totalAdded = 0
        for view in arrangedSubviews.prefix(maxItemCount) {
            let fullRowSpace = currentRow.totalWidth(spacer: horizontalSpacing, withAdding: view)
            let canAddToCurrentRow = fullRowSpace <= contentWidth
                || currentRow.count == 0
                || currentRow.totalWidth(spacer: horizontalSpacing) < contentWidth / 2
            
            if !canAddToCurrentRow {
                rows.append(currentRow)
                currentRow = .init()
                if rows.count >= maxRowCount {
                    break
                }
            }
            
            currentRow.views.append(view)
            totalAdded += 1
        }
        if currentRow.count > 0 {
            rows.append(currentRow)
        }
        
        // define the acccessory if needed
        var restToAdd = arrangedSubviews.count - totalAdded
        if restToAdd > 0, rows.count > 0 {
            var lastRow = rows.removeLast()
            while let accessoryView = trailingAccessoryFactory?(restToAdd)  {
                let aView = ArrangedView(view: accessoryView)
                aView.isAccessory = true
                let overflow = lastRow.totalWidth(spacer: horizontalSpacing) - (contentWidth - (aView.size.width + horizontalSpacing))
                if overflow > 0 {
                    if lastRow.count > 1 && lastRow.views.last!.size.width < aView.size.width  {
                        lastRow.views.removeLast()
                        restToAdd += 1
                        continue
                    }
                }
                lastRow.views.append(aView)
                break
            }
            rows.append(lastRow)
        }
                        
        // Now lay out views.
        subviews.forEach { $0.removeFromSuperview() }
        var y: CGFloat = 0
        if !rows.isEmpty {
            for row in rows {
                
                var lastNonAccessoryView: ArrangedView?
                for view in row.views {
                    view.forcedWidth = nil
                    if !view.isAccessory {
                        lastNonAccessoryView = view
                    }
                }
                var rowWidth = row.totalWidth(spacer: horizontalSpacing)
                let overflow = rowWidth - contentWidth
                if overflow > 0, let lastNonAccessoryView {
                    lastNonAccessoryView.forcedWidth = lastNonAccessoryView.size.width - overflow
                    rowWidth -= overflow
                }
                                
                var x: CGFloat = 0
                switch horAlignment {
                case .left:
                    break
                case .center:
                    x = floor((contentWidth - rowWidth) / 2)
                }
                let height = row.maxHeight
                for view in row.views {
                    addSubview(view.view)
                    let width = min(view.forcedWidth ?? view.size.width, contentWidth)
                    var r = CGRect(x: x, y: y, width: width, height: view.size.height)
                    r.origin.y += max(0, (height - r.height) / 2)
                    view.view.frame = r
                    x += r.size.width + horizontalSpacing
                }
                y += verticalSpacing + height
            }
            y -= verticalSpacing
        }
        
        if cachedLayoutHeight != y {
            cachedLayoutHeight = y
            invalidateIntrinsicContentSize()
        }
    }
}
