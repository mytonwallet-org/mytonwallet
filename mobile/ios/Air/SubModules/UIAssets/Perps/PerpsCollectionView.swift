import UIActivityList
import UIComponents
import UIKit
import WalletContext

@MainActor
final class PerpsCollectionView: UICollectionView, UICollectionViewDelegate {
    typealias Provider = ActivityListViewController.CustomSectionDataProvider
    private struct Row: Hashable { let section: String; let item: String }
    var onNearBottom: (() -> Void)?
    private var sections: [any Provider] = []
    private var source: UICollectionViewDiffableDataSource<String, Row>!
    private lazy var dateRefreshController = ActivityDateRefreshController(collectionView: self)

    init() {
        super.init(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        backgroundColor = .clear
        layoutMargins = .zero
        delaysContentTouches = false
        alwaysBounceVertical = true
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        delegate = self
        let configuration = UICollectionViewCompositionalLayoutConfiguration()
        configuration.contentInsetsReference = .layoutMargins
        collectionViewLayout = UICollectionViewCompositionalLayout(sectionProvider: { [weak self] index, environment in
            guard let self, sections.indices.contains(index) else { return nil }
            return sections[index].makeLayoutSection(layoutEnvironment: environment)
        }, configuration: configuration)
        source = UICollectionViewDiffableDataSource<String, Row>(collectionView: self) { [weak self] collection, index, row in
            self?.sections.first { $0.id == row.section }?.dequeueCell(collection, index, itemIdentifier: row.item)
        }
        source.supplementaryViewProvider = { [weak self] collection, kind, index in
            guard let self, sections.indices.contains(index.section) else { return nil }
            return sections[index.section].dequeueSupplementaryView(collection, kind: kind, indexPath: index)
        }
    }
    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    func updateHorizontalMargins(_ margins: UIEdgeInsets) -> Bool {
        insetsLayoutMarginsFromSafeArea = false
        // Section layouts supply 16-point margins; the collection supplies only the remaining parent margin
        let additionalMargins = UIEdgeInsets(top: 0, left: max(0, margins.left - 16), bottom: 0, right: max(0, margins.right - 16))
        guard layoutMargins != additionalMargins else { return false }
        layoutMargins = additionalMargins
        collectionViewLayout.invalidateLayout()
        return true
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { dateRefreshController.start() }
        else { dateRefreshController.stop() }
    }

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
        source.apply(snapshot, animatingDifferences: animatingDifferences) { [weak self] in
            self?.dateRefreshController.setNeedsUpdate()
        }
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

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        dateRefreshController.setNeedsUpdate()
    }
}
