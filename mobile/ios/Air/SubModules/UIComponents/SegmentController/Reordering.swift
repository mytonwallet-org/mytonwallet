
import SwiftUI
import UIKit
import WalletContext
import Perception

struct SegmentedControlReordering: View {
    
    let model: SegmentedControlModel
    let scrollContentMargin: CGFloat
    
    var body: some View {
        WithPerceptionTracking {
            if model.isReordering {
                content
            }
        }
    }
    
    @ViewBuilder
    var content: some View {
        WithPerceptionTracking {
            SegmentedControlReorderingVCRepresentable(
                items: model.items,
                selection: model.selection,
                primaryColor: model.primaryColor,
                secondaryColor: model.secondaryColor,
                capsuleColor: model.capsuleColor,
                font: model.font,
                constants: model.constants,
                scrollContentMargin: scrollContentMargin,
                onChange: { model.requestItemsReorder($0) }
            )
        }
        .frame(height: model.constants.fullHeight)
    }
}

// MARK: - SegmentedControlReorderingVC

private final class SegmentedControlReorderingVC: UIViewController {
    private var items: [SegmentedControlItem]
    private var selectedItemID: SegmentedControlItem.ID?
    private var constants: SegmentedControlConstants
    private var scrollContentMargin: CGFloat
    
    // This is a lightweight version of SegmentedControlItem for fast change comparison
    private struct ItemSignature: Hashable {
        let title: String
        let isDeletable: Bool
        
        init(segmentItem: SegmentedControlItem) {
            self.title = segmentItem.title
            self.isDeletable = segmentItem.isDeletable
        }
    }
    private var itemsSignatures: [ItemSignature]  = []
    
    private let primaryColor: UIColor
    private let secondaryColor: UIColor
    private let capsuleColor: UIColor
    private let font: UIFont
    private let onChange:([SegmentedControlItem]) -> Void

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, SegmentedControlItem>!
    private var reorderController: ReorderableCollectionViewController!

    private enum Section: Hashable {
        case main
    }

    init(items: [SegmentedControlItem], selection: SegmentedControlSelection?,
                primaryColor: UIColor, secondaryColor: UIColor, capsuleColor: UIColor,
                font: UIFont, constants: SegmentedControlConstants, scrollContentMargin: CGFloat,
                onChange: @escaping ([SegmentedControlItem]) -> Void) {
        self.items = items
        self.selectedItemID = selection?.effectiveSelectedItemID
        self.itemsSignatures = items.map { .init(segmentItem:$0) }
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor
        self.capsuleColor = capsuleColor
        self.font = font
        self.constants = constants
        self.scrollContentMargin = scrollContentMargin
        self.onChange = onChange
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        let layout = HorizontalCenteringFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumInteritemSpacing = 4
        layout.minimumLineSpacing = constants.spacing
        layout.sectionInset = UIEdgeInsets(top: 0, left: scrollContentMargin, bottom: 0, right:  scrollContentMargin)
        layout.itemSize = .init(width: 100, height: constants.fullHeight)

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.clipsToBounds = false
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.register(_Cell.self, forCellWithReuseIdentifier: _Cell.reuseIdentifier)
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        dataSource = UICollectionViewDiffableDataSource<Section, SegmentedControlItem>(collectionView: collectionView) { [weak self] cv, indexPath, item in
            guard let self else { return nil }
            guard let cell = cv.dequeueReusableCell(withReuseIdentifier: _Cell.reuseIdentifier, for: indexPath) as? _Cell else {
                return UICollectionViewCell()
            }
            
            cell.configure(
                title: item.title,
                textColor: selectedItemID == item.id ? primaryColor : secondaryColor,
                font: font,
                backgroundColor: selectedItemID == item.id ? capsuleColor : .clear,
                deleteButtonColor: capsuleColor,
                isDeletable: item.isDeletable,
                constants: constants
            )
            cell.onDeleteTapped = { [weak self, weak cell] in
                guard let self else { return }
                guard let cell, let indexPath = collectionView.indexPath(for: cell) else { return }
                self.deleteTile(at: indexPath)
            }
            reorderController.updateCell(cell, indexPath: indexPath)
            return cell
        }
        collectionView.dataSource = dataSource

        reorderController = ReorderableCollectionViewController(collectionView: collectionView)
        reorderController.autoScrollEdgeInset = 20
        reorderController.delegate = self
        reorderController.isReordering = true // starts immediately. In fact this is the only mode for the VC

        applySnapshot(animated: false)
    }
    
