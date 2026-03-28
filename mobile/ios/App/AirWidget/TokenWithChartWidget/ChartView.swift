import SwiftUI
import WidgetKit

struct ChartView: View {
    var token: ApiToken
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
                    Text(localized("No Data"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.76))
                )
        } else {
            GeometryReader { geometry in
                let scaledPoints = scaledPoints(in: geometry.size)
                ZStack {
                    areaPath(for: scaledPoints, size: geometry.size)
                        .fill(areaGradient)
                    linePath(for: scaledPoints)
                        .stroke(
                            isVivid ? Color.white : tintColor,
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                        )
                }
            }
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
    
    private func scaledPoints(in size: CGSize) -> [CGPoint] {
        guard let firstDate = points.first?.date, let lastDate = points.last?.date else {
            return []
        }

        let dateRange = max(lastDate.timeIntervalSince(firstDate), 1)
        let yRange = yScaleRange.upperBound - yScaleRange.lowerBound

        return points.map { point in
            let xProgress = point.date.timeIntervalSince(firstDate) / dateRange
            let yProgress = yRange == 0 ? 0.5 : (point.value - yScaleRange.lowerBound) / yRange

            return CGPoint(
                x: size.width * xProgress,
                y: size.height * (1 - yProgress)
            )
        }
    }

    private func linePath(for scaledPoints: [CGPoint]) -> Path {
        Path { path in
            guard let firstPoint = scaledPoints.first else { return }
            path.move(to: firstPoint)
            for point in scaledPoints.dropFirst() {
                path.addLine(to: point)
            }
        }
    }

    private func areaPath(for scaledPoints: [CGPoint], size: CGSize) -> Path {
        Path { path in
            guard let firstPoint = scaledPoints.first, let lastPoint = scaledPoints.last else { return }
            path.move(to: CGPoint(x: firstPoint.x, y: size.height))
            path.addLine(to: firstPoint)
            for point in scaledPoints.dropFirst() {
                path.addLine(to: point)
            }
            path.addLine(to: CGPoint(x: lastPoint.x, y: size.height))
            path.closeSubpath()
        }
    }

    private var areaGradient: LinearGradient {
        if isVivid {
            LinearGradient(
                colors: [
                    Color.white.opacity(0.35),
                    Color.white.opacity(0.01),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            LinearGradient(
                colors: [
                    tintColor.opacity(0.20),
                    tintColor.opacity(0.01),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var tintColor: Color {
        colorForSlug(token.slug, tokenColor: token.color)
    }
}
