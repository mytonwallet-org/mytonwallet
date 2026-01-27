import SwiftUI
import UIKit
import UIComponents
import WalletContext
import WalletCore
import Kingfisher
import Dependencies
import Perception

struct ActivityNavigationHeader: View {
    
    var viewModel: ActivityDetailsViewModel
    
    var body: some View {
        WithPerceptionTracking {
            switch viewModel.context {
            case .normal, .external:
                NavigationHeader {
                    HStack(spacing: 4) {
                        if viewModel.isScam {
                            Image.airBundle("ScamBadge")
                        }
                        Text(viewModel.activity.displayTitleResolved)
                        ActivityStatusBadge(status: status)
                    }
                } subtitle: {
                    Text(viewModel.activity.timestamp.dateTimeString)
                }

            case .sendConfirmation, .sendNftConfirmation, .swapConfirmation, .stakeConfirmation, .unstakeConfirmation, .unstakeRequestConfirmation:
                NavigationHeader {
                    if let title = viewModel.context.displayTitle {
                        Text(title)
                    }
                }
            }
        }
    }
    
    var status: DisplayStatus? {
        switch viewModel.activity {
        case .transaction(let tx):
            if tx.status == .failed {
                return .failed
            }
        case .swap(let swap):
            if swap.cex?.status == .hold {
                return .hold
            } else if swap.cex?.status == .expired || swap.cex?.status == .overdue {
                return .expired
            } else if swap.cex?.status == .refunded {
                return .refunded
            } else if swap.cex?.status == .failed || swap.status == .failed || swap.status == .expired {
                return .failed
            } else if swap.cex?.status == .waiting && !getShouldSkipSwapWaitingStatus(activity: viewModel.activity, accountChains: viewModel.accountContext.account.supportedChains) {
                return .waitingForPayment
            }
        }
        return nil
    }
}

struct ActivityStatusBadge: View {
    
    var status: DisplayStatus?
    
    var body: some View {
        if let status {
            Text(status.displayString)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 3)
                .padding(.vertical, 2.5)
                .background {
                    RoundedRectangle(cornerRadius: 4)
                        .opacity(0.1)
                }
                .padding(.vertical, -2.5)
                .foregroundStyle(status.color)
        }
    }
}

enum DisplayStatus {
    case expired
    case refunded
    case failed
    case hold
    case waitingForPayment
}

extension DisplayStatus {
    var displayString: String {
        switch self {
        case .expired: lang("Expired")
        case .refunded: lang("Refunded")
        case .failed: lang("Failed")
        case .hold: lang("Hold")
        case .waitingForPayment: lang("Waiting For Payment")
        }
    }
    
    var color: Color {
        switch self {
        case .expired, .refunded, .failed: .red
        case .hold: .orange
        case .waitingForPayment: .secondary
        }
    }
}

/**
 * If the account has the "from" token chain, the swap "in" transaction has been performed by the app automatically
 * (see the `submitSwapCex` action code). So, if the Changelly status is "waiting", the UI shouldn't tell the user that
 * the app is waiting for their payment.
 */
func getShouldSkipSwapWaitingStatus(activity: ApiActivity, accountChains: Set<ApiChain>) -> Bool {
    if let swap = activity.swap {
        return getSwapType(from: swap.from, to: swap.to, accountChains: accountChains) != .crosschainToWallet
    }
    return false
}
