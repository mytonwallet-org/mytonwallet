import UIKit
import WalletCore
import WalletContext
import UIComponents
import SwiftUI
import Perception

final class WalletSettingsListCell: UICollectionViewListCell, ReorderableCell {

    private var hostingController: UIHostingController<_Content>?
    private let cellModel = _CellModel()

    func configure(with accountContext: AccountContext) {
        if let hc = hostingController {
            hc.rootView = _Content(accountContext: accountContext, model: cellModel)
        } else {
            backgroundConfiguration = .clear()
            let hc = UIHostingController(rootView: _Content(accountContext: accountContext, model: cellModel))
            hc.view.backgroundColor = .clear
            hc.view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(hc.view)
            NSLayoutConstraint.activate([
                hc.view.topAnchor.constraint(equalTo: contentView.topAnchor),
                hc.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                hc.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            ])
            hostingController = hc
        }
        configurationUpdateHandler = { [weak self] _, state in
            guard let self else { return }
            
            self.cellModel.isHighlighted = state.isHighlighted
            self.cellModel.isLifted = state.cellDragState == .lifting
            self.cellModel.isDragged = state.cellDragState == .dragging
        }
        
        hostingController?.view.setNeedsLayout()
        contentView.layoutIfNeeded()
    }

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let attributes = super.preferredLayoutAttributesFitting(layoutAttributes)
        attributes.size.height = _Content.contentHeight
        return attributes
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        cellModel.isHighlighted = false
        cellModel.isLifted = false
        cellModel.isDragged = false
        cellModel.reorderingState = []
    }
    
    // MARK: - ReorderableCell

    var reorderingState: ReorderableCellState = [] {
        didSet {
            cellModel.reorderingState = reorderingState
        }
    }
}

// MARK: - SwiftUI Content

@Perceptible
private final class _CellModel: CustomStringConvertible {
    var isHighlighted: Bool = false
    var isLifted: Bool = false
    var isDragged: Bool = false
    var reorderingState: ReorderableCellState = []
    
    var isReordering: Bool { reorderingState.contains(.reordering) }
    var isEffectiveDragged: Bool { reorderingState.contains(.dragging) || isDragged }
    var isEffectiveHighlighted: Bool { isHighlighted && !isLifted && !isReordering && !isDragged }
    
    @PerceptionIgnored
    var description: String {
        "\(ObjectIdentifier(self)): \(isEffectiveDragged)  \(isEffectiveHighlighted)"
    }
}

private struct _Content: View {

    let accountContext: AccountContext
    let model: _CellModel
    
    private static let vPadding: CGFloat = 10
    static var contentHeight: CGFloat { vPadding * 2 + AccountListCell.contentHeight }
    
    var body: some View {
        WithPerceptionTracking {
            AccountListCell(
                accountContext: accountContext,
                isReordering: model.reorderingState.contains(.reordering),
                showCurrentAccountHighlight: true,
                showBalance: true
            )
            .padding(.horizontal, 12)
            .padding(.vertical, Self.vPadding)
            .background {
                CellBackgroundHighlight(
                    isHighlighted: model.isEffectiveHighlighted,
                    isSwiped: model.isEffectiveDragged,
                    normalColor: .air.groupedItem
                )
            }
        }
    }
}
