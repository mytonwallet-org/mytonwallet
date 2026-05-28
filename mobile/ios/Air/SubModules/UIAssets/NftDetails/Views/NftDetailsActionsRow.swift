
import SwiftUI
import UIKit
import UIComponents
import WalletContext
import WalletCore
import Kingfisher
import Dependencies

struct NftDetailsActionsRow: View {
    
    @ObservedObject var viewModel: NftDetailsViewModel
    
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var wearMenu: MenuContext = MenuContext()
    @State private var moreMenu: MenuContext = MenuContext()
    
    var buttonCount: Int {
        viewModel.nft.isMtwCard ? 4 : 3
    }
    
    var buttonSpacing: CGFloat {
        S.actionButtonSpacing(forButtonCount: buttonCount)
    }
    
    var body: some View {
        HStack(spacing: IOS_26_MODE_ENABLED ? buttonSpacing : 8) {
            wear
            send
            share
            more
        }
        .fixedSize(horizontal: IOS_26_MODE_ENABLED, vertical: false)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, IOS_26_MODE_ENABLED ? 0 : 16)
        .padding(.top, 16)
        .padding(.bottom, 16)
        .tint(viewModel.isExpanded ? Color.white : Color(WTheme.tint))
        .environmentObject(viewModel)
        .fixedSize(horizontal: false, vertical: true)
        .task {
            wearMenu.onAppear = {
                viewModel.selectedSubmenu = "wear"
            }
            wearMenu.onDismiss = {
                viewModel.selectedSubmenu = nil
            }
            moreMenu.onAppear = {
                viewModel.selectedSubmenu = "more"
            }
            moreMenu.onDismiss = {
                viewModel.selectedSubmenu = nil
            }
        }
    }
    
    @ViewBuilder var wear: some View {
        if viewModel.nft.isMtwCard {
            ZStack {
                ActionButton(
                    viewModel: viewModel,
                    id: "wear",
                    title: IOS_26_MODE_ENABLED ? lang("Wear") : lang("Wear").lowercased(),
                    icon: IOS_26_MODE_ENABLED ? "WearIconBold" : "ActionWear24"
                ) {
                }
                Color.clear.contentShape(.rect)
            }
            .compositingGroup()
            .menuSource(menuContext: wearMenu)
            .task {
                wearMenu.makeConfig = {
                    
                    @Dependency(\.accountStore.currentAccountId) var currentAccountId
                    @Dependency(\.accountSettings) var _accountSettings
                    let accountSettings = _accountSettings.for(accountId: currentAccountId)
                    
                    let nft = viewModel.nft
                    var items: [MenuItem] = []
                    if let mtwCardId = nft.metadata?.mtwCardId {
                        let isCurrent = mtwCardId == accountSettings.backgroundNft?.metadata?.mtwCardId
                        if isCurrent {
                            items += .button(id: "0-card", title: lang("Reset Card"), trailingIcon: .air("MenuInstallCard26")) {
                                accountSettings.setBackgroundNft(nil)
                            }
                        } else {
                            items += .button(id: "0-card", title: lang("Install Card"), trailingIcon: .air("MenuInstallCard26")) {
                                accountSettings.setBackgroundNft(nft)
                                accountSettings.setAccentColorNft(nft)
                            }
                        }
                        let isCurrentAccent = mtwCardId == accountSettings.accentColorNft?.metadata?.mtwCardId
                        if isCurrentAccent {
                            items += .button(id: "0-palette", title: lang("Reset Palette"), trailingIcon: .air("custom.paintbrush.badge.xmark")) {
                                accountSettings.setAccentColorNft(nil)
                            }
                        } else {
                            items += .button(id: "0-palette", title: lang("Apply Palette"), trailingIcon: .air("MenuBrush26")) {
                                accountSettings.setAccentColorNft(nft)
                            }
                        }
                    }
                    return MenuConfig(menuItems: items)
                }
            }
        }
    }
    
    @ViewBuilder var send: some View {
        ActionButton(
            viewModel: viewModel,
            id: "send",
            title: IOS_26_MODE_ENABLED ? lang("Send") : lang("Send").lowercased(),
            icon: IOS_26_MODE_ENABLED ? "SendIconBold" : "ActionSend24"
        ) {
            AppActions.showSend(prefilledValues: .init(nfts: [viewModel.nft], nftSendMode: .send))
        }
    }
    
    @ViewBuilder var share: some View {
        ActionButton(
            viewModel: viewModel,
            id: "share",
            title: IOS_26_MODE_ENABLED ? lang("Share") : lang("Share").lowercased(),
            icon: IOS_26_MODE_ENABLED ? "ShareIconBold" : "ActionShare24"
        ) {
            AppActions.shareUrl(ExplorerHelper.nftUrl(viewModel.nft))
        }
    }
    
    @ViewBuilder var more: some View {
        ZStack {
            ActionButton(
                viewModel: viewModel,
                id: "more",
                title: IOS_26_MODE_ENABLED ? lang("More") : lang("More").lowercased(),
                icon: IOS_26_MODE_ENABLED ? "MoreIconBold" : "ActionMore24"
            ) {
            }
            Color.clear.contentShape(.rect)
        }
        .compositingGroup()
        .menuSource(menuContext: moreMenu)
        .task(id: viewModel.accountId) {
            let accountId = viewModel.accountId
            self.moreMenu.makeConfig = {
                var items: [MenuItem] = []
                items += .button(id: "0-hide", title: lang("Hide"), trailingIcon: .air("MenuHide26")) {
                    NftStore.setHiddenByUser(accountId: accountId, nftId: viewModel.nft.id, isHidden: true)
                }
                items += .button(id: "0-burn", title: lang("Burn"), trailingIcon: .air("MenuBurn26"), isDangerous: true) {
                    AppActions.showSend(prefilledValues: .init(nfts: [viewModel.nft], nftSendMode: .burn))
                }
                items += .wideSeparator()
                items += .button(id: "0-getgems", title: "Getgems", trailingIcon: .air("MenuGetgems26")) {
                    let url = ExplorerHelper.nftUrl(viewModel.nft)
                    AppActions.openInBrowser(url)
                }
                items += .button(id: "0-tonscan", title: "Tonscan", trailingIcon: .air("MenuTonscan26")) {
                    let url = ExplorerHelper.tonscanNftUrl(viewModel.nft)
                    AppActions.openInBrowser(url)
                }
                return MenuConfig(menuItems: items)
            }
        }
    }
}

