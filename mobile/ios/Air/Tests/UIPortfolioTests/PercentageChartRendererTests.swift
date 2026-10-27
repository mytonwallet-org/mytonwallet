import CoreGraphics
import Testing
import UIKit
@testable import GraphKit

@Suite("Percentage chart rendering")
@MainActor
struct PercentageChartRendererTests {
    enum Surface: CaseIterable {
        case main, minimap

        var size: CGSize {
            CGSize(width: 320, height: self == .main ? 180 : 40)
        }
    }

    @Test(arguments: Surface.allCases)
    func leadingZerosJumpDirectlyToFullShare(surface: Surface) throws {
        // Exercise a single dataset, the first visible dataset, and the last visible dataset.
        let configurations: [([[Double]], [Bool])] = [
            ([[0, 0, 10, 10, 10, 10]], [true]),
            ([[0, 0, 10, 10, 10, 10], [20, 20, 20, 20, 20, 20]], [true, false]),
            ([[20, 20, 20, 20, 20, 20], [0, 0, 10, 10, 10, 10]], [false, true]),
        ]
        for (values, visibility) in configurations {
            let controller = makeController(values: values, visibility: visibility)
            let bitmap = try render(controller, surface: surface)
            for y in [0.1, 0.5, 0.9] {
                #expect(bitmap.pixel(x: 0.2, y: y) == .white)
                #expect(bitmap.pixel(x: 0.39, y: y) == .white)
                #expect(bitmap.pixel(x: 0.41, y: y) == (visibility[0] ? .red : .blue))
                #expect(bitmap.pixel(x: 0.9, y: y) == (visibility[0] ? .red : .blue))
            }
        }
    }

    @Test(arguments: Surface.allCases)
    func zeroTotalRangesStayEmpty(surface: Surface) throws {
        for (values, visibility) in [
            ([[0.0, 0, 0, 0, 0, 0]], [true]),
            ([[0.0, 0, 0, 0, 0, 0], [20, 20, 20, 20, 20, 20]], [true, false]),
            ([[20.0, 20, 20, 20, 20, 20], [0, 0, 0, 0, 0, 0]], [false, true]),
        ] {
            let bitmap = try render(makeController(values: values, visibility: visibility), surface: surface)
            for x in [0.1, 0.5, 0.9] {
                #expect(bitmap.pixel(x: x, y: 0.1) == .white)
                #expect(bitmap.pixel(x: x, y: 0.9) == .white)
            }
        }
    }

    @Test(arguments: Surface.allCases)
    func internalAndTrailingZerosBreakTheFill(surface: Surface) throws {
        let controller = makeController(values: [[10, 0, 0, 10, 10, 0]], visibility: [true])
        let bitmap = try render(controller, surface: surface)
        for y in [0.1, 0.9] {
            #expect(bitmap.pixel(x: 0.19, y: y) == .red)
            #expect(bitmap.pixel(x: 0.21, y: y) == .white)
            #expect(bitmap.pixel(x: 0.59, y: y) == .white)
            #expect(bitmap.pixel(x: 0.61, y: y) == .red)
        }

        let trailing = try render(makeController(values: [[10, 10, 0, 0, 0, 0]], visibility: [true]), surface: surface)
        #expect(trailing.pixel(x: 0.39, y: 0.1) == .red)
        #expect(trailing.pixel(x: 0.41, y: 0.9) == .white)
        #expect(trailing.pixel(x: 0.9, y: 0.9) == .white)
    }

    @Test(arguments: Surface.allCases)
    func multipleAssetsKeepTheirSharesAndDoNotBackfillZeros(surface: Surface) throws {
        let controller = makeController(values: [[0, 0, 10, 10, 10, 10], [0, 0, 0, 10, 30, 30]], visibility: [true, true])
        let bitmap = try render(controller, surface: surface)
        #expect(bitmap.pixel(x: 0.2, y: 0.1) == .white)
        #expect(bitmap.pixel(x: 0.2, y: 0.9) == .white)
        #expect(bitmap.pixel(x: 0.41, y: 0.1) == .red)
        #expect(bitmap.pixel(x: 0.5, y: 0.1) == .blue)
        #expect(bitmap.pixel(x: 0.5, y: 0.5) == .red)
        #expect(bitmap.pixel(x: 0.9, y: 0.5) == .blue)
        #expect(bitmap.pixel(x: 0.9, y: 0.9) == .red)
    }

