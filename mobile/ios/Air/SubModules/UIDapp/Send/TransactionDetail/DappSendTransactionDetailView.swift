
import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext


struct DappSendTransactionDetailView: View {
    
    var accountContext: AccountContext
    var message: ApiDappTransfer
    var chain: ApiChain
    
    var isScam: Bool { message.isScam == true }
    var hasAmountSection: Bool { !message.displayedAmounts(chain: chain, includeNativeFee: false).isEmpty }
    var nftTransferPayload: ApiNftTransferPayload? { message.nftTransferPayload }
    
    var body: some View {
        InsetList(topPadding: 0, spacing: 16) {
            if isScam {
                Image.airBundle("ScamBadge")
                    .scaleEffect(1.2)
                    .offset(y: -3)
                    .padding(.bottom, 2)
            }

            if let nftTransferPayload {
                InsetSection {
                    DappSendNftPreviewRow(payload: nftTransferPayload)
                }
            }
            
            if !message.displayedToAddress.isEmpty {
                InsetSection {
                    InsetCell {
                        TappableAddressFull(accountContext: accountContext, model: .init(chain: chain, apiAddress: message.displayedToAddress))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, 3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } header: {
                    Text(lang("Receiving Address"))
                }
            }

            if hasAmountSection {
                InsetSection {
                    TransactionAmountRow(transfer: message, chain: chain)
                } header: {
                    Text(message.isNftTransferPayload ? lang("Additional Amount Sent") : lang("Amount"))
                }
            }
            
            InsetSection {
                TransactionFeeRow(transfer: message, chain: chain)
            } header: {
                Text(lang("Fee"))
            }
            
            if let payloadLabel = message.detailPayloadLabel,
               let payloadContent = message.detailPayloadContent {
                InsetSection {
                    InsetExpandableCell(content: payloadContent)
                } header: {
                    Text(payloadLabel)
                }

                if message.isDangerous {
                    SendDappWarningView()
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }
            }
        }
        .navigationBarInset(12)
    }
}

private struct DappSendNftPreviewRow: View {
    let payload: ApiNftTransferPayload

    private var title: String {
        payload.nft?.displayName
            ?? payload.nftName?.nilIfEmpty
            ?? formatStartEndAddress(payload.nftAddress)
    }

    private var subtitle: String {
        payload.nft?.collectionName?.nilIfEmpty ?? lang("NFT")
    }

    var body: some View {
        if let nft = payload.nft {
            NftPreviewRow(nft: nft)
        } else {
            InsetCell {
                HStack(spacing: 10) {
                    Image(uiImage: UIImage.airBundle("NoNftImage"))
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .padding(14)
                        .frame(width: 64, height: 64)
                        .foregroundStyle(Color.air.secondaryLabel)
                        .background(Color.air.secondaryFill)
                        .clipShape(.rect(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 0) {
                        Text(title)
                            .font17h22()
                            .lineLimit(1)
                        Text(subtitle)
                            .font13()
                            .padding(.bottom, 2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private extension ApiDappTransfer {
    var detailPayloadLabel: String? {
        switch payload {
        case .comment:
            return lang("Comment")
        case .unknown:
            return lang("Payload")
        case .nftTransfer, .tokensTransfer, .tokensTransferNonStandard, nil:
            return nil
        default:
            return lang("Nested Transaction")
        }
    }

    var detailPayloadContent: String? {
        switch payload {
        case .comment(let payload):
            return payload.comment
        case .tokensBurn(let payload):
            return lang("$dapp_transfer_tokens_burn", arg1: formattedAmount(
                payload.amount,
                token: TokenStore.getToken(slug: payload.slug) ?? unknownToken(chain: .ton),
                maxDecimals: 2
            ))
        case .dnsChangeRecord(let payload):
            let category = payload.record.type != "unknown" ? payload.record.type : (payload.record.key ?? "")
            if payload.record.type == "wallet", let value = payload.record.value {
                return lang("$dapp_dns_set_wallet_payload", arg1: payload.domain, arg2: value)
            } else if payload.record.type == "wallet" {
                return lang("$dapp_dns_delete_wallet_payload", arg1: payload.domain)
            } else if let value = payload.record.value {
                return lang("$dapp_dns_change_record_payload", arg1: category, arg2: payload.domain, arg3: value)
            } else {
                return lang("$dapp_dns_delete_record_payload", arg1: category, arg2: payload.domain)
            }
        case .tokenBridgePaySwap(let payload):
            _ = payload
            return lang("$dapp_token_bridge_pay_swap_payload")
        case .liquidStakingDeposit:
            return lang("$dapp_liquid_staking_deposit_payload")
        case .liquidStakingVote(let payload):
            return lang("$dapp_liquid_staking_vote_payload", arg1: String(payload.vote), arg2: payload.votingAddress)
        case .singleNominatorChangeValidator(let payload):
            return lang("$dapp_single_nominator_change_validator_payload", arg1: payload.address)
        case .singleNominatorWithdraw(let payload):
            return lang("$dapp_single_nominator_withdraw_payload", arg1: formattedAmount(
                payload.amount,
                token: TokenStore.getNativeToken(chain: .ton),
                maxDecimals: ApiChain.ton.nativeToken.decimals
            ))
        case .vestingAddWhitelist(let payload):
            return lang("$dapp_vesting_add_whitelist_payload", arg1: payload.address)
        case .unknown:
            return rawPayload
        case .nftTransfer, .tokensTransfer, .tokensTransferNonStandard, nil:
            return nil
        default:
            return payload?.jsonStringPretty()
        }
    }

    private func formattedAmount(_ amount: BigInt, token: ApiToken, maxDecimals: Int) -> String {
        TokenAmount(amount, token).formatted(.defaultAdaptive, maxDecimals: maxDecimals)
    }

    private func unknownToken(chain: ApiChain) -> ApiToken {
        .init(
            slug: "unknown",
            name: "[Unknown]",
            symbol: "[Unknown]",
            decimals: 9,
            chain: chain
        )
    }
}
