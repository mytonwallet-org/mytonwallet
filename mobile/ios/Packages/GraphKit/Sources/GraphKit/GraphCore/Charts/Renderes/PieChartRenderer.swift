//
//  PieChartRenderer.swift
//  GraphTest
//
//  Created by Andrei Salavei on 4/11/19.
//  Copyright © 2019 Andrei Salavei. All rights reserved.
//

import Foundation
#if os(macOS)
import Cocoa
#else
import UIKit
#endif

struct PieChartGeometry {
    let center: CGPoint
    let radius: CGFloat
    let innerRadius: CGFloat
    var selectionOffset: CGFloat { radius / 14 }

    init(chartFrame: CGRect, drawsDonut: Bool) {
        center = CGPoint(x: chartFrame.midX, y: chartFrame.midY)
        let availableRadius = min(chartFrame.width, chartFrame.height) / 2 * 14 / 15
        radius = drawsDonut ? min(availableRadius, 110) : availableRadius
        innerRadius = drawsDonut ? radius / 2 : 0
    }
}

enum DonutChartHighlight {
    // Figma's white radial overlay fades from 24% at the center to clear at the rim.
    private static let gradient = CGGradient(
        colorSpace: CGColorSpaceCreateDeviceGray(),
        colorComponents: [1, 0.24, 1, 0],
        locations: [0, 1],
        count: 2
    )!

    static func draw(in context: CGContext, center: CGPoint, radius: CGFloat, alpha: CGFloat = 1) {
        context.saveGState()
        context.setAlpha(alpha)
        context.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                                   endCenter: center, endRadius: radius, options: [])
        context.restoreGState()
    }
}

class PieChartRenderer: BaseChartRenderer {
    struct PieComponent: Hashable {
        var color: GColor
        var value: CGFloat
    }

    override func setup(verticalRange: ClosedRange<CGFloat>, animated: Bool, timeFunction: TimeFunction? = nil) {
        super.setup(verticalRange: 0...1, animated: animated, timeFunction: timeFunction)
    }
    
    var valuesFormatter: NumberFormatter = NumberFormatter()
    var drawValues: Bool = true

    private var componentsAnimators: [AnimationController<CGFloat>] = []
    private lazy var transitionAnimator: AnimationController<CGFloat> = { AnimationController<CGFloat>(current: 1, refreshClosure: self.refreshClosure) }()
    private var oldPercentageData: [PieComponent] = []
    private var percentageData: [PieComponent] = []
    private var setlectedSegmentsAnimators: [AnimationController<CGFloat>] = []

    var drawPie: Bool = true
    var drawsDonut = false
    var initialAngle: CGFloat = .pi / 3
    var hasSelectedSegments: Bool {
        return selectedSegment != nil
    }
    private(set) var selectedSegment: Int?
    func selectSegmentAt(at indexToSelect: Int?, animated: Bool) {
        guard selectedSegment != indexToSelect else {
            return
        }
        selectedSegment = indexToSelect
        for (index, animator) in setlectedSegmentsAnimators.enumerated() {
            let fraction: CGFloat = (index == indexToSelect) ? 1.0 : 0.0
            if animated {
                animator.animate(to: fraction, duration: .defaultDuration / 2)
            } else {
                animator.set(current: fraction)
            }
        }
    }
    
    func updatePercentageData(_ percentageData: [PieComponent], animated: Bool) {
        if self.percentageData.count != percentageData.count {
            componentsAnimators = percentageData.map { _ in AnimationController<CGFloat>(current: 1, refreshClosure: self.refreshClosure) }
            setlectedSegmentsAnimators = percentageData.map { _ in AnimationController<CGFloat>(current: 0, refreshClosure: self.refreshClosure) }
        }
        if animated {
            self.oldPercentageData = self.currentTransitionAnimationData
            self.percentageData = percentageData
            transitionAnimator.completionClosure = { [weak self] in
                self?.oldPercentageData = []
            }
            transitionAnimator.set(current: 0)
            transitionAnimator.animate(to: 1, duration: .defaultDuration)
        } else {
            self.oldPercentageData = []
            self.percentageData = percentageData
            transitionAnimator.set(current: 0)
        }
    }
    
    func setComponentVisible(_ isVisible: Bool, at index: Int, animated: Bool) {
        componentsAnimators[index].animate(to: isVisible ? 1 : 0, duration: animated ? .defaultDuration : 0)
    }
    
    var lastRenderedBounds: CGRect = .zero
    var lastRenderedChartFrame: CGRect = .zero
    func selectedItemIndex(at point: CGPoint) -> Int? {
        let touchPosition = lastRenderedChartFrame.origin + point * lastRenderedChartFrame.size
        let geometry = PieChartGeometry(chartFrame: lastRenderedChartFrame, drawsDonut: drawsDonut)
        let currentData = currentlyVisibleData
        let total: CGFloat = currentData.map({ $0.value }).reduce(0, +)
        guard total > 0, geometry.radius > 0 else { return nil }
        let numberOfVisibleItems = currentData.filter { $0.value > 0 }.count
        var startAngle: CGFloat = initialAngle
        for (index, piece) in currentData.enumerated() {
            let percent = piece.value / total
            guard percent > 0 else { continue }
            let segmentSize = 2 * .pi * percent
            let endAngle = startAngle + segmentSize
            let centerAngle = (startAngle + endAngle) / 2
            let offset = numberOfVisibleItems > 1 ? setlectedSegmentsAnimators[index].current * geometry.selectionOffset : 0
            let center = geometry.center + CGPoint(x: cos(centerAngle) * offset, y: sin(centerAngle) * offset)
            let distance = center.distanceTo(touchPosition)
            let angle = (center - touchPosition).angle + .pi
            if distance >= geometry.innerRadius, distance <= geometry.radius,
               (angle >= startAngle && angle <= endAngle ||
                angle + .pi * 2 >= startAngle && angle + .pi * 2 <= endAngle) {
                return index
            }
            startAngle = endAngle
        }
        return nil
    }
    
