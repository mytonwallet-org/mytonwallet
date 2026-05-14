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

            case .sendConfirmation, .sendNftConfirmation, .swapConfirmation, .stakeConfirmation, .unstakeConfirmation, .unstakeRequestConfirmation, .burnNftConfirmation:
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
            switch swap.displayStatus(accountChains: viewModel.accountContext.account.supportedChains) {
            case .hold:
                return .hold
            case .expired:
                return .expired
            case .refunded:
                return .refunded
            case .failed:
                return .failed
            case .waitingForPayment:
                return .waitingForPayment
            case .pending, .completed:
                return nil
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