    func updateFrom(items: [SegmentedControlItem], selection: SegmentedControlSelection?) {
        let itemsSignatures = items.map { ItemSignature(segmentItem:$0) }
        let selectedItemID = selection?.effectiveSelectedItemID
        if itemsSignatures != self.itemsSignatures || selectedItemID != self.selectedItemID {
            self.items = items
            self.selectedItemID = selectedItemID
            self.itemsSignatures = itemsSignatures
            applySnapshot(animated: true)
        }
    }

    private func applySnapshot(animated: Bool) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, SegmentedControlItem>()
        snapshot.appendSections([.main])
        snapshot.appendItems(items, toSection: .main)
        snapshot.reconfigureItems(items)
        dataSource.apply(snapshot, animatingDifferences: animated)
    }

    private func deleteTile(at indexPath: IndexPath) {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        items.removeAll { $0.id == item.id }
        onChange(items)
        applySnapshot(animated: true)
    }
}

extension SegmentedControlReorderingVC: ReorderableCollectionViewControllerDelegate {
    func reorderController(_ controller: ReorderableCollectionViewController, previewForCell cell: UICollectionViewCell) -> ReorderableCollectionViewController.CellPreview? {
        guard let tileCell = cell as? _Cell else { return nil }
        return .init(view: tileCell.mainView)
    }
    
    func reorderController(_ controller: ReorderableCollectionViewController, moveItemAt sourceIndexPath: IndexPath,
                                  to destinationIndexPath: IndexPath) -> Bool {
        let movedItem = items.remove(at: sourceIndexPath.item)
        items.insert(movedItem, at: destinationIndexPath.item)
        onChange(items)
        applySnapshot(animated: true)
        return true
    }

    func reorderController(_ controller: ReorderableCollectionViewController, sizeForItemAt indexPath: IndexPath) -> CGSize? {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return nil }
        let width = _Cell.widthFor(item, font: font, labelGap: constants.labelGap)
        return CGSize(width: width, height: constants.fullHeight)
    }
    
    func reorderController(_ controller: ReorderableCollectionViewController, adjustPreviewFrame previewFrame: CGRect) -> CGRect {
        let insets = UIEdgeInsets(
            top: constants.topInset,
            left: -previewFrame.width,
            bottom: 0,
            right: -previewFrame.width
        )
        let bounds = controller.collectionView.bounds.inset(by: insets)
        return previewFrame.clamped(to: bounds)
    }
}

private final class _Cell: UICollectionViewCell, ReorderableCell {
    static let reuseIdentifier = "_Cell"

    var reorderingState: ReorderableCellState = [] {
        didSet {
            wiggleBehavior.isWiggling = reorderingState.contains(.reordering)
            updateDeleteButton()
        }
    }

    var onDeleteTapped: (() -> Void)?
    
    private lazy var wiggleBehavior = WiggleBehavior(view: contentView)
    
    private var mainViewLeadingConstraint: NSLayoutConstraint!
    private var mainViewTopConstraint: NSLayoutConstraint!
    private var mainViewHeightConstraint: NSLayoutConstraint!
    private var titleLeadingConstraint: NSLayoutConstraint!
    private var titleTrailingConstraint: NSLayoutConstraint!

    private let deleteButton: UIButton = {
        let b = UIButton(type: .custom)
        b.alpha = 0
        b.layer.masksToBounds = false
        return b
    }()