struct ActionButton: View {

    @ObservedObject var viewModel: NftDetailsViewModel
    
    var id: String
    var title: String
    var icon: String
    var action: () -> ()

    init(viewModel: NftDetailsViewModel, id: String, title: String, icon: String, action: @escaping () -> Void) {
        self.viewModel = viewModel
        self.id = id
        self.title = title
        self.icon = icon
        self.action = action
    }

    var body: some View {
        if #available(iOS 26, *) {
            ActionButton_New(viewModel: viewModel, id: id, title: title, icon: icon, action: action)
        } else {
            ActionButton_Legacy(viewModel: viewModel, id: id, title: title, icon: icon, action: action)
        }
    }
}

@available(iOS 26, *)
struct ActionButton_New: View {

    @ObservedObject var viewModel: NftDetailsViewModel
    
    var id: String
    var title: String
    var icon: String
    var action: () -> ()

    var isEnabled: Bool { viewModel.selectedSubmenu == nil || viewModel.selectedSubmenu == id }
    
    init(viewModel: NftDetailsViewModel, id: String, title: String, icon: String, action: @escaping () -> Void) {
        self.viewModel = viewModel
        self.id = id
        self.title = title
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Image.airBundle("ActionButtonBackground")
                        .opacity(viewModel.isExpanded ? 0 : 1)
                    Image.airBundle(icon)
                        .foregroundStyle(viewModel.isExpanded ? .white : Color.air.tint)
                }
                .frame(width: 48, height: 48)
                .clipShape(.circle)
                .glassEffect(.clear.interactive())
                
                Text(title)
                    .font(.system(size: 12, weight: .regular))
                    .frame(height: 13)
                    .foregroundStyle(viewModel.isExpanded ? .white : .primary)
            }
            .opacity(isEnabled ? 1 : 0.3)
            .frame(width: 64, height: 70)
            .backportGeometryGroup()
        }
        .buttonStyle(.plain)
        .animation(.smooth(duration: 0.25), value: isEnabled)
    }
}

struct ActionButton_Legacy: View {

    @ObservedObject var viewModel: NftDetailsViewModel
    
    var id: String
    var title: String
    var icon: String
    var action: () -> ()

    var isEnabled: Bool { viewModel.selectedSubmenu == nil || viewModel.selectedSubmenu == id }
    
    init(viewModel: NftDetailsViewModel, id: String, title: String, icon: String, action: @escaping () -> Void) {
        self.viewModel = viewModel
        self.id = id
        self.title = title
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image.airBundle(icon)
                    .frame(width: 24, height: 24)
                    .foregroundStyle(.tint)
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
            }
            .fixedSize()
            .drawingGroup()
            .opacity(isEnabled ? 1 : 0.3)
        }
        .buttonStyle(ActionButtonStyle())
        .animation(.smooth(duration: 0.25), value: isEnabled)
    }
}

struct ActionButtonStyle: PrimitiveButtonStyle {

    @EnvironmentObject var viewModel: NftDetailsViewModel
    
    @State private var isHighlighted: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .opacity(isHighlighted ? 0.5 : 1)
            .background {
                ZStack {
                    BackgroundBlur(radius: 20)
                        .background(Color.white.opacity(0.04))
                    ZStack {
                        Color.black.opacity(0.04)
                        Color.white.opacity(0.04)
                    }
                    ZStack {
                        Color.black.opacity(0.04)
                        Color.white.opacity(0.16)
                    }
                    .blendMode(.colorBurn)

                    RoundedRectangle(cornerRadius: S.actionButtonCornerRadius)
                        .fill(Color(WTheme.groupedItem))
                        .opacity(viewModel.isExpanded ? 0 : 1)
                }
                .clipShape(.rect(cornerRadius: S.actionButtonCornerRadius))
            }
            .contentShape(.rect(cornerRadius: S.actionButtonCornerRadius))
            .onTapGesture {
                configuration.trigger()
            }
            .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in
                withAnimation(.spring(duration: 0.1)) {
                    isHighlighted = true
                }
            }.onEnded { _ in
                withAnimation(.spring(duration: 0.5)) {
                    isHighlighted = false
                }
            })
    }
}

#if DEBUG
@available(iOS 18, *)
#Preview {
    @Previewable var viewModel = NftDetailsViewModel(accountId: "0-mainnet", nft: .sampleMtwCard, listContext: .none, navigationBarInset: 0)
    VStack {
        NftDetailsActionsRow(viewModel: viewModel)
        Button("Toggle isExplanded") {
            withAnimation(.spring(duration: 2)) {
                viewModel.isExpanded.toggle()
            }
        }
    }
    .padding(32)
    .background(Color.blue.opacity(0.2))
}
#endif
