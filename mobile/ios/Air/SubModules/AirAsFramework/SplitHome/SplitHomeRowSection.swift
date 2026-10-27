import UIKit
import UIActivityList

@MainActor
protocol SplitHomeRowContent: AnyObject {
    func setHorizontalInsets(_ insets: UIEdgeInsets)
}

@MainActor
final class SplitHomeRowSection<Cell: UICollectionViewCell & SplitHomeRowContent>: ActivityListViewController.CustomSectionDataProvider {
    let id: String
    var itemIdentifiers: [String] { [id] }

    private let registration: UICollectionView.CellRegistration<Cell, String>
    private var horizontalInsets: UIEdgeInsets = .zero
    private weak var cell: Cell?

    init(id: String, configure: @escaping (Cell) -> Void) {
        self.id = id
        registration = UICollectionView.CellRegistration<Cell, String> { cell, _, _ in
            configure(cell)
        }
    }

    func makeLayoutSection(layoutEnvironment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection? {
        let listSection = NSCollectionLayoutSection.list(
            using: UICollectionLayoutListConfiguration(appearance: .insetGrouped),
            layoutEnvironment: layoutEnvironment
        )
        // UIKit's inset-grouped section already includes the container's safe-area insets.
        let leading = listSection.contentInsets.leading
        let trailing = listSection.contentInsets.trailing
        let isRTL = layoutEnvironment.traitCollection.layoutDirection == .rightToLeft
        horizontalInsets = UIEdgeInsets(top: 0, left: isRTL ? trailing : leading, bottom: 0, right: isRTL ? leading : trailing)
        cell?.setHorizontalInsets(horizontalInsets)

        let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(300))
        let item = NSCollectionLayoutItem(layoutSize: size)
        let section = NSCollectionLayoutSection(group: .vertical(layoutSize: size, subitems: [item]))
        // Cell reuse must follow the visible pane edges, not the inset-grouped margins.
        section.contentInsetsReference = .none
        section.contentInsets.bottom = 16
        return section
    }

    func dequeueCell(_ collectionView: UICollectionView, _ indexPath: IndexPath, itemIdentifier: String) -> UICollectionViewCell {
        let cell = collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: itemIdentifier)
        cell.setHorizontalInsets(horizontalInsets)
        self.cell = cell
        return cell
    }
}

extension UICollectionView {
    func setSplitHomeHorizontalInsets(_ insets: UIEdgeInsets) {
        guard contentInset != insets else { return }
        let insetDelta = effectiveUserInterfaceLayoutDirection == .rightToLeft
            ? insets.right - contentInset.right
            : contentInset.left - insets.left
        let offset = contentOffset.x + insetDelta
        contentInset = insets
        contentOffset.x = offset
    }
}
