
import Foundation
import UIKit
import SwiftUI
import UIComponents
import WalletCore
import WalletContext


final class CardAddressViewModel: ObservableObject {
    @Published var account: MAccount
    @Published var nft: ApiNft?
    
    init(account: MAccount, nft: ApiNft?) {
        self.account = account
        self.nft = nft
    }
}

final class CardAddressView: HostingView {
    
    let viewModel: CardAddressViewModel
    
    init() {
        let viewModel = CardAddressViewModel(account: DUMMY_ACCOUNT, nft: nil)
        self.viewModel = viewModel
        super.init {
            _CardAddressView(viewModel: viewModel)
        }
    }
    
    func update(currentNft: ApiNft?) {
        let account = AccountStore.account ?? DUMMY_ACCOUNT
        viewModel.account = account
        viewModel.nft = currentNft
        setNeedsLayout()
    }
}


struct _CardAddressView: View {
    
    @ObservedObject var viewModel: CardAddressViewModel
    
    var account: MAccount { viewModel.account }
    
    @StateObject private var menuContext = MenuContext()
    
    var preferrsDarkText: Bool { viewModel.nft?.metadata?.mtwCardTextType == .dark }
    
    var body: some View {
        HStack(spacing: 6) {
            AccountTypeBadge(account.type, style: .card)
            icons
            label
            chevronOrActions
        }
        .fixedSize()
        .padding(10)
        .contentShape(.rect)
        .menuSource(isEnabled: !showActions, menuContext: menuContext)
        .padding(-10)
        .foregroundStyle(Color.primary) // TODO: Gradient color
        .environment(\.colorScheme, preferrsDarkText ? .light : .dark)
        .task(id: account) {
            menuContext.verticalOffset = -8
            menuContext.minWidth = 280
            menuContext.makeConfig = makeAddressesMenuConfig
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .gesture(TapGesture().onEnded {
            if showActions {
                onCopy()
            }
        }, isEnabled: showActions)
    }
    
    var chains: [ApiChain] { account.supportedChains }
    
    @ViewBuilder
    var icons: some View {
        HStack {
            if account.isMultichain {
                Image.airBundle("MultichainIcon")
                    .resizable()
            } else if let chain = account.supportedChains.first {
                Image(uiImage: chain.image)
                    .resizable()
            }
        }
        .aspectRatio(contentMode: .fit)
        .frame(height: 16)
    }
    
    enum LabelMode {
        case multichain
        case address(String)
    }
    var labelMode: LabelMode {
        if chains.count > 1 {
            return .multichain
        } else if let firstAddress = account.firstAddress {
            return .address(firstAddress)
        } else { // error
            return .address("")
        }
    }
    
    var label: some View {
        HStack {
            switch labelMode {
            case .multichain:
                Text(lang("Multichain"))
            case .address(let address):
                Text(formatStartEndAddress(address, prefix: 6, suffix: 6))
            }
        }
        .fixedSize()
        .font(.compactMedium(size: 17))
        .opacity(0.75)
    }
    
    var showActions: Bool {
        !account.isMultichain // TODO: or domain is set
    }
    
    @ViewBuilder
    var chevronOrActions: some View {
        HStack {
            if showActions {
                HStack(spacing: 0) {
                    Image.airBundle("CardCopy")
                    Button(action: onOpenExplorer) {
                        Image.airBundle("CardGlobe")
                            .padding(.trailing, 20)
                            .padding(.vertical, 12)
                            .contentShape(.rect)
                    }
                    .padding(.trailing, -20)
                    .padding(.vertical, -12)
                }
            } else {
                Image.airBundle("ChevronDown10")
                    .offset(y: 1)
            }
        }
        .padding(.leading, -4)
        .opacity(0.75)
    }
    
    func onCopy() {
        UIPasteboard.general.string = AccountStore.account?.firstAddress
        topWViewController()?.showToast(animationName: "Copy", message: lang("Address was copied!"))
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }
    
    func onOpenExplorer() {
        if let chain = account.supportedChains.first, let address = account.addressByChain[chain.rawValue] {
            let url = ExplorerHelper.addressUrl(chain: chain, address: address)
            AppActions.openInBrowser(url)
        }
    }
}
