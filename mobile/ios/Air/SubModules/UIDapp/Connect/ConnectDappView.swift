
import SwiftUI
import UIKit
import UIPasscode
import UIComponents
import WalletCore
import WalletContext
import Ledger
import Perception

private let topMargin = 40.0

enum ConnectDappViewOrPlaceholderContent {
    case placeholder(TonConnectPlaceholder)
    case connectDapp(ConnectDappView)
}

struct ConnectDappViewOrPlaceholder: View {
    
    let viewModel: ConnectViewModel
    
    var body: some View {
        WithPerceptionTracking {
            switch content {
            case .placeholder(let view):
                view
                    .transition(.opacity.animation(.default))
            case .connectDapp(let view):
                view
                    .transition(.opacity.animation(.default))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
    
    var content: ConnectDappViewOrPlaceholderContent {
        if let update = viewModel.update {
            return .connectDapp(ConnectDappView(viewModel: viewModel, update: update))
        } else {
            return .placeholder(TonConnectPlaceholder(
                account: viewModel.accountViewModel.account,
                connectionType: .connect,
            ))
        }
    }
}

struct ConnectDappView: View {
    
    let viewModel: ConnectViewModel
    var update: ApiUpdate.DappConnect
    
    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 24) {
                HeaderView(dapp: update.dapp)
                    .padding(.top, 40)
                SelectSection(viewModel: viewModel)
                if viewModel.isDisabled {
                    WarningView(text: lang("Action is not possible on a view-only wallet."))
                        .padding(.horizontal, 20)
                        .padding(.top, -8)
                }
                ConnectButton(viewModel: viewModel)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea(edges: .top)
        }
    }
}

private struct HeaderView: View {
    
    var dapp: ApiDapp
    
    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 16) {
                HeaderDappIcon(dapp: dapp)
                VStack(spacing: 4) {
                    Text(lang("$connect_dapp_title", arg1: dapp.name))
                        .airFont24h32(weight: .semibold)
                    Text(dapp.displayUrl)
                        .font17h22()
                        .foregroundStyle(.tint)
                }
                .padding(.horizontal, 8)
            }
            Text(lang("$connect_dapp_description"))
        }
        .padding(.horizontal, 32)
        .multilineTextAlignment(.center)
    }
}

private struct SelectSection: View {
    
    let viewModel: ConnectViewModel
    
    var body: some View {
        WithPerceptionTracking {
            InsetSection {
                InsetButtonCell(horizontalPadding: 12, verticalPadding: 10, action: viewModel.onSelectWallet) {
                    HStack {
                        AccountListCell(viewModel: viewModel.accountViewModel, isReordering: false, showCurrentAccountHighlight: false)
                        InsetListChevron()
                    }
                }
            } header: {
                Text(lang("Selected Wallet"))
                    .padding(.top, 6)
                    .padding(.bottom, 5)
            }
        }
    }
}

private struct ConnectButton: View {
    
    let viewModel: ConnectViewModel
    
    var body: some View {
        WithPerceptionTracking {
            Button(action: viewModel.onConnectWallet) {
                Text(lang("Connect Wallet"))
            }
            .disabled(viewModel.isDisabled)
            .buttonStyle(.airPrimary)
            .padding(.horizontal, 30)
            .padding(.bottom, 36)
        }
    }
}
