
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
            
            if !message.toAddress.isEmpty {
                InsetSection {
                    InsetCell {
                        TappableAddressFull(accountContext: accountContext, model: .init(chain: chain, apiAddress: message.toAddress))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, 3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } header: {
                    Text(lang(message.payloadRecipientAddress == nil ? "Receiving Address" : "Contract Address"))
                }
            }

            if let payloadRecipientAddress = message.payloadRecipientAddress {
                InsetSection {
                    InsetCell {
                        TappableAddressFull(accountContext: accountContext, model: .init(chain: chain, apiAddress: payloadRecipientAddress))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, 3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } header: {
                    Text(lang("Recipient Address"))
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

    private var hasDisplayName: Bool {
        payload.nft?.displayName != nil || payload.nftName?.nilIfEmpty != nil
    }

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
                            .textStyle(
                                .body,
                                content: hasDisplayName ? .default : .technical,
                                scaling: .dynamic
                            )
                            .lineSpacing(1)
                            .frame(minHeight: 22)
                            .lineLimit(1)
                        Text(subtitle)
                            .textStyle(.footnote, scaling: .dynamic)
                            .lineSpacing(2)
                            .padding(.top, 2)
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
            return L10n.dappTransferTokensBurn(amount: formattedAmount(
                payload.amount,
                token: TokenStore.getToken(slug: payload.slug) ?? .unknown(slug: payload.slug, chain: .ton),
                maxDecimals: 2
            ))
        case .dnsChangeRecord(let payload):
            let category = payload.record.type != "unknown" ? payload.record.type : (payload.record.key ?? "")
            if payload.record.type == "wallet", let value = payload.record.value {
                return L10n.dappDnsSetWalletPayload(domain: payload.domain, address: value)
            } else if payload.record.type == "wallet" {
                return L10n.dappDnsDeleteWalletPayload(domain: payload.domain)
            } else if let value = payload.record.value {
                return L10n.dappDnsChangeRecordPayload(category: category, domain: payload.domain, value: value)
            } else {
                return L10n.dappDnsDeleteRecordPayload(category: category, domain: payload.domain)
            }
        case .tokenBridgePaySwap(let payload):
            _ = payload
            return lang("$dapp_token_bridge_pay_swap_payload")
        case .liquidStakingDeposit:
            return lang("$dapp_liquid_staking_deposit_payload")
        case .liquidStakingVote(let payload):
            return L10n.dappLiquidStakingVotePayload(vote: String(payload.vote), votingAddress: payload.votingAddress)
        case .singleNominatorChangeValidator(let payload):
            return L10n.dappSingleNominatorChangeValidatorPayload(address: payload.address)
        case .singleNominatorWithdraw(let payload):
            return L10n.dappSingleNominatorWithdrawPayload(amount: formattedAmount(
                payload.amount,
                token: TokenStore.getNativeToken(chain: .ton),
                maxDecimals: ApiChain.ton.nativeToken.decimals
            ))
        case .vestingAddWhitelist(let payload):
            return L10n.dappVestingAddWhitelistPayload(address: payload.address)
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
}
