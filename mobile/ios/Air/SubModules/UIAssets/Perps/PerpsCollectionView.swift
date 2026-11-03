import UIActivityList
import UIKit
import WalletContext

@MainActor
final class PerpsCollectionView: UICollectionView, UICollectionViewDelegate {
    typealias Provider = ActivityListViewController.CustomSectionDataProvider
    private struct Row: Hashable { let section: String; let item: String }
    var onNearBottom: (() -> Void)?
    private var sections: [any Provider] = []
    private var source: UICollectionViewDiffableDataSource<String, Row>!

    init() {
        super.init(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        backgroundColor = .clear
        delaysContentTouches = false
        alwaysBounceVertical = true
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        delegate = self
        collectionViewLayout = UICollectionViewCompositionalLayout { [weak self] index, environment in
            guard let self, sections.indices.contains(index) else { return nil }
            return sections[index].makeLayoutSection(layoutEnvironment: environment)
        }
        source = UICollectionViewDiffableDataSource<String, Row>(collectionView: self) { [weak self] collection, index, row in
            self?.sections.first { $0.id == row.section }?.dequeueCell(collection, index, itemIdentifier: row.item)
        }
        source.supplementaryViewProvider = { [weak self] collection, kind, index in
            guard let self, sections.indices.contains(index.section) else { return nil }
            return sections[index.section].dequeueSupplementaryView(collection, kind: kind, indexPath: index)
        }
    }
    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    func update(sections: [any Provider], animatingDifferences: Bool = false) {
        self.sections = sections
        var snapshot = NSDiffableDataSourceSnapshot<String, Row>()
        for section in sections {
            section.prepareForUse()
            snapshot.appendSections([section.id])
            snapshot.appendItems(section.itemIdentifiers.map { Row(section: section.id, item: $0) }, toSection: section.id)
        }
        let oldItems = Set(source.snapshot().itemIdentifiers)
        snapshot.reconfigureItems(snapshot.itemIdentifiers.filter { oldItems.contains($0) })
        source.apply(snapshot, animatingDifferences: animatingDifferences)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView.contentOffset.y + scrollView.bounds.height > scrollView.contentSize.height - 300 {
            onNearBottom?()
        }
    }

    private func provider(at index: IndexPath) -> (any Provider, String)? {
        guard let row = source.itemIdentifier(for: index), let section = sections.first(where: { $0.id == row.section }) else { return nil }
        return (section, row.item)
    }
    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        guard let (section, item) = provider(at: indexPath) else { return false }
        return section.shouldSelect(itemIdentifier: item)
    }
    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        self.collectionView(collectionView, shouldSelectItemAt: indexPath)
    }
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let (section, item) = provider(at: indexPath) else { return }
        section.didSelect(itemIdentifier: item)
    }
}

@MainActor
final class PerpsContentSection: ActivityListViewController.CustomSectionDataProvider {
    let id: String
    var itemIdentifiers: [String] { [id] }
    private let height: CGFloat?
    private let inset: CGFloat
    private let bottomSpacing: CGFloat
    private let onSelect: (() -> Void)?
    private let cell: (UICollectionView, IndexPath) -> UICollectionViewCell

    init(id: String, height: CGFloat? = nil, inset: CGFloat = 0, bottomSpacing: CGFloat = 0,
         onSelect: (() -> Void)? = nil, cell: @escaping (UICollectionView, IndexPath) -> UICollectionViewCell) {
        self.id = id; self.height = height; self.inset = inset; self.bottomSpacing = bottomSpacing
        self.onSelect = onSelect; self.cell = cell
    }
    func makeLayoutSection(layoutEnvironment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection? {
        let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: height.map { .absolute($0) } ?? .estimated(300))
        let group = NSCollectionLayoutGroup.vertical(layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)])
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = .init(top: 0, leading: inset, bottom: bottomSpacing, trailing: inset)
        return section
    }
    func dequeueCell(_ collectionView: UICollectionView, _ indexPath: IndexPath, itemIdentifier: String) -> UICollectionViewCell { cell(collectionView, indexPath) }
    func shouldSelect(itemIdentifier: String) -> Bool { onSelect != nil }
    func didSelect(itemIdentifier: String) { onSelect?() }
}
