//
//  WalletSettingsGridCell.swift
//
//  Created by nikstar on 04.11.2025.
//

import UIKit
import WalletCore
import WalletContext
import UIComponents
import SwiftUI
import Perception

final class WalletSettingsGridCell: UICollectionViewCell, ReorderableCell {
    private var hostingController: UIHostingController<_Content>?
    private lazy var wiggle = WiggleBehavior(view: contentView)
    private let cellModel = _CellModel()

    override var isHighlighted: Bool {
        didSet {
            if isHighlighted != oldValue {
                cellModel.isHighlighted = isHighlighted
            }
        }
    }

    func setSelection(_ isSelected: Bool?) {
        cellModel.isSelected = isSelected
    }

    private func clearHighlight() {
        if isHighlighted {
            isHighlighted = false
        } else {
            cellModel.isHighlighted = false
        }
    }

    func configure(with accountContext: AccountContext, isSelected: Bool?) {
        contentView.backgroundColor = .clear
        cellModel.isSelected = isSelected
        let onClearHighlight: () -> Void = { [weak self] in
            guard let self else { return }
            self.clearHighlight()
        }

        if let hc = hostingController {
            hc.rootView = _Content(accountContext: accountContext, model: cellModel, onClearHighlight: onClearHighlight)
        } else {
            let hc = UIHostingController(rootView: _Content(accountContext: accountContext, model: cellModel, onClearHighlight: onClearHighlight))
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

        hostingController?.view.setNeedsLayout()
        contentView.layoutIfNeeded()
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        cellModel.isHighlighted = false
        cellModel.isSelected = nil
        wiggle.prepareForReuse()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        wiggle.layoutDidChange()
    }

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let attributes = super.preferredLayoutAttributesFitting(layoutAttributes)
        let targetWidth = attributes.size.width
        attributes.size.height = _Content.LayoutGeometry().preferredHeight(forCellWidth: targetWidth)
        return attributes
    }
        
    // MARK: - ReorderableCell
    
    var reorderingState: ReorderableCellState = [] {
        didSet {
            wiggle.isWiggling = reorderingState.contains(.reordering)
        }
    }
}

// MARK: - SwiftUI Content

private struct _Content: View {

    struct LayoutGeometry {
        let titleFont = UIFont.systemFont(ofSize: 13, weight: .medium)
        let borderWidth = 1.5
        let vStackSpacing = 7.0
        let titleBottomPadding = 7.0
        let selectionBulletSize = 28.0
        let selectionBulletInset = 2.0

        func preferredHeight(forCellWidth width: CGFloat) -> CGFloat {
            let selectionOutset = 4 * borderWidth
            let innerWidth = max(0, width - selectionOutset)
            let cardBodyHeight = innerWidth / SMALL_CARD_RATIO
            let cardStackHeight = cardBodyHeight + selectionOutset
            let titleLineHeight = ceil(titleFont.lineHeight)
            return ceil(cardStackHeight + vStackSpacing + titleLineHeight + titleBottomPadding)
        }
    }

    private let layoutGeometry = LayoutGeometry()

    let accountContext: AccountContext
    let model: _CellModel
    let onClearHighlight: () -> Void
    
    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: layoutGeometry.vStackSpacing) {
                MtwCard(aspectRatio: SMALL_CARD_RATIO)
                    .background {
                        MtwCardBackground(nft: accountContext.nft, hideBorder: true)
                    }
                    .overlay {
                        _BalanceView(accountContext: accountContext, onClearHighlight: onClearHighlight)
                    }
                    .overlay(alignment: .bottom) {
                        GridAddressLine(addressLine: accountContext.addressLine, nft: accountContext.nft)
                            .foregroundStyle(.white)
                            .padding(8)
                        
                    }
                    .overlay(alignment: .topTrailing) {
                        if let isSelected = model.isSelected {
                            selectionBullet(isSelected: isSelected)
                                .padding(layoutGeometry.selectionBulletInset)
                                .transition(.opacity.combined(with: .scale(scale: 0.85)))
                        }
                    }
                    .clipShape(.containerRelative)
                    .mtwCardSelection(isSelected: accountContext.isCurrent, cornerRadius: 12, lineWidth: layoutGeometry.borderWidth)
                    .containerShape(.rect(cornerRadius: 12))
                    .scaleEffect(model.isHighlighted && model.isSelected != nil ? 0.95 : 1)
                    .animation(.smooth(duration: 0.25), value: model.isHighlighted)

                Text(accountContext.account.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .allowsTightening(true)
                    .padding(.horizontal, -2)
                    .padding(.bottom, layoutGeometry.titleBottomPadding)
                
            }
            .animation(.smooth(duration: 0.3), value: model.animationKey)
        }
    }

    private func selectionBullet(isSelected: Bool) -> some View {
        Image.airBundle(isSelected ? "SelectedItem" : "UnselectedItem")
            .resizable()
            .frame(
                width: layoutGeometry.selectionBulletSize,
                height: layoutGeometry.selectionBulletSize
            )
            .contentTransition(.opacity)
    }
}

@Perceptible
private final class _CellModel {
    var isHighlighted = false
    var isSelected: Bool?

    var animationKey: AnimationKey {
        AnimationKey(isSelected: isSelected)
    }

    struct AnimationKey: Equatable {
        var isSelected: Bool?
    }
}

private struct _BalanceView: View {
    
    var accountContext: AccountContext
    var onClearHighlight: () -> Void
    
    var body: some View {
        WithPerceptionTracking {
            MtwCardBalanceView(
                balance: accountContext.balance,
                style: .grid,
                onSensitiveDataReveal: onClearHighlight
            )
                .frame(height: 24, alignment: .center)
                .padding(.leading, 6)
                .padding(.trailing, 5)
                .padding(.bottom, 6)
                .sourceAtop {
                    MtwCardBalanceGradient(nft: accountContext.nft)
                }
        }
    }
}

private struct GridAddressLine: View {
    
    var addressLine: MAccount.AddressLine
    var nft: ApiNft?
    
    var body: some View {
        MtwCardAddressLine(addressLine: addressLine, style: .card, gradient: MtwCardCenteredGradient(nft: nft))
    }
}