    private func updateDeleteButtonImage(_ minusColor: UIColor, _ circleColor: UIColor) {
        let baseConfig = UIImage.SymbolConfiguration(pointSize: Self.deleteButtonImageSize, weight: .medium)
        let paletteConfig = UIImage.SymbolConfiguration(paletteColors: [minusColor, circleColor])
        let config = baseConfig.applying(paletteConfig)
        if let image = UIImage(systemName: "minus.circle.fill")?.applyingSymbolConfiguration(config) {
            deleteButton.setImage(image, for: .normal)
        }
        deleteButton.setPreferredSymbolConfiguration(config, forImageIn: .normal)
        if let imageView = deleteButton.imageView {
            imageView.layer.shadowColor = UIColor.black.cgColor
            imageView.layer.shadowOpacity = 0.15
            imageView.layer.shadowRadius = 3
            imageView.layer.shadowOffset = CGSize(width: 0, height: 1)
            imageView.layer.masksToBounds = false
        }
    }
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.adjustsFontSizeToFitWidth = false
        label.minimumScaleFactor = 1.0
        label.numberOfLines = 1
        return label
    }()
    
    let mainView = UIView()
    
    static let deleteButtonImageSize: CGFloat = 18
    static let deleteButtonSize: CGFloat = 24
    static let deleteButtonImageSideOffset: CGFloat = 6
    static var deleteButtonSideOffset: CGFloat { deleteButtonSize/2 - (deleteButtonImageSize / 2 - deleteButtonImageSideOffset) }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        mainView.addSubview(titleLabel)
        titleLeadingConstraint = titleLabel.leadingAnchor.constraint(equalTo: mainView.leadingAnchor, constant: 0)
        titleTrailingConstraint = titleLabel.trailingAnchor.constraint(equalTo: mainView.trailingAnchor, constant: 0)
        NSLayoutConstraint.activate([
            titleLeadingConstraint,
            titleTrailingConstraint,
            titleLabel.centerYAnchor.constraint(equalTo: mainView.centerYAnchor)
        ])

        mainView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(mainView)
        
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.addTarget(self, action: #selector(deleteButtonTapped), for: .touchUpInside)
        contentView.addSubview(deleteButton)
        
        mainViewLeadingConstraint = mainView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 0)
        mainViewHeightConstraint = mainView.heightAnchor.constraint(equalToConstant: 0)
        mainViewTopConstraint = mainView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 0)
        NSLayoutConstraint.activate([
            mainViewTopConstraint,
            mainViewHeightConstraint,
            mainView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: 0),
            mainViewLeadingConstraint,
            
            deleteButton.widthAnchor.constraint(equalToConstant: Self.deleteButtonSize),
            deleteButton.heightAnchor.constraint(equalToConstant: Self.deleteButtonSize),
            deleteButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 0),
            deleteButton.topAnchor.constraint(equalTo: mainView.topAnchor, constant: -Self.deleteButtonSideOffset),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        wiggleBehavior.prepareForReuse()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        wiggleBehavior.layoutDidChange()
    }

    private func updateDeleteButton() {
        UIView.animate(withDuration: 0.2) { [weak self] in
            guard let self else { return }
            self.deleteButton.alpha = reorderingState.contains(.reordering) && !reorderingState.contains(.dragging) ? 1.0 : 0.0
        }
    }
    
    @objc private func deleteButtonTapped() {
        onDeleteTapped?()
    }

    private func updateLayouts() {
        if deleteButton.isHidden {
            mainViewLeadingConstraint.constant = 0
        } else {
            mainViewLeadingConstraint.constant = Self.deleteButtonSideOffset
        }
    }
    
    func configure(title: String, textColor: UIColor, font: UIFont, backgroundColor: UIColor,
                   deleteButtonColor: UIColor, isDeletable: Bool, constants: SegmentedControlConstants) {
        mainView.backgroundColor = backgroundColor
        
        titleLabel.text = title
        titleLabel.textColor = textColor
        titleLabel.font = font
        
        mainView.layer.cornerRadius = constants.height / 2
        mainViewTopConstraint.constant = constants.topInset
        mainViewHeightConstraint.constant = constants.height
        titleLeadingConstraint.constant = constants.labelGap
        titleTrailingConstraint.constant = -constants.labelGap
        
        onDeleteTapped = nil
        if isDeletable {
            updateDeleteButtonImage(textColor, deleteButtonColor)
            deleteButton.isHidden = false
        } else {
            deleteButton.isHidden = true
        }
        
        updateLayouts()
    }
    
    static func widthFor(_ item: SegmentedControlItem, font: UIFont, labelGap: CGFloat) -> CGFloat {
        let text = item.title as NSString
        let constraintSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: font.lineHeight)
        let boundingRect = text.boundingRect(
            with: constraintSize,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        var width = ceil(boundingRect.width) + labelGap * 2
        if item.isDeletable {
            width += _Cell.deleteButtonSideOffset
        }
        return width
    }
}