    @Test(arguments: Surface.allCases)
    func hidingAndRestoringAssetsRecomputesEmptyPeriods(surface: Surface) throws {
        let controller = makeController(values: [[0, 0, 10, 10, 10, 10], [20, 20, 20, 20, 20, 20]], visibility: [true, true])
        #expect(try render(controller, surface: surface).pixel(x: 0.2, y: 0.5) == .blue)

        controller.updateChartsVisibility(visibility: [true, false], animated: false)
        #expect(try render(controller, surface: surface).pixel(x: 0.2, y: 0.5) == .white)
        #expect(try render(controller, surface: surface).pixel(x: 0.5, y: 0.1) == .red)

        controller.updateChartsVisibility(visibility: [true, true], animated: false)
        #expect(try render(controller, surface: surface).pixel(x: 0.2, y: 0.5) == .blue)
    }

    @Test(arguments: Surface.allCases)
    func croppedRangeInsideAGapRemainsEmptyUntilTheNextPositiveSample(surface: Surface) throws {
        let controller = makeController(values: [[10, 0, 0, 10, 10, 10]], visibility: [true])
        let bitmap = try render(controller, surface: surface, range: 1.5...3.5)
        #expect(bitmap.pixel(x: 0.5, y: 0.9) == .white)
        #expect(bitmap.pixel(x: 0.74, y: 0.9) == .white)
        #expect(bitmap.pixel(x: 0.76, y: 0.1) == .red)
    }

    @Test(arguments: [true, false])
    func pieTransitionMatchesPercentageChartAtTheChartEnd(fromDataToPie: Bool) throws {
        let configurations: [([[Double]], [Bool])] = [
            ([[0, 0, 10, 10, 10, 10]], [true]),
            ([[0, 0, 10, 10, 10, 10], [20, 20, 20, 20, 20, 20]], [true, false]),
            ([[20, 20, 20, 20, 20, 20], [0, 0, 10, 10, 10, 10]], [false, true]),
            ([[0, 0, 10, 10, 10, 10], [0, 0, 0, 10, 30, 30]], [true, true]),
            ([[10, 0, 0, 10, 10, 0], [10, 0, 0, 30, 30, 0]], [true, true]),
            ([[10, 10, 0, 0, 0, 0]], [true]),
        ]
        for (values, visibility) in configurations {
            let controller = makeController(values: values, visibility: visibility)
            let expected = try render(controller, surface: .main)
            let actual = try renderTransition(controller, fromDataToPie: fromDataToPie, progress: fromDataToPie ? 0 : 1)
            for x in [0.1, 0.3, 0.5, 0.7, 0.9] {
                for y in [0.1, 0.5, 0.9] {
                    #expect(actual.pixel(x: x, y: y) == expected.pixel(x: x, y: y))
                }
            }
        }
    }

    @Test(arguments: [true, false])
    func emptyPieTransitionsStayEmpty(fromDataToPie: Bool) throws {
        for values in [[[0.0, 0, 0, 0, 0, 0]], [[0.0, 0, 0, 0, 0, 0], [0, 0, 0, 0, 0, 0]]] {
            let controller = makeController(values: values, visibility: values.map { _ in true })
            for progress in [0.0, 0.25, 0.5, 0.75, 1] {
                let bitmap = try renderTransition(controller, fromDataToPie: fromDataToPie, progress: progress)
                for x in [0.1, 0.5, 0.9] {
                    for y in [0.1, 0.5, 0.9] {
                        #expect(bitmap.pixel(x: x, y: y) == .white)
                    }
                }
            }
        }
    }

    @Test(arguments: [true, false])
    func pieTransitionDoesNotFlashAFillAcrossGaps(fromDataToPie: Bool) throws {
        for values in [[[0.0, 0, 0, 10, 10, 10]], [[0.0, 0, 0, 10, 10, 10], [0, 0, 0, 30, 30, 30]]] {
            let controller = makeController(values: values, visibility: values.map { _ in true })
            for progress in [0.0, 0.25, 0.5, 0.75, 1] {
                let bitmap = try renderTransition(controller, fromDataToPie: fromDataToPie, progress: progress)
                // This point is in the empty chart period and outside the destination pie.
                #expect(bitmap.pixel(x: 0.1, y: 0.5) == .white)
                let pieFraction = fromDataToPie ? progress : 1 - progress
                #expect(bitmap.pixel(x: 0.5, y: 0.6) == (pieFraction == 0 ? .white : pieFraction == 1 ? .red : .other))
            }
        }
    }

    @Test(arguments: [true, false])
    func donutTransitionEndsWithAnEmptyCenter(fromDataToPie: Bool) throws {
        for values in [[[10.0, 10, 10, 10, 10, 10]], [[0.0, 0, 10, 10, 10, 10]]] {
            let controller = makeController(values: values, visibility: [true])
            let bitmap = try renderTransition(controller, fromDataToPie: fromDataToPie, progress: fromDataToPie ? 1 : 0, drawsDonut: true)
            let expected = try Bitmap(size: Surface.main.size)
            let renderer = PieChartRenderer()
            renderer.drawsDonut = true
            renderer.drawValues = false
            renderer.updatePercentageData([.init(color: .red, value: 1)], animated: false)
            renderer.render(context: expected.context, bounds: expected.bounds, chartFrame: expected.chartFrame)
            #expect(bitmap.pixel(x: 0.5, y: 0.5) == .white)
            for x in [0.1, 0.5, 0.67, 0.75] {
                #expect(bitmap.color(x: x, y: 0.5) == expected.color(x: x, y: 0.5))
            }
        }
    }

