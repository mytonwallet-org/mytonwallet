
import UIComponents
import WalletContext
import WalletCore
import SwiftUI
import Perception


struct LedgerSelectWalletsView: View {
    
    var model: LedgerAddAccountModel
    var onWalletsCountChange: (Int) -> ()
    
    @State private var angle: Angle = .zero
    @State private var continueLoading = false
    
    var body: some View {
        WithPerceptionTracking {
            @Perception.Bindable var model = model
            InsetList {
                InsetSection {
                    ForEach($model.discoveredWallets, id: \.id) { $discoveredWallet in
                        WalletRow(discoveredWallet: $discoveredWallet)
                    }
                    InsetButtonCell(horizontalPadding: 0, verticalPadding: 0, action: onLoadMore) {
                        HStack(spacing: 0) {
                            if model.isLoadingMore {
                                Image.airBundle("ActivityIndicator")
                                    .renderingMode(.template)
                                    .rotationEffect(angle)
                                    .onAppear {
                                        withAnimation(.linear(duration: 0.625).repeatForever(autoreverses: false)) {
                                            angle += .radians(2 * .pi)
                                        }
                                    }

                                    .frame(width: 22)
                                    .padding(.horizontal, 20)
                                    .transition(.scale.combined(with: .opacity))
                            } else {
                                Image(systemName: "chevron.down")
                                    .frame(width: 22)
                                    .padding(.horizontal, 20)
                                    .transition(.scale.combined(with: .opacity))
                            }
                            Text(lang("Load 5 More Wallets"))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 48)
                    }
                    .allowsHitTesting(!model.isLoadingMore)
                    .opacity(!model.isLoadingMore ? 1 : 0.4)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: onContinue) {
                    Text(lang("Continue"))
                }
                .buttonStyle(.airPrimary)
                .disabled(!model.canContinue)
                .animation(.smooth(duration: 0.3), value: model.canContinue)
                .padding(.horizontal, 32)
                .padding(.vertical, 32)
                .environment(\.isLoading, continueLoading)
            }
            .onChange(of: model.selectedCount) { count in
                onWalletsCountChange(count)
            }
        }
    }
    
    func onLoadMore() {
        Task {
            await model.requestMoreWallets()
        }
    }
    
    func onContinue() {
        Task {
            do {
                continueLoading = true
                try await model.finalizeImport()
            } catch {
                continueLoading = false
                AppActions.showError(error: error)
            }
        }
    }
}


private struct WalletRow: View {
    
    @Binding var discoveredWallet: LedgerAddAccountModel.DiscoveredWallet
    
    var body: some View {
        InsetButtonCell(horizontalPadding: 0, verticalPadding: 12, action: onTap) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(Color(WTheme.tint))
                .tint(Color(WTheme.tint))
        }
        .allowsHitTesting(discoveredWallet.status != .alreadyImported)
        .opacity(discoveredWallet.status != .alreadyImported ? 1 : 0.4)
        .onTapGesture {
            onTap()
        }
    }
    
    var content: some View {
        HStack(spacing: 0) {
            Checkmark(isOn: discoveredWallet.status != .available)
                .padding(.horizontal, 20)
            VStack(alignment: .leading, spacing: 0) {
                let title = if let name = discoveredWallet.displayName {
                    name
                } else {
                    formatStartEndAddress(discoveredWallet.address)
                }
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                if discoveredWallet.displayName != nil {
                    Text("\(formatStartEndAddress(discoveredWallet.address))")
                        .foregroundStyle(.secondary)
                        .font14h18()
                        .fixedSize()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
            Text(discoveredWallet.balance.formatted(.defaultAdaptive))
                .foregroundStyle(.secondary)
                .font(.system(size: 16, weight: .regular))
                .fixedSize()
                .padding(.trailing, 12)
        }
        .frame(minHeight: 32)
        .foregroundStyle(Color.primary)
    }
    
    func onTap() {
        withAnimation(.spring) {
            if discoveredWallet.status == .available {
                discoveredWallet.status = .selected
            } else if discoveredWallet.status == .selected {
                discoveredWallet.status = .available
            }
        }
    }
}
