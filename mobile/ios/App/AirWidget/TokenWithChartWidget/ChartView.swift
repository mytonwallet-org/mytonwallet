//
//  ChartView.swift
//  App
//
//  Created by nikstar on 23.09.2025.
//

import SwiftUI
import WalletCore
import WalletContext
import UIComponents
import WidgetKit
import UIKit
import Charts

struct ChartView: View {
    
    var token: ApiToken
    // Date (unix timestamp) and value
    var chartData: [(Double, Double)]
    var chartStyle: ChartStyle
    
    @Environment(\.widgetFamily) private var family
    
    var isSmall: Bool { family == .systemSmall }
    var isMedium: Bool { family == .systemMedium }
    var isRectangularAccessory: Bool { family == .accessoryRectangular }
    var isVivid: Bool { chartStyle == .vivid }

    var body: some View {
        if points.isEmpty {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.06))
                .overlay(
                    Text(LocalizedStringResource("No Data", bundle: LocalizationSupport.shared.bundle))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.76))
                )
        } else {
            let minY = points.min(by: { $0.value < $1.value })!.value // points is not empty
            Chart(points) { point in
                
                AreaMark(
                    x: .value("Time", point.date),
                    yStart: .value("Price", point.value),
                    yEnd: .value("PriceBaseline", minY * 0.98),
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(foregroundStyle)

                LineMark(
                    x: .value("Time", point.date),
                    y: .value("Price", point.value)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(isVivid ? .white : tintColor)
                .lineStyle(.init(lineWidth: 2, lineCap: .round, lineJoin: .round))

            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .chartYScale(domain: yScaleRange)
        }
    }

    private var points: [Point] {
        guard chartData.count > 1 else { return [] }
        return chartData.enumerated().map { index, sample in
            Point(id: index, date: Date(timeIntervalSince1970: sample.0), value: sample.1)
        }
    }

    private struct Point: Identifiable {
        let id: Int
        let date: Date
        let value: Double
    }
    
    private var yScaleRange: ClosedRange<Double> {
        let values = points.map { $0.value }
        guard let minValue = values.min(), let maxValue = values.max() else {
            return 0...1
        }

        if abs(maxValue - minValue) < .ulpOfOne {
            let delta = max(abs(maxValue) * 0.05, 0.01)
            return (minValue - delta)...(maxValue + delta)
        }
        
        let full: CGFloat = 164
        let top: CGFloat = isRectangularAccessory ? 76 : 48
        let bottom: CGFloat = isRectangularAccessory ? 12 : isMedium ? 58 : 68
        let center = full - top - bottom
        
        let topPadding = (maxValue - minValue) * (top/center)
        let bottomPadding = (maxValue - minValue) * (bottom/center)
        return (minValue - bottomPadding)...(maxValue + topPadding)
    }
    
    var foregroundStyle: some ShapeStyle {
        if isVivid {
            AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.35),
                        Color.white.opacity(0.01),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .blendMode(.plusLighter)
            )
        } else {
            AnyShapeStyle(
                LinearGradient(
                    colors: [
                        tintColor.opacity(0.20),
                        tintColor.opacity(0.01),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .blendMode(.hardLight)
            )
        }
    }

    var tintColor: Color {
        colorForSlug(token.slug, tokenColor: token.color)
    }
}
