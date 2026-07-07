import UIKit
import WalletCore
import WalletContext
import UIComponents
import SwiftUI
import Perception

final class WalletSettingsListCell: UICollectionViewListCell, ReorderableCell {

    @MainActor
    enum Layout {
        static let textLeading = 62.0
        static let textTrailing = 12.0
        static var markerSpace: CGFloat { _Content.Layout.markerSpace }
        static var previewCornerRadius: CGFloat { S.insetSectionCornerRadius }
    }

    private var accountContext: AccountContext?
    private var hostingController: UIHostingController<_Content>?
    private let cellModel = _CellModel()

    func setSelection(_ isSelected: Bool?) {
        cellModel.isSelected = isSelected
    }

    func setPreviewChrome(_ isActive: Bool) {
        cellModel.isPreviewChromeForced = isActive
    }

    func configure(with accountContext: AccountContext, isSelected: Bool?) {
        self.accountContext = accountContext
        cellModel.isSelected = isSelected
        if let hc = hostingController {
            hc.rootView = _Content(accountContext: accountContext, model: cellModel)
        } else {
            var background = UIBackgroundConfiguration.listGroupedCell()
            background.backgroundColor = .air.groupedItem
            backgroundConfiguration = background

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
        attributes.size.height = _Content.Layout.contentHeight
        return attributes
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cellModel.isHighlighted = false
        cellModel.isLifted = false
        cellModel.isDragged = false
        cellModel.isPreviewChromeForced = false
        cellModel.reorderingState = []
        cellModel.isSelected = nil
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
private final class _CellModel {
    var isHighlighted: Bool = false
    var isLifted: Bool = false
    var isDragged: Bool = false
    var isPreviewChromeForced: Bool = false
    var isSelected: Bool?
    var reorderingState: ReorderableCellState = []

    var isReordering: Bool { reorderingState.contains(.reordering) }
    var isEffectiveDragged: Bool { reorderingState.contains(.dragging) || isDragged }

    /// Context-menu lift, custom reorder drag, and system drag preview.
    var usesPreviewChrome: Bool {
        isPreviewChromeForced || isLifted || isDragged || isReordering || reorderingState.contains(.dragging)
    }

    var isEffectiveHighlighted: Bool {
        isHighlighted && !usesPreviewChrome
    }

    var animationKey: AnimationKey {
        AnimationKey(
            isReordering: isReordering,
            isSelected: isSelected
        )
    }

    struct AnimationKey: Equatable {
        var isReordering: Bool
        var isSelected: Bool?
    }
}

private struct _Content: View {

    @MainActor
    enum Layout {
        static let markerSize: CGFloat = 22
        static let markerLeading: CGFloat = 6
        static let markerTrailing: CGFloat = 16
        static let trailing: CGFloat = 12
        static let vPadding: CGFloat = 10

        static let markerSpace: CGFloat = markerLeading + markerSize + markerTrailing
        static var contentHeight: CGFloat { vPadding * 2 + AccountListCell.contentHeight }
    }

    let accountContext: AccountContext
    let model: _CellModel

    var body: some View {
        WithPerceptionTracking {
            HStack(spacing: 0) {
                if let isSelected = model.isSelected {
                    selectionMarker(isSelected: isSelected)
                        .transition(.opacity.combined(with: .offset(x: -12)).combined(with: .scale(scale: 0.9)))
                }
                AccountListCell(
                    accountContext: accountContext,
                    isReordering: model.isReordering,
                    showCurrentAccountHighlight: true,
                    showBalance: true
                )
            }
            .padding(.horizontal, Layout.trailing)
            .padding(.vertical, Layout.vPadding)
            .background {
                CellBackgroundHighlight(
                    isHighlighted: model.isEffectiveHighlighted,
                    isSwiped: model.usesPreviewChrome,
                    normalColor: .air.groupedItem
                )
            }
            .animation(.snappy, value: model.animationKey)
        }
    }

    func selectionMarker(isSelected: Bool) -> some View {
        return ZStack {
            Circle()
                .strokeBorder(Color.air.secondaryLabel.opacity(0.5), lineWidth: 1.2)
                .opacity(isSelected ? 0 : 1)
                .padding(1.2)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: Layout.markerSize))
                .foregroundStyle(Color(uiColor: .tintColor))
                .opacity(isSelected ? 1 : 0)
        }
        .frame(width: Layout.markerSize, height: Layout.markerSize)
        .padding(.trailing, Layout.markerTrailing)
        .padding(.leading, Layout.markerLeading)
    }
}