    private var currentTransitionAnimationData: [PieComponent] {
        if transitionAnimator.isAnimating {
            let animationFraction = transitionAnimator.current
            return percentageData.enumerated().map { arg in
                return PieComponent(color: arg.element.color,
                                    value: oldPercentageData[arg.offset].value * (1 - animationFraction) + arg.element.value * animationFraction)
            }
        } else {
            return percentageData
        }
    }
    
    var currentlyVisibleData: [PieComponent] {
        return currentTransitionAnimationData.enumerated().map { arg in
            return PieComponent(color: arg.element.color,
                                value: arg.element.value * componentsAnimators[arg.offset].current)
        }
    }
    
    override func render(context: CGContext, bounds: CGRect, chartFrame: CGRect) {
        guard isEnabled && verticalRange.current.distance > 0 && verticalRange.current.distance > 0 else { return }
        lastRenderedBounds = bounds
        lastRenderedChartFrame = chartFrame
        let chartAlpha = chartAlphaAnimator.current
        if chartAlpha == 0 { return }

        let geometry = PieChartGeometry(chartFrame: chartFrame, drawsDonut: drawsDonut)
        let center = geometry.center

        let currentData = currentlyVisibleData

        let total: CGFloat  = currentData.map({ $0.value }).reduce(0, +)
        guard total > 0 else {
            return
        }

        let animationSelectionOffset = geometry.selectionOffset
        let maximumFontSize: CGFloat = drawsDonut ? 17 * geometry.radius / 110 : geometry.radius * 15 / 14 / 7
        let minimumFontSize: CGFloat = 4
        let centerOffsetStartAngle = CGFloat.pi / 4
        let minimumValueToDraw: CGFloat = 0.015
        let diagramRadius = geometry.radius

        let numberOfVisibleItems = currentlyVisibleData.filter { $0.value > 0 }.count
        var startAngle: CGFloat = initialAngle
        for (index, piece) in currentData.enumerated() {
            let percent = piece.value / total
            guard percent > 0 else { continue }
            let segmentSize = 2 * .pi * percent * chartAlpha
            let endAngle = startAngle + segmentSize
            let centerAngle = (startAngle + endAngle) / 2
            let labelVector = CGPoint(x: cos(centerAngle),
                                      y: sin(centerAngle))

            let selectionAnimationFraction = (numberOfVisibleItems > 1 ? setlectedSegmentsAnimators[index].current : 0)

            let updatedCenter = CGPoint(x: center.x + labelVector.x * selectionAnimationFraction * animationSelectionOffset,
                                        y: center.y + labelVector.y * selectionAnimationFraction * animationSelectionOffset)
            if drawPie {
                context.saveGState()
                context.setFillColor(piece.color.withAlphaComponent(piece.color.alphaValue * chartAlpha).cgColor)
                context.move(to: updatedCenter + CGPoint(x: cos(startAngle) * diagramRadius, y: sin(startAngle) * diagramRadius))
                context.addArc(center: updatedCenter,
                               radius: diagramRadius,
                               startAngle: startAngle,
                               endAngle: endAngle,
                               clockwise: false)
                if geometry.innerRadius > 0 {
                    context.addArc(center: updatedCenter,
                                   radius: geometry.innerRadius,
                                   startAngle: endAngle,
                                   endAngle: startAngle,
                                   clockwise: true)
                } else {
                    context.addLine(to: updatedCenter)
                }
                context.closePath()
                let slicePath = context.path
                context.fillPath()
                if drawsDonut, let slicePath {
                    context.addPath(slicePath)
                    context.clip()
                    DonutChartHighlight.draw(in: context, center: updatedCenter, radius: diagramRadius,
                                             alpha: piece.color.alphaValue * chartAlpha)
                }
                context.restoreGState()
            }

            if drawValues && percent >= minimumValueToDraw {
                context.saveGState()

                let text = valuesFormatter.string(from: percent * 100)
                let fraction = crop(0, segmentSize / centerOffsetStartAngle, 1)
                let fontSize = (minimumFontSize + (maximumFontSize - minimumFontSize) * fraction).rounded(.up)
                let labelPositionOffset = drawsDonut
                    ? diagramRadius * (0.75 + 0.1 * (1 - fraction))
                    : diagramRadius / 2 + diagramRadius / 2 * (1 - fraction)
                let font = GraphTypography.technicalPieValueFont(pointSize: fontSize)
                let labelsEaseInColor = crop(0, chartAlpha * chartAlpha * 2 - 1, 1)
                let attributes: [NSAttributedString.Key: Any] = [.foregroundColor: GColor.white.withAlphaComponent(labelsEaseInColor),
                                                                 .font: font]
                
                let attributedString = NSAttributedString(string: text, attributes: attributes)
                let textNode = TextRenderer.layoutText(attributedString, bounds.size)
                
                let labelPoint = CGPoint(x: labelVector.x * labelPositionOffset + updatedCenter.x - textNode.0.size.width / 2,
                                         y: labelVector.y * labelPositionOffset + updatedCenter.y - textNode.0.size.height / 2)
                textNode.1.draw(CGRect(origin: labelPoint, size: textNode.0.size), in: context, backingScaleFactor: deviceScale)
                context.restoreGState()
            }

            startAngle = endAngle
        }
    }
}
