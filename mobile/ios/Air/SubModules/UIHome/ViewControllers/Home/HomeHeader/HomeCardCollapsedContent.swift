import Foundation
import UIKit
import ContextMenuKit
import UIComponents
import WalletCore
import WalletContext
import SwiftUI
import SwiftUIIntrospect
import Perception
import Dependencies

struct HomeCardCollapsedContent: View {
    
    let headerViewModel: HomeHeaderViewModel
    let accountContext: AccountContext
    
    var progress: CGFloat { headerViewModel.collapseProgress }
    
    var spacing: CGFloat { interpolate(from: 5, to: -2, progress: progress) }
    var balanceScale: CGFloat { interpolate(from: 1, to: 17.0/40.0, progress: progress) }
    var subtitleScale: CGFloat { interpolate(from: 1, to: 13.0/17.0, progress: progress) }
    var bottomPadding: CGFloat { interpolate(from: 12, to: targetBottomPadding, progress: progress) }
    
    var targetBottomPadding: CGFloat {
        16 + (IOS_26_MODE_ENABLED ? -3 : -14)
    }
    
    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: spacing) {
                _CollapsedBalanceView(accountContext: accountContext)
                    .scaleEffect(balanceScale, anchor: .bottom)
                    .animation(.default, value: accountContext.balance)
                _CollapsedDisplayName(accountContext: accountContext)
                    .scaleEffect(subtitleScale, anchor: .top)
            }
//            .backportGeometryGroup()
            .padding(.horizontal, 80)
            .padding(.bottom, bottomPadding)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

private struct _CollapsedBalanceView: View {
    
    let accountContext: AccountContext
    
    var body: some View {
        WithPerceptionTracking {
            MtwCardBalanceView(balance: accountContext.balance, style: .homeCollaped)
                .contextMenuSource(configuration: makeBaseCurrencyMenuConfig(accountId: accountContext.accountId))
        }
    }
}

private struct _CollapsedDisplayName: View {
    
    let accountContext: AccountContext
    
    var body: some View {
        WithPerceptionTracking {
            HStack(spacing: 4) {
                if accountContext.account.isView {
                    Image.airBundle(MAccount.AddressLine.LeadingIcon.view.symbolName)
                        .imageScale(.small)
                        .accessibilityHidden(true)
                }
                Text(accountContext.account.displayName)
                    .lineLimit(1)
            }
            .foregroundStyle(.secondary)
            .font(.system(size: 17))
        }
    }
}
