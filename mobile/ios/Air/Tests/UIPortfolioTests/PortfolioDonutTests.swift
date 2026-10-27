import Testing
import UIKit
@testable import GraphKit

@Suite("Portfolio donut rendering")
@MainActor
struct PortfolioDonutTests {
    @Test(arguments: [false, true])
    func radialHighlightFadesTowardTheRimAndFollowsSelection(selected: Bool) throws {
        let renderer = PieChartRenderer()
        renderer.drawsDonut = true
        renderer.drawValues = false
        renderer.initialAngle = 0
        renderer.updatePercentageData([
            .init(color: .red, value: 75), .init(color: .blue, value: 25),
        ], animated: false)
        if selected { renderer.selectSegmentAt(at: 0, animated: false) }
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 300)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(bounds: bounds, format: format).image {
            renderer.render(context: $0.cgContext, bounds: bounds, chartFrame: bounds)
        }
        let cgImage = try #require(image.cgImage)
        let data = try #require(cgImage.dataProvider?.data)
        let bytes = try #require(CFDataGetBytePtr(data))
        let offset = selected ? 110 / 14 / sqrt(CGFloat(2)) : 0
        let center = CGPoint(x: 150 - offset, y: 150 + offset)
        for distance in [CGFloat(60), 100] {
            let pixel = Int(center.y + distance) * cgImage.bytesPerRow + Int(center.x) * 4
            // Red's green/blue channels directly measure the white overlay's opacity.
            let highlight = min(bytes[pixel], bytes[pixel + 1], bytes[pixel + 2])
            let expected = 255 * 0.24 * (1 - distance / 110)
            #expect(abs(CGFloat(highlight) - expected) <= 2)
            #expect(bytes[pixel + 3] == 255)
        }
        let centerPixel = Int(center.y) * cgImage.bytesPerRow + Int(center.x) * 4
        #expect(bytes[centerPixel + 3] == 0)
    }

    @Test(arguments: [false, true])
    func centerIsEmptyAndRingRemainsSelectable(selected: Bool) throws {
        let renderer = PieChartRenderer()
        renderer.drawsDonut = true
        renderer.drawValues = false
        renderer.initialAngle = 0
        renderer.updatePercentageData([
            .init(color: .red, value: 75), .init(color: .blue, value: 25),
        ], animated: false)
        if selected { renderer.selectSegmentAt(at: 0, animated: false) }
        let bounds = CGRect(x: 0, y: 0, width: 356, height: 273)
        let image = UIGraphicsImageRenderer(bounds: bounds).image {
            UIColor.white.setFill()
            $0.fill(bounds)
            renderer.render(context: $0.cgContext, bounds: bounds, chartFrame: bounds)
        }
        #expect(renderer.selectedItemIndex(at: CGPoint(x: 0.5, y: 0.5)) == nil)
        #expect(renderer.selectedItemIndex(at: CGPoint(x: 0.6, y: 0.5)) == nil)
        #expect(renderer.selectedItemIndex(at: CGPoint(x: 0.5, y: 0.8)) == 0)
        #expect(renderer.selectedItemIndex(at: CGPoint(x: 0.72, y: 0.3)) == 1)
        #expect(renderer.selectedItemIndex(at: CGPoint(x: 0.82, y: 0.5)) == nil)
        #expect(renderer.selectedItemIndex(at: CGPoint(x: 0.99, y: 0.5)) == nil)
        let cgImage = try #require(image.cgImage)
        let data = try #require(cgImage.dataProvider?.data)
        let bytes = try #require(CFDataGetBytePtr(data))
        let offset = cgImage.height / 2 * cgImage.bytesPerRow + cgImage.width / 2 * 4
        #expect(bytes[offset] == 255 && bytes[offset + 1] == 255 && bytes[offset + 2] == 255)
        let ringOffset = Int(Double(cgImage.height) * 0.8) * cgImage.bytesPerRow + cgImage.width / 2 * 4
        #expect(bytes[ringOffset] < 255 || bytes[ringOffset + 1] < 255 || bytes[ringOffset + 2] < 255)
    }

    @Test
    func emptyAndHiddenSlicesCannotBeSelected() {
        let renderer = PieChartRenderer()
        renderer.drawsDonut = true
        renderer.initialAngle = 0
        renderer.lastRenderedChartFrame = CGRect(x: 0, y: 0, width: 220, height: 220)
        renderer.updatePercentageData([.init(color: .red, value: 0), .init(color: .blue, value: 100)], animated: false)
        #expect(renderer.selectedItemIndex(at: CGPoint(x: 0.85, y: 0.5)) == 1)
        renderer.setComponentVisible(false, at: 1, animated: false)
        #expect(renderer.selectedItemIndex(at: CGPoint(x: 0.85, y: 0.5)) == nil)
    }

    @Test(arguments: [false, true])
    func chartContainerRendersTheDonutWithLabelsInBothThemes(dark: Bool) throws {
        let values: [Double] = [65, 10, 8, 4, 3, 3, 3, 2, 2]
        let colors: [UIColor] = [.systemGreen, .cyan, .systemYellow, .systemRed, .systemBlue, .systemOrange, .systemMint, .systemPurple, .systemPink]
        let controller = PercentPieChartController(chartsCollection: ChartsCollection(
            axisValues: [Date(timeIntervalSince1970: 1_778_025_600), Date(timeIntervalSince1970: 1_778_112_000)],
            chartValues: values.enumerated().map {
                ChartsCollection.Chart(color: colors[$0.offset], name: "Asset \($0.offset)", values: [$0.element, $0.element])
            }
        ))
        controller.drawsDonut = true
        let view = ChartContainerView(frame: CGRect(x: 0, y: 0, width: 388, height: 460))
        view.overrideUserInterfaceStyle = dark ? .dark : .light
        view.backgroundColor = dark ? .black : .white
        view.apply(theme: .extractedTheme(for: dark ? .dark : .light), animated: false)
        view.setup(controller: controller, noInitialZoom: true)
        view.setPieVisible(true, animated: false)
        view.frame.size.height = view.preferredHeight(for: view.bounds.width)
        view.layoutIfNeeded()
        display(view)
        let image = UIGraphicsImageRenderer(bounds: view.bounds).image { view.layer.render(in: $0.cgContext) }
        Attachment.record(Array(try #require(image.pngData())), named: "portfolio-donut-\(dark ? "dark" : "light").png")
    }

    private func display(_ view: UIView) {
        view.layoutIfNeeded()
        view.layer.displayIfNeeded()
        view.subviews.forEach(display)
    }
}
