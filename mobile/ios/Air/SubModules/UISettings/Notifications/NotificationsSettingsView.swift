
import Foundation
import SwiftUI
import UIKit
import UIComponents
import WalletContext
import WalletCore
import Perception

private let log = Log("NotificationsVC")

struct NotificationsSettingsView: View {
    
    var viewModel: NotificationsSettingsViewModel
    
    @State private var areNotificationsOn: Bool = false
    
    var body: some View {
        WithPerceptionTracking {
            InsetList(topPadding: 16, spacing: 24) {
                if viewModel.notificationsAreAllowed {
                    notificationsSection
                    walletSelectionSection
                } else {
                    enableNotificationsSection
                }
                soundsSection
                    .padding(.top, 8)
                    .padding(.bottom, 48)
            }
            .onChange(of: areNotificationsOn) { areNotificationsOn in
                withAnimation {
                    if areNotificationsOn {
                        viewModel.toggledOn()
                    } else {
                        viewModel.toggledOff()
                    }
                }
            }
            .onChange(of: viewModel.selectedCount) { _ in
                withAnimation {
                    areNotificationsOn = viewModel.selectedCount > 0
                }
            }
            .onAppear {
                areNotificationsOn = viewModel.selectedCount > 0
            }
            .task {
                for await _ in NotificationCenter.default.notifications(named: UIScene.didActivateNotification) {
                    viewModel.checkIfNotificationsAreEnabled()
                }
            }
            .onChange(of: viewModel.playSounds) { playSounds in
                Task {
                    AppStorageHelper.sounds = playSounds
                    try await GlobalStorage.syncronize()
                }
            }
        }
    }
    
    @ViewBuilder
    var enableNotificationsSection: some View {
        InsetSection {
            InsetCell {
                Text(lang("Notifications are disabled"))
                    .font(.system(size: 17, weight: .semibold))
            }
            InsetButtonCell(alignment: .leading, action: goToSettings) {
                Text(lang("Enable in Settings"))
            }
        }
        .transition(.opacity)
    }
    
    func goToSettings() {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
    
    var notificationsSection: some View {
        InsetSection {
            InsetCell(verticalPadding: 0) {
                HStack {
                    Text(lang("Push Notifications"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Toggle(lang("Push Notifications"), isOn: $areNotificationsOn)
                        .labelsHidden()
                }
                .frame(minHeight: 44)
            }
        }
    }
    
    @ViewBuilder
    var walletSelectionSection: some View {
        @Perception.Bindable var viewModel = viewModel
        InsetSection {
            ForEach($viewModel.selectableAccounts) { $selectableAccount in
                WithPerceptionTracking {
                    SelectableAccountRow(
                        selectableAccount: $selectableAccount,
                        canSelectAnother: viewModel.canSelectAnother
                    )
                }
            }
        } header: {
            Text(lang("Select up to %count% wallets for notifications", arg1: "\(MAX_PUSH_NOTIFICATIONS_ACCOUNT_COUNT)"))
        }
    }
    
    @ViewBuilder
    var soundsSection: some View {
        @Perception.Bindable var viewModel = viewModel
        InsetSection {
            InsetCell(verticalPadding: 0) {
                HStack {
                    Text(lang("Play Sounds"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Toggle(lang("Play Sounds"), isOn: $viewModel.playSounds)
                        .labelsHidden()
                }
                .frame(minHeight: 44)
            }
        }
    }
}


struct SelectableAccountRow: View {
    
    @Binding var selectableAccount: SelectableAccount
    var canSelectAnother: Bool
    
    var account: MAccount { selectableAccount.account }
    var isEnabled: Bool { selectableAccount.isSelected || canSelectAnother }
    
    var body: some View {
        InsetButtonCell(horizontalPadding: 0, verticalPadding: 9, action: onTap) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(Color(WTheme.tint))
                .tint(Color(WTheme.tint))
        }
        .allowsHitTesting(isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .animation(.spring, value: isEnabled)
    }
    
    var content: some View {
        HStack(spacing: 0) {
            Checkmark(isOn: selectableAccount.isSelected)
                .padding(.horizontal, 20)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(account.displayName)
                        .font(.system(size: 16, weight: .medium))
                    AccountTypeBadge(account.type)
                        .foregroundStyle(Color.air.secondaryLabel)
                }
                let firstAddress = account.firstAddress
                Text("\(formatStartEndAddress(firstAddress))")
                    .font14h18()
                    .fixedSize()
                    .foregroundStyle(Color.air.secondaryLabel)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 32)
        .foregroundStyle(Color.primary)
    }
    
    func onTap() {
        selectableAccount.isSelected.toggle()
    }
}
