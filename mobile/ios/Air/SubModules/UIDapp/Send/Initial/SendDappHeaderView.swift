
import SwiftUI
import UIKit
import UIPasscode
import UIComponents
import WalletCore
import WalletContext
import Kingfisher

struct SendDappHeaderView: View {
    
    var dapp: ApiDapp
    var transactionsCount: Int
    var account: MAccount
    var isDangerous: Bool
    
    var showWarning: Bool { dapp.isUrlEnsured != true }
    
    var body: some View {
        VStack(spacing: 16) {
            icon
            VStack(spacing: 8) {
                title
                transfer
            }
        }
        .padding(.top, 32)
    }
    
    var icon: some View {
        KFImage(URL(string: dapp.iconUrl))
            .resizable()
            .frame(width: 64, height: 64)
            .background(Color(WTheme.secondaryFill))
            .clipShape(.rect(cornerRadius: 16))
    }

    var title: some View {
        // todo localization - "Confirm %lld Actions"
        Text(lang("Confirm Action"))
            .font(.system(size: 24, weight: .semibold))
    }
    
    @ViewBuilder
    var transfer: some View {
        let wallet = Text(account.displayName)
            .foregroundColor(.secondary)
        let chevron = Text("›")
            .foregroundColor(.secondary)
        let dapp = Text(dapp.displayUrl)
            .foregroundColor(Color(WTheme.tint))
        if showWarning {
            let warning = Text(Image(systemName: "exclamationmark.circle.fill"))
                .foregroundColor(Color.orange)
                .fontWeight(.bold)
            Text("\(wallet) \(chevron) \(dapp) \(warning)")
                .imageScale(.small)
        } else {
            Text("\(wallet) \(chevron) \(dapp)")
        }
    }
}
