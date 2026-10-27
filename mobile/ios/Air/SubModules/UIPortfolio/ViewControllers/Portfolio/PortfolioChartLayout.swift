import UIKit

@MainActor
enum PortfolioChartLayout {
    // Match the design's 388-point panels and 16-point gutter, after the section insets.
    static let minimumColumnWidth: CGFloat = 388
    static let columnSpacing: CGFloat = 16

    static func makeSection(availableWidth: CGFloat) -> NSCollectionLayoutSection {
        let columnCount = availableWidth >= minimumColumnWidth * 2 + columnSpacing ? 2 : 1
        let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(535))
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1 / CGFloat(columnCount)),
            heightDimension: .estimated(535)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: size, repeatingSubitem: item, count: columnCount)
        group.interItemSpacing = .fixed(columnSpacing)
        return NSCollectionLayoutSection(group: group)
    }
}