    private func renderTransition(_ controller: PercentPieChartController, fromDataToPie: Bool, progress: Double, drawsDonut: Bool = false) throws -> Bitmap {
        let renderer = PercentPieAnimationRenderer()
        renderer.drawsDonut = drawsDonut
        renderer.setup(horizontalRange: CGFloat(start)...CGFloat(start + 5 * .day), animated: false)
        renderer.visiblePercentageData = controller.percentController.currentlyVisiblePercentageData
        renderer.visiblePieComponents = renderer.visiblePercentageData.components.map {
            PieChartRenderer.PieComponent(color: $0.color, value: $0.values.reduce(0, +))
        }
        renderer.animate(fromDataToPie: !fromDataToPie, animated: false) {}
        let existingListeners = Set(DisplayLinkService.shared.listners.allObjects.map { ObjectIdentifier($0) })
        renderer.animate(fromDataToPie: fromDataToPie, animated: true) {}
        defer { renderer.animate(fromDataToPie: fromDataToPie, animated: false) {} }
        // Advance only this transition, synchronously, without wall-clock timing in the test.
        for listener in DisplayLinkService.shared.listners.allObjects where !existingListeners.contains(ObjectIdentifier(listener)) {
            (listener as? DisplayLinkListner)?.update(delta: .defaultDuration * progress)
        }
        let bitmap = try Bitmap(size: Surface.main.size)
        renderer.render(context: bitmap.context, bounds: bitmap.bounds, chartFrame: bitmap.chartFrame)
        return bitmap
    }

    private let start: TimeInterval = 1_700_000_000

    private func makeController(values: [[Double]], visibility: [Bool]) -> PercentPieChartController {
        let collection = ChartsCollection(
            axisValues: (0..<6).map { Date(timeIntervalSince1970: start + Double($0) * .day) },
            chartValues: values.enumerated().map { index, values in
                ChartsCollection.Chart(color: index == 0 ? .red : .blue, name: "Asset \(index)", values: values)
            }
        )
        let controller = PercentPieChartController(chartsCollection: collection)
        controller.chartFrame = { CGRect(x: 16, y: 0, width: 288, height: 180) }
        controller.cartViewBounds = { CGRect(x: 0, y: 0, width: 320, height: 180) }
        controller.initializeChart()
        controller.updateChartsVisibility(visibility: visibility, animated: false)
        return controller
    }

    private func render(_ controller: PercentPieChartController, surface: Surface, range: ClosedRange<Double> = 0...5) throws -> Bitmap {
        let renderer = surface == .main
            ? controller.percentController.mainPecentChartRenderer
            : controller.percentController.previewPercentChartRenderer
        renderer.setVisible(true, animated: false)
        renderer.setup(horizontalRange: CGFloat(start + range.lowerBound * .day)...CGFloat(start + range.upperBound * .day), animated: false)
        let bitmap = try Bitmap(size: surface.size)
        renderer.render(context: bitmap.context, bounds: bitmap.bounds, chartFrame: bitmap.chartFrame)
        return bitmap
    }

    private struct Bitmap {
        enum Pixel: Equatable {
            case white, red, blue, other
        }

        let context: CGContext
        let bounds: CGRect
        let chartFrame: CGRect

        init(size: CGSize) throws {
            bounds = CGRect(origin: .zero, size: size)
            chartFrame = bounds.insetBy(dx: 16, dy: 0)
            context = try #require(CGContext(
                data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                bytesPerRow: Int(size.width) * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
            context.setFillColor(UIColor.white.cgColor)
            context.fill(bounds)
            context.clip(to: chartFrame)
        }

        func color(x: Double, y: Double) -> [UInt8] {
            let column = Int(chartFrame.minX + x * chartFrame.width)
            let row = Int(y * chartFrame.height)
            let offset = row * context.bytesPerRow + column * 4
            let data = context.data!.assumingMemoryBound(to: UInt8.self)
            return Array(UnsafeBufferPointer(start: data + offset, count: 4))
        }

        func pixel(x: Double, y: Double) -> Pixel {
            let color = color(x: x, y: y)
            switch (color[0], color[1], color[2]) {
            case (255, 255, 255): return .white
            case (255, 0, 0): return .red
            case (0, 0, 255): return .blue
            default: return .other
            }
        }
    }
}
