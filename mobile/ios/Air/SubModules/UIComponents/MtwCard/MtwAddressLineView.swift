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
    
    public struct Style: Equatable, Hashable {
        public let font: Font
        public let textOpacity: CGFloat
        public let accountTypeIconSpacing: CGFloat
        public let largeAccountTypeIcon: Bool
        public let fullcolorChainIcons: Bool
        public let chainIconWidth: CGFloat
        public let chainIconSpacing: CGFloat
        public let chainSpacing: CGFloat
        public let singlechainAddressCount: Int
        public let multichainEndCount: Int
        public let multichainAddressCount: Int
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
            singlechainAddressCount: 6,
            multichainEndCount: 6,
            multichainAddressCount: 2,
            showComma: true,
            showAccessories: false,
        )
        public static let card = Style(
            font: .compactDisplay(size: 11, weight: .medium),
            textOpacity: 1,
            accountTypeIconSpacing: 3.333,
            largeAccountTypeIcon: false,
            fullcolorChainIcons: false,
            chainIconWidth: 12,
            chainIconSpacing: 0,
            chainSpacing: 1.667,
            singlechainAddressCount: 4,
            multichainEndCount: 4,
            multichainAddressCount: 2,
            showComma: false,
            showAccessories: false,
        )
        public static let homeCard = Style(
            font: .compactDisplay(size: 17, weight: .medium),
            textOpacity: 0.75,
            accountTypeIconSpacing: 4,
            largeAccountTypeIcon: true,
            fullcolorChainIcons: true,
            chainIconWidth: 16,
            chainIconSpacing: 4,
            chainSpacing: 6,
            singlechainAddressCount: 6,
            multichainEndCount: 6,
            multichainAddressCount: 2,
            showComma: true,
            showAccessories: true,
        )
        public static let customizeWalletCard = Style(
            font: .compactDisplay(size: 17, weight: .medium),
            textOpacity: 0.75,
            accountTypeIconSpacing: 4,
            largeAccountTypeIcon: true,
            fullcolorChainIcons: true,
            chainIconWidth: 16,
            chainIconSpacing: 4,
            chainSpacing: 6,
            singlechainAddressCount: 4,
            multichainEndCount: 4,
            multichainAddressCount: 2,
            showComma: true,
            showAccessories: false,
        )
    }
    
    var addressLine: MAccount.AddressLine
    var style: Style
    var gradient: MtwCardCenteredGradient?
    
    @Namespace private var ns
        
    public init(addressLine: MAccount.AddressLine, style: Style, gradient: MtwCardCenteredGradient?) {
        self.addressLine = addressLine
        self.style = style
        self.gradient = gradient
    }
    
    public var body: some View {
        HStack(spacing: style.accountTypeIconSpacing) {
            let itemsCount = addressLine.items.count
            if addressLine.isTestnet {
                addressLine.testnetImage
                    .sourceAtop {
                        if let gradient {
                            gradient.matchedGeometryEffect(id: "address", in: ns, isSource: false)
                        }
                    }
            }
            Group {
                if let leadingIcon = addressLine.leadingIcon {
                    if style.largeAccountTypeIcon {
                        switch leadingIcon {
                        case .ledger:
                            AccountTypeBadge(.hardware, increasedOpacity: gradient?.nft?.metadata?.mtwCardType?.isPremium == true)
                        case .view:
                            AccountTypeBadge(.view, increasedOpacity: gradient?.nft?.metadata?.mtwCardType?.isPremium == true)
                        }
                    } else {
                        leadingIcon.image
                            .opacity(style.textOpacity)
                    }
                }
            }
            .sourceAtop {
                if let gradient {
                    gradient.matchedGeometryEffect(id: "address", in: ns, isSource: false)
                }
            }
            .background {
                if style.largeAccountTypeIcon && addressLine.leadingIcon == .view {
                    BackgroundBlur(radius: 12)
                        .clipShape(.rect(cornerRadius: viewBadgeCornerRadius))
                        .padding(.vertical, -viewBadgeVerticalPadding)
                }
            }
            HStack(spacing: style.chainSpacing) {
                let addressesToShowCount = itemsCount == 1 ? 1 : min(style.multichainAddressCount, itemsCount)
                ForEach(addressLine.items.indices, id: \.self) { idx in
                    ItemView(
                        item: addressLine.items[idx],
                        itemsCount: itemsCount,
                        showAddress: idx < addressesToShowCount,
                        style: style,
                        gradient: gradient,
                        ns: ns
                    )
                }
            }
            if style.showAccessories {
                Image.airBundle("ArrowUpDownSmall")
                    .opacity(style.textOpacity == 1 ? 0.9 : 0.5)
                    .offset(x: -1, y: 0.333)
                    .padding(.vertical, -3)
                    .sourceAtop {
                        if let gradient {
                            gradient.matchedGeometryEffect(id: "address", in: ns, isSource: false)
                        }
                    }
            }
        }
        .lineLimit(1)
        .font(style.font)
        .allowsTightening(true)
        .background {
            if gradient != nil {
                Color.clear.matchedGeometryEffect(id: "address", in: ns, isSource: true)
            }
        }
    }
}

private struct ItemView: View {
    
    var item: MAccount.AddressLine.Item
    var itemsCount: Int
    var showAddress: Bool
    var style: MtwCardAddressLine.Style
    var gradient: MtwCardCenteredGradient?
    var ns: Namespace.ID

    var body: some View {
        HStack(spacing: showAddress ? style.chainIconSpacing : 0) {
            if style.fullcolorChainIcons {
                Image.airBundle("chain_\(item.chain.rawValue)")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: style.chainIconWidth)
            } else {
                Image.airBundle("inline_chain_\(item.chain.rawValue)")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: style.chainIconWidth)
                    .opacity(style.textOpacity)
            }
            
            Group {
                let comma = style.showComma && !item.isLast ? "," : ""
                if showAddress {
                    if item.isDomain {
                        Text(item.text + comma)
                            .truncationMode(.middle)
                            .opacity(style.textOpacity)
                    } else {
                        Text(formatStartEndAddress(item.text, prefix: itemsCount == 1 ? style.singlechainAddressCount : 0, suffix: itemsCount == 1 ? style.singlechainAddressCount : style.multichainEndCount) + comma)
                            .opacity(style.textOpacity)
                    }
                } else if !comma.isEmpty {
                    Text(comma)
                        .opacity(style.textOpacity)
                }
            }
            .sourceAtop {
                if style.fullcolorChainIcons, let gradient {
                    gradient.matchedGeometryEffect(id: "address", in: ns, isSource: false)
                }
            }
        }
        .contentShape(.rect)
        .longTapGesture_ios18(isEnabled: true, onLongTap: onCopy)
        .sourceAtop {
            if !style.fullcolorChainIcons, let gradient {
                gradient.matchedGeometryEffect(id: "address", in: ns, isSource: false)
            }
        }
    }
    
    func onCopy() {
        UIPasteboard.general.string = item.textToCopy
        AppActions.showToast(animationName: "Copy", message: lang("%chain% Address Copied", arg1: item.chain.title))
        Haptics.play(.lightTap)
    }
}
