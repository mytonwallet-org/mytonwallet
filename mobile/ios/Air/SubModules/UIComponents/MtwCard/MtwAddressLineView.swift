//
//  AddressLineView.swift
//  MyTonWalletAir
//
//  Created by nikstar on 17.11.2025.
//

import SwiftUI
import WalletContext
import WalletCore

public struct MtwCardAddressLine: View {
    
    public struct Style {
        public let font: Font
        public let textOpacity: CGFloat
        public let accountTypeIconSpacing: CGFloat
        public let largeAccountTypeIcon: Bool
        public let fullcolorChainIcons: Bool
        public let chainIconWidth: CGFloat
        public let chainIconSpacing: CGFloat
        public let chainSpacing: CGFloat
        public let multichainEndCount: Int
        public let showComma: Bool
        public let showAccessories: Bool
        
        public static let list = Style(
            font: .system(size: 14, weight: .regular),
            textOpacity: 1,
            accountTypeIconSpacing: 4,
            largeAccountTypeIcon: false,
            fullcolorChainIcons: false,
            chainIconWidth: 13,
            chainIconSpacing: 0,
            chainSpacing: 3,
            multichainEndCount: 4,
            showComma: true,
            showAccessories: false,
        )
        public static let card = Style(
            font: .compactMedium(size: 11),
            textOpacity: 1,
            accountTypeIconSpacing: 3.333,
            largeAccountTypeIcon: false,
            fullcolorChainIcons: false,
            chainIconWidth: 12,
            chainIconSpacing: 0,
            chainSpacing: 1.667,
            multichainEndCount: 3,
            showComma: false,
            showAccessories: false,
        )
        public static let homeCard = Style(
            font: .compactMedium(size: 17),
            textOpacity: 0.75,
            accountTypeIconSpacing: 4,
            largeAccountTypeIcon: true,
            fullcolorChainIcons: true,
            chainIconWidth: 16,
            chainIconSpacing: 4,
            chainSpacing: 6,
            multichainEndCount: 4,
            showComma: true,
            showAccessories: true,
        )
        public static let customizeWalletCard = Style(
            font: .compactMedium(size: 17),
            textOpacity: 0.75,
            accountTypeIconSpacing: 4,
            largeAccountTypeIcon: true,
            fullcolorChainIcons: true,
            chainIconWidth: 16,
            chainIconSpacing: 4,
            chainSpacing: 6,
            multichainEndCount: 4,
            showComma: true,
            showAccessories: false,
        )
    }
    
    var addressLine: MAccount.AddressLine
    var style: Style
    
    public init(addressLine: MAccount.AddressLine, style: Style) {
        self.addressLine = addressLine
        self.style = style
    }
    
    public var body: some View {
        HStack(spacing: style.accountTypeIconSpacing) {
            let itemsCount = addressLine.items.count
            if addressLine.isTestnet {
                addressLine.testnetImage
            }
            if let leadingIcon = addressLine.leadingIcon {
                if style.largeAccountTypeIcon {
                    switch leadingIcon {
                    case .ledger:
                        AccountTypeBadge(.hardware, style: .card)
                    case .view:
                        AccountTypeBadge(.view, style: .card)
                    }
                } else {
                    leadingIcon.image
                        .opacity(style.textOpacity)
                }
            }
            HStack(spacing: style.chainSpacing) {
                ForEach(addressLine.items) { item in
                    ItemView(item: item, itemsCount: itemsCount, style: style)
                }
            }
            if style.showAccessories {
                Image.airBundle("ChevronDown10")
                    .opacity(style.textOpacity)
                    .offset(y: 1)
                    .padding(.vertical, -3)
            }
        }
        .lineLimit(1)
        .font(style.font)
        .allowsTightening(true)
    }
}

private struct ItemView: View {
    
    var item: MAccount.AddressLine.Item
    var itemsCount: Int
    var style: MtwCardAddressLine.Style
    
    var body: some View {
        HStack(spacing: style.chainIconSpacing) {
            if style.fullcolorChainIcons {
                Image.airBundle("chain_\(item.chain)")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: style.chainIconWidth)
            } else {
                Image.airBundle("inline_chain_\(item.chain)")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: style.chainIconWidth)
                    .opacity(style.textOpacity)
            }
            
            let comma = item.isLast ? "" : ","
            if item.isDomain {
                Text(item.text + comma)
                    .truncationMode(.middle)
                    .opacity(style.textOpacity)
            } else {
                Text(formatStartEndAddress(item.text, prefix: itemsCount == 1 ? 4 : 0, suffix: style.multichainEndCount) + comma)
                    .opacity(style.textOpacity)
            }
        }
        .contentShape(.rect)
        .longTapGesture_ios18(isEnabled: true, onLongTap: onCopy)
    }
    
    func onCopy() {
        UIPasteboard.general.string = item.textToCopy
        topWViewController()?.showToast(animationName: "Copy", message: lang("Address was copied!"))
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }
}
