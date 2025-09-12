
import SwiftUI
import UIKit
import UIComponents
import WalletContext
import WalletCore
import Kingfisher


struct NftDetailsActionsRow: View {
    
    @ObservedObject var viewModel: NftDetailsViewModel
    
    @Environment(\.colorScheme) private var colorScheme
    
    @StateObject private var wearMenu: MenuContext = MenuContext()
    @StateObject private var moreMenu: MenuContext = MenuContext()
    
    var body: some View {
        HStack(spacing: 8) {
            wear
            send
            share
            more
        }
        .padding(.horizontal, 16)
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
                    title: lang("Wear").lowercased(),
                    icon: "ActionWear24"
                ) {
                }
                Color.clear.contentShape(.rect)
            }
            .compositingGroup()
            .menuSource(isEnabled: true, coordinateSpace: .global, menuContext: wearMenu)
            .task {
                wearMenu.setMenu {
                    WearMenuContent(nft: viewModel.nft, dismiss: { wearMenu.dismiss() })
                }
            }
        }
    }
    
    @ViewBuilder var send: some View {
        ActionButton(
            viewModel: viewModel,
            id: "send",
            title: lang("Send").lowercased(),
            icon: "ActionSend24"
        ) {
            AppActions.showSend(prefilledValues: .init(nfts: [viewModel.nft], nftSendMode: .send))
        }
    }
    
    @ViewBuilder var share: some View {
        ActionButton(
            viewModel: viewModel,
            id: "share",
            title: lang("Share").lowercased(),
            icon: "ActionShare24"
        ) {
            AppActions.shareUrl(ExplorerHelper.nftUrl(viewModel.nft))
        }
    }
    
    @ViewBuilder var more: some View {
        ZStack {
            ActionButton(
                viewModel: viewModel,
                id: "more",
                title: lang("More").lowercased(),
                icon: "ActionMore24"
            ) {
            }
            Color.clear.contentShape(.rect)
        }
        .compositingGroup()
        .menuSource(isEnabled: true, coordinateSpace: .global, menuContext: moreMenu)
        .task {
            self.moreMenu.setMenu {
                ScrollableMenuContent {
                    VStack(spacing: 0) {
                        DividedVStack {
                            WMenuButton(id: "0-hide", title: "Hide", trailingIcon: "MenuHide26") {
                                NftStore.setHiddenByUser(accountId: AccountStore.accountId ?? "", nftId: viewModel.nft.id, isHidden: true)
                                moreMenu.dismiss()
                            }
                            WMenuButton(id: "0-burn", title: "Burn", trailingIcon: "MenuBrush26") {
                                AppActions.showSend(prefilledValues: .init(nfts: [viewModel.nft], nftSendMode: .burn))
                                moreMenu.dismiss()
                            }
                            .foregroundStyle(.red)
                            
                        }
                        WideSeparator()
                        DividedVStack {
                            WMenuButton(id: "0-getgems", title: "Getgems", trailingIcon: "MenuGetgems26") {
                                let url = ExplorerHelper.nftUrl(viewModel.nft)
                                AppActions.openInBrowser(url)
                                moreMenu.dismiss()
                            }
                            WMenuButton(id: "0-tonscan", title: "Tonscan", trailingIcon: "MenuTonscan26") {
                                let url = ExplorerHelper.tonscanNftUrl(viewModel.nft)
                                AppActions.openInBrowser(url)
                                moreMenu.dismiss()
                            }
                        }
                        
                    }
                }
                .frame(minHeight: 200, alignment: .top)
                .frame(maxWidth: 220)
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
                Text(title)
                    .font(.system(size: 12))
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
            .foregroundStyle(.tint)
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

                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(WTheme.groupedItem))
                        .opacity(viewModel.isExpanded ? 0 : 1)
                }
                .clipShape(.rect(cornerRadius: 12))
            }
            .contentShape(.rect(cornerRadius: 12))
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

struct WearMenuContent: View {
    
    var nft: ApiNft
    var dismiss: () -> ()
    
    var body: some View {
        if let mtwCardId = nft.metadata?.mtwCardId {
            ScrollableMenuContent {
                DividedVStack {
                    let isCurrent = mtwCardId == AccountStore.currentAccountCardBackgroundNft?.metadata?.mtwCardId
                    if isCurrent {
                        WMenuButton(id: "0-card", title: "Reset Card", trailingIcon: "MenuInstallCard26") {
                            AccountStore.currentAccountCardBackgroundNft = nil
                            AccountStore.currentAccountAccentColorNft = nil
                            dismiss()
                        }
                    } else {
                        WMenuButton(id: "0-card", title: "Install Card", trailingIcon: "MenuInstallCard26") {
                            AccountStore.currentAccountCardBackgroundNft = nft
                            AccountStore.currentAccountAccentColorNft = nft
                            dismiss()
                        }
                    }
                    
                    let isCurrentAccent = mtwCardId == AccountStore.currentAccountAccentColorNft?.metadata?.mtwCardId
                    if isCurrentAccent {
                        WMenuButton(id: "0-palette", title: "Reset Palette", trailingIcon: "custom.paintbrush.badge.xmark") {
                            AccountStore.currentAccountAccentColorNft = nil
                            dismiss()
                        }
                    } else {
                        WMenuButton(id: "0-palette", title: "Install Palette", trailingIcon: "MenuBrush26") {
                            AccountStore.currentAccountAccentColorNft = nft
                            dismiss()
                        }
                    }
                }
            }
            .frame(minHeight: 200, alignment: .top)
            .frame(maxWidth: 220)
        }
    }
}

#if DEBUG
@available(iOS 18, *)
#Preview {
    @Previewable var viewModel = NftDetailsViewModel(nft: .sampleMtwCard, listContext: .none, navigationBarInset: 0)
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
