import Testing
import UIKit
import WalletResources
@testable import GraphKit
@testable import UIPortfolio

@Suite("Portfolio adaptive chart layout")
@MainActor
struct PortfolioChartLayoutTests {
    @Test
    func resizingUsesTwoColumnsOnlyWhenBothPanelsFitTheDesign() throws {
        _ = WalletResourcesBundle.bundle.load()
        let layout = UICollectionViewCompositionalLayout { _, environment in
            let section = PortfolioChartLayout.makeSection(availableWidth: environment.container.effectiveContentSize.width - 32)
            section.contentInsets = .init(top: 24, leading: 16, bottom: 32, trailing: 16)
            section.interGroupSpacing = 24
            return section
        }
        let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 390, height: 1500), collectionViewLayout: layout)
        collection.overrideUserInterfaceStyle = .light
        collection.backgroundColor = .systemGroupedBackground
        PortfolioGraphKitAdapter.configureTypography()
        let presentation = PortfolioGraphKitAdapter.ChartPresentation(
            json: ##"{"columns":[["x",1778025600000,1778112000000],["y0",65,75],["y1",35,25]],"types":{"x":"x","y0":"area","y1":"area"},"names":{"y0":"TON","y1":"USD₮"},"colors":{"y0":"#0088FF","y1":"#00CAFF"},"stacked":true,"percentage":true}"##,
            limitedHistoryFraction: nil, baseCurrency: .USD, valueFormat: .currency
        )
        let kinds: [PortfolioGraphKind] = [.portfolioShare, .totalValue, .totalPnl, .dailyPnl]
        let titles = ["Portfolio Share", "Total Value", "Profit & Loss", "Daily Profit & Loss"]
        let registration = UICollectionView.CellRegistration<PortfolioChartTileCell, Int> { cell, _, item in
            cell.configure(configuration: .init(
                title: titles[item],
                state: .chart(presentation: presentation, kind: kinds[item], pieVisible: item == 0 ? true : nil),
                isRefreshing: false, fadesCurrentData: false, hidesVerticalAxisLabels: false,
                onLimitedHistoryTap: nil, analyzeTitle: "", onAnalyze: nil
            ), onRetry: {})
        }
        let source = UICollectionViewDiffableDataSource<Int, Int>(collectionView: collection) { view, indexPath, item in
            view.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: item)
        }
        defer { withExtendedLifetime(source) {} }
        var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
        snapshot.appendSections([0])
        snapshot.appendItems([0, 1, 2, 3])
        source.apply(snapshot, animatingDifferences: false)

        // Resize the same view in both directions, including fractional widths just below the threshold.
        for width in [CGFloat(320), 375, 390, 768, 820, 823.5, 824, 832, 1024, 1366, 823, 390] {
            collection.frame.size.width = width
            layout.invalidateLayout()
            collection.layoutIfNeeded()
            for listener in DisplayLinkService.shared.listners.allObjects {
                (listener as? DisplayLinkListner)?.update(delta: .defaultDuration + 1)
            }
            collection.visibleCells.forEach { $0.layer.removeAllAnimations() }
            display(collection)
            let frames = try (0..<4).map {
                try #require(layout.layoutAttributesForItem(at: IndexPath(item: $0, section: 0))).frame
            }
            for cell in collection.visibleCells {
                let indexPath = try #require(collection.indexPath(for: cell))
                let expectedWidth = frames[indexPath.item].width
                #expect(abs(cell.bounds.width - expectedWidth) < 0.5)
                #expect(abs(cell.contentView.bounds.width - expectedWidth) < 0.5)
                if let cell = cell as? PortfolioChartTileCell {
                    #expect(abs(cell.tileContentView.bounds.width - expectedWidth) < 0.5)
                    let mainChart = try #require(descendants(of: cell).compactMap { $0 as? ChartView }.first)
                    let plot = mainChart.chartFrame
                    #expect(plot.height <= 235)
                    #expect(abs(plot.height - min(235, plot.width * 235 / 356)) < 0.5)
                    if indexPath.item == 0 {
                        let geometry = PieChartGeometry(chartFrame: plot, drawsDonut: true)
                        #expect(geometry.radius <= 110)
                        #expect(abs(geometry.radius - plot.height * 7 / 15) < 0.5)
                        #expect(geometry.innerRadius == geometry.radius / 2)
                    }
                    let range = try #require(descendants(of: cell).compactMap { $0 as? RangeChartView }.first)
                    #expect(abs(range.frame.minY - mainChart.frame.maxY) < 0.5)
                }
            }
            if width >= 824 {
                #expect(frames[0].minY == frames[1].minY)
                #expect(frames[2].minY == frames[3].minY)
                #expect(frames.allSatisfy { $0.width >= 388 })
                #expect(frames.allSatisfy { abs($0.width - (width - 48) / 2) < 0.5 })
                #expect(frames.allSatisfy { $0.minX >= 16 && $0.maxX <= width - 16 })
                #expect(abs(frames[1].minX - frames[0].maxX - 16) < 0.5)
                #expect(frames[2].minY >= max(frames[0].maxY, frames[1].maxY) + 24)
            } else {
                #expect(frames.allSatisfy { abs($0.width - (width - 32)) < 0.5 })
                #expect(frames[1].minY >= frames[0].maxY + 24)
            }
            if width == 824 || width == 390 || width == 320 || width == 1366 {
                display(collection)
                let image = UIGraphicsImageRenderer(bounds: collection.bounds).image { collection.layer.render(in: $0.cgContext) }
                Attachment.record(Array(try #require(image.pngData())), named: "portfolio-charts-\(Int(width)).png")
            }
        }
    }

    private func descendants(of view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    private func display(_ view: UIView) {
        view.layoutIfNeeded()
        view.layer.displayIfNeeded()
        view.subviews.forEach(display)
    }
}
