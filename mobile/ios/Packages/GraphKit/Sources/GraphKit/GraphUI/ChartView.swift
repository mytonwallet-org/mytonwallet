//
//  ChartView.swift
//  GraphTest
//
//  Created by Andrei Salavei on 4/7/19.
//  Copyright © 2019 Andrei Salavei. All rights reserved.
//

import UIKit

class ChartView: UIControl {
    private enum InteractionConstants {
        static let longPressDuration = 0.15
        static let longPressAllowableMovement = CGFloat(12.0)
    }

    weak var detailsSuperview: UIView? {
        didSet {
            updateDetailsViewHostIfNeeded()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        
        setupView()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        
        setupView()
    }
    
    var chartInsets: UIEdgeInsets = UIEdgeInsets(top: 40, left: 16, bottom: 35, right: 16) {
        didSet {
            setNeedsDisplay()
        }
    }
    
    var renderers: [ChartViewRenderer] = [] {
        willSet {
            renderers.forEach { $0.containerViews.removeAll(where: { $0.value == self || $0.value == nil }) }
        }
        didSet {
            renderers.forEach { $0.containerViews.append(ContainerViewReference(value: self)) }
            setNeedsDisplay()
        }
    }
    
    var chartFrame: CGRect {
        let chartBound = self.bounds
        return CGRect(x: chartInsets.left,
                      y: chartInsets.top,
                      width: max(1, chartBound.width - chartInsets.left - chartInsets.right),
                      height: max(1, chartBound.height - chartInsets.top - chartInsets.bottom))
    }
    
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let chartBounds = self.bounds
        let chartFrame = self.chartFrame
        
        for renderer in renderers {
            renderer.render(context: context, bounds: chartBounds, chartFrame: chartFrame)
        }
    }
    
    var userDidSelectCoordinateClosure: ((CGPoint) -> Void)?
    var userDidDeselectCoordinateClosure: (() -> Void)?

    private var _isTracking: Bool = false
    private lazy var tapGestureRecognizer: UITapGestureRecognizer = {
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        recognizer.cancelsTouchesInView = false
        return recognizer
    }()
    private lazy var longPressGestureRecognizer: UILongPressGestureRecognizer = {
        let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        recognizer.minimumPressDuration = InteractionConstants.longPressDuration
        recognizer.allowableMovement = InteractionConstants.longPressAllowableMovement
        recognizer.cancelsTouchesInView = false
        return recognizer
    }()

    override var isTracking: Bool {
        return self._isTracking
    }

    // MARK: Details View
    
    private var detailsView: ChartDetailsView!
    private var maxDetailsViewWidth: CGFloat = 0
    func loadDetailsViewIfNeeded() {
        let detailsHostView = resolvedDetailsSuperview
        if detailsView == nil {
            let detailsView = ChartDetailsView(frame: bounds)
            detailsHostView.addSubview(detailsView)
            detailsView.alpha = 0
            self.detailsView = detailsView
        } else if detailsView.superview !== detailsHostView {
            detailsView.removeFromSuperview()
            detailsHostView.addSubview(detailsView)
        }

        updateDetailsViewFrame()
    }
    
    private var detailsTableTopOffset: CGFloat = 5
    private var detailsTableLeftOffset: CGFloat = 8
    private var isDetailsViewVisible: Bool = false

    var detailsViewPosition: CGFloat = 0 {
        didSet {
            loadDetailsViewIfNeeded()
        }
    }
    
    private func updateDetailsViewFrame() {
        guard let detailsView else {
            return
        }
        
        let detailsHostView = resolvedDetailsSuperview
        let previousSuperView = detailsView.superview
        if previousSuperView !== detailsHostView {
            detailsView.removeFromSuperview()
            detailsHostView.addSubview(detailsView)
        }

        let chartLocalFrame: CGRect
        let detailsViewSize = detailsView.intrinsicContentSize
        maxDetailsViewWidth = max(maxDetailsViewWidth, detailsViewSize.width)
        if maxDetailsViewWidth + detailsTableLeftOffset > detailsViewPosition {
            chartLocalFrame = CGRect(x: max(detailsTableLeftOffset, min(detailsViewPosition + detailsTableLeftOffset, bounds.width - maxDetailsViewWidth - detailsTableLeftOffset)),
                                     y: chartInsets.top + detailsTableTopOffset,
                                     width: maxDetailsViewWidth,
                                     height: detailsViewSize.height)
        } else {
            chartLocalFrame = CGRect(x: max(detailsTableLeftOffset, min(detailsViewPosition - maxDetailsViewWidth - detailsTableLeftOffset, bounds.width - maxDetailsViewWidth - detailsTableLeftOffset)),
                                     y: chartInsets.top + detailsTableTopOffset,
                                     width: maxDetailsViewWidth,
                                     height: detailsViewSize.height)
        }

        if detailsHostView === self {
            detailsView.frame = chartLocalFrame
        } else {
            detailsView.frame = convert(chartLocalFrame, to: detailsHostView)
        }

        detailsView.bringToFront()
    }

    private var resolvedDetailsSuperview: UIView {
        detailsSuperview ?? self
    }

    private func updateDetailsViewHostIfNeeded() {
        guard detailsView != nil else {
            return
        }

        loadDetailsViewIfNeeded()
        let position = detailsViewPosition
        detailsViewPosition = position
    }
    
    func setDetailsChartVisible(_ visible: Bool, animated: Bool) {
        guard isDetailsViewVisible != visible else {
            return
        }
        isDetailsViewVisible = visible
        loadDetailsViewIfNeeded()
        detailsView.setVisible(visible, animated: animated)
        if !visible {
            maxDetailsViewWidth = 0
        }
    }
    
    func setDetailsViewModel(viewModel: ChartDetailsViewModel, animated: Bool) {
        loadDetailsViewIfNeeded()
        detailsView.setup(viewModel: viewModel, animated: animated)
        UIView.perform(animated: animated, animations: {
            let position = self.detailsViewPosition
            self.detailsViewPosition = position
        })
    }

    func setupView() {
        backgroundColor = .clear
        layer.drawsAsynchronously = true
        addGestureRecognizer(tapGestureRecognizer)
        addGestureRecognizer(longPressGestureRecognizer)
        tapGestureRecognizer.require(toFail: longPressGestureRecognizer)
    }
}

private extension ChartView {
    @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else {
            return
        }

        select(at: recognizer.location(in: self))
        userDidDeselectCoordinateClosure?()
        _isTracking = false
    }

    @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began, .changed:
            _isTracking = true
            select(at: recognizer.location(in: self))
        case .ended, .cancelled, .failed:
            userDidDeselectCoordinateClosure?()
            _isTracking = false
        default:
            break
        }
    }

    func select(at location: CGPoint) {
        guard chartFrame.width > 0.0, chartFrame.height > 0.0 else {
            return
        }

        let clampedPoint = CGPoint(
            x: max(0.0, min(frame.width, location.x)),
            y: max(0.0, min(frame.height, location.y))
        )
        let fractionPoint = CGPoint(
            x: (clampedPoint.x - chartFrame.origin.x) / chartFrame.width,
            y: (clampedPoint.y - chartFrame.origin.y) / chartFrame.height
        )
        userDidSelectCoordinateClosure?(fractionPoint)
    }
}


extension ChartView: ChartThemeContainer {
    func apply(theme: ChartTheme, strings: ChartStrings, animated: Bool) {
        detailsView?.apply(theme: theme, strings: strings, animated: animated && (detailsView?.isVisibleInWindow ?? false))
    }
}
