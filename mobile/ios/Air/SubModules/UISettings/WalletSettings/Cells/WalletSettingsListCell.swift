import UIKit
import QuartzCore
import WalletCore
import WalletContext
import UIComponents
import SwiftUI
import Perception

final class WalletSettingsListCell: UICollectionViewListCell, ReorderableCell, UIGestureRecognizerDelegate {

    @MainActor
    enum Layout {
        static let textLeading = 62.0
        static let textTrailing = 12.0
        static var markerSpace: CGFloat { _Content.Layout.markerSpace }
    }

    private var hostingController: UIHostingController<_Content>?
    private let cellModel = _CellModel()

    private var accountContext: AccountContext?
    private var selectionTapRecognizer: ShortTapGestureRecognizer?
    private var onToggleSelection: (() -> Void)?

    func configure(with accountContext: AccountContext, isSelected: Bool, onToggleSelection: @escaping () -> Void) {
        self.accountContext = accountContext
        self.onToggleSelection = onToggleSelection
        cellModel.isSelected = isSelected
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

            // A short, movement-free tap toggles selection. Picking a cell up to drag (which lifts it
            // almost immediately) or holding it must NOT toggle, so the recognizer fails on movement
            // or a long press instead of firing on any release-in-place.
            let tap = ShortTapGestureRecognizer(target: self, action: #selector(handleSelectionTap))
            tap.delegate = self
            tap.cancelsTouchesInView = false
            contentView.addGestureRecognizer(tap)
            selectionTapRecognizer = tap
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
        cellModel.reorderingState = []
        cellModel.isSelected = false
        onToggleSelection = nil
    }
    
    @objc private func handleSelectionTap() {
        guard cellModel.isReordering else { return }
        onToggleSelection?()
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === selectionTapRecognizer {
            return cellModel.isReordering
        }
        
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        gestureRecognizer === selectionTapRecognizer
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
    var isSelected: Bool = false
    var reorderingState: ReorderableCellState = []

    var isReordering: Bool { reorderingState.contains(.reordering) }
    var isEffectiveDragged: Bool { reorderingState.contains(.dragging) || isDragged }
    var isEffectiveHighlighted: Bool { isHighlighted && !isLifted && !isReordering && !isDragged }

    var animationKey: AnimationKey {
        AnimationKey(
            isReordering: isReordering,
            isSelected: isSelected,
            isEffectiveHighlighted: isEffectiveHighlighted,
            isEffectiveDragged: isEffectiveDragged
        )
    }

    struct AnimationKey: Equatable {
        var isReordering: Bool
        var isSelected: Bool
        var isEffectiveHighlighted: Bool
        var isEffectiveDragged: Bool
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
                if model.isReordering {
                    selectionMarker
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
                    isSwiped: model.isEffectiveDragged,
                    normalColor: .air.groupedItem
                )
            }
            .animation(.snappy, value: model.animationKey)
        }
    }

    private var selectionMarker: some View {
        return ZStack {
            Circle()
                .strokeBorder(Color.air.secondaryLabel.opacity(0.5), lineWidth: 1.2)
                .opacity(model.isSelected ? 0 : 1)
                .padding(1.2)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: Layout.markerSize))
                .foregroundStyle(Color(uiColor: .tintColor))
                .opacity(model.isSelected ? 1 : 0)
        }
        .frame(width: Layout.markerSize, height: Layout.markerSize)
        .padding(.trailing, Layout.markerTrailing)
        .padding(.leading, Layout.markerLeading)
    }
}

// MARK: - ShortTapGestureRecognizer

/// A tap recognizer that only succeeds for a quick tap that doesn't move. It fails as soon as the touch
/// moves beyond `maxMovement` (an actual drag) or stays down longer than `maxDuration` (a deliberate
/// pick-up/hold), so releasing a lifted/dragged cell in place does not register as a selection tap.
final class ShortTapGestureRecognizer: UITapGestureRecognizer {

    var maxDuration: CFTimeInterval = 0.35
    var maxMovement: CGFloat = 10

    private var startTime: CFTimeInterval = 0
    private var startLocation: CGPoint = .zero
    private var didMoveTooFar = false

    override func reset() {
        super.reset()
        didMoveTooFar = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        startTime = CACurrentMediaTime()
        startLocation = touches.first?.location(in: view) ?? .zero
        didMoveTooFar = false
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard let location = touches.first?.location(in: view) else { return }
        if hypot(location.x - startLocation.x, location.y - startLocation.y) > maxMovement {
            didMoveTooFar = true
            state = .failed
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        if didMoveTooFar || CACurrentMediaTime() - startTime > maxDuration {
            state = .failed
            return
        }
        super.touchesEnded(touches, with: event)
    }
}
