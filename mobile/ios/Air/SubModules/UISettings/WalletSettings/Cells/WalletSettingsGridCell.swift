//
//  WalletSettingsGridCell.swift
//  MyTonWalletAir
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

    func configure(with accountContext: AccountContext) {
        contentView.backgroundColor = .clear

        if let hc = hostingController {
            hc.rootView = _Content(accountContext: accountContext)
        } else {
            let hc = UIHostingController(rootView: _Content(accountContext: accountContext))
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
    
    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: layoutGeometry.vStackSpacing) {
                MtwCard(aspectRatio: SMALL_CARD_RATIO)
                    .background {
                        MtwCardBackground(nft: accountContext.nft, hideBorder: true)
                    }
                    .overlay {
                        _BalanceView(accountContext: accountContext)
                    }
                    .overlay(alignment: .bottom) {
                        GridAddressLine(addressLine: accountContext.addressLine, nft: accountContext.nft)
                            .foregroundStyle(.white)
                            .padding(8)
                        
                    }
                    .clipShape(.containerRelative)
                    .mtwCardSelection(isSelected: accountContext.isCurrent, cornerRadius: 12, lineWidth: layoutGeometry.borderWidth)
                    .containerShape(.rect(cornerRadius: 12))
                    
                Text(accountContext.account.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .allowsTightening(true)
                    .padding(.horizontal, -2)
                    .padding(.bottom, layoutGeometry.titleBottomPadding)
                
            }
        }
    }
}

private struct _BalanceView: View {
    
    var accountContext: AccountContext
    
    var body: some View {
        WithPerceptionTracking {
            MtwCardBalanceView(balance: accountContext.balance, style: .grid)
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