private struct SegmentedControlReorderingVCRepresentable: UIViewRepresentable {
    let items: [SegmentedControlItem]
    let selection: SegmentedControlSelection?
    let primaryColor: UIColor
    let secondaryColor: UIColor
    let capsuleColor: UIColor
    let font: UIFont
    let constants: SegmentedControlConstants
    let scrollContentMargin: CGFloat
    let onChange: ([SegmentedControlItem]) -> Void
    
    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear
        let vc = SegmentedControlReorderingVC(
            items: items, selection: selection, primaryColor: primaryColor, secondaryColor: secondaryColor,
            capsuleColor: capsuleColor, font: font, constants: constants, scrollContentMargin: scrollContentMargin,
            onChange: onChange
        )
        context.coordinator.vc = vc
        let childView = vc.view!
        childView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(childView)
        NSLayoutConstraint.activate([
            childView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            childView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            childView.topAnchor.constraint(equalTo: container.topAnchor),
            childView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.vc?.updateFrom(items: items, selection: selection)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var vc: SegmentedControlReorderingVC?
    }
}


private class HorizontalCenteringFlowLayout: UICollectionViewFlowLayout {
    private var horizontalOffset: CGFloat = 0

    override func prepare() {
        super.prepare()
        horizontalOffset = computeHorizontalOffset()
    }

    private func computeHorizontalOffset() -> CGFloat {
        guard let collectionView else { return 0 }
        let insets = collectionView.adjustedContentInset
        let availableWidth = collectionView.bounds.width - insets.left - insets.right
        let contentWidth = super.collectionViewContentSize.width
        guard contentWidth < availableWidth else { return 0 }
        return ((availableWidth - contentWidth) / 2).rounded()
    }

    override var collectionViewContentSize: CGSize {
        var size = super.collectionViewContentSize
        if horizontalOffset > 0, let collectionView {
            let insets = collectionView.adjustedContentInset
            let availableWidth = collectionView.bounds.width - insets.left - insets.right
            size.width = max(size.width, availableWidth)
        }
        return size
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard horizontalOffset > 0 else {
            return super.layoutAttributesForElements(in: rect)
        }
        let queryRect = rect.offsetBy(dx: -horizontalOffset, dy: 0)
        guard let originals = super.layoutAttributesForElements(in: queryRect) else { return nil }
        return originals.map { shifted($0) }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard let attr = super.layoutAttributesForItem(at: indexPath) else { return nil }
        guard horizontalOffset > 0 else { return attr }
        return shifted(attr)
    }

    override func layoutAttributesForSupplementaryView(ofKind elementKind: String, at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard let attr = super.layoutAttributesForSupplementaryView(ofKind: elementKind, at: indexPath) else { return nil }
        guard horizontalOffset > 0 else { return attr }
        return shifted(attr)
    }

    override func layoutAttributesForDecorationView(ofKind elementKind: String, at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard let attr = super.layoutAttributesForDecorationView(ofKind: elementKind, at: indexPath) else { return nil }
        guard horizontalOffset > 0 else { return attr }
        return shifted(attr)
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        if let collectionView, collectionView.bounds.size != newBounds.size {
            return true
        }
        return super.shouldInvalidateLayout(forBoundsChange: newBounds)
    }

    private func shifted(_ attr: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        guard let copy = attr.copy() as? UICollectionViewLayoutAttributes else { return attr }
        copy.frame = copy.frame.offsetBy(dx: horizontalOffset, dy: 0)
        return copy
    }
}
