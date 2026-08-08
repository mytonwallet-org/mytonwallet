import ProtectedAction
import WalletContext
import WalletCore

extension ProtectedAction where HeaderView == DappHeaderView, Result == ApiMfaProtectedResult {
    static func signData(
        account: MAccount,
        accountContext: AccountContext,
        update: ApiUpdate.DappSignData,
        onCommitted: @escaping @MainActor () -> Void
    ) -> Self {
        Self(
            account: account,
            software: .single { enclaveToken in
                try await TonConnect.shared.submitSignData(update: update, enclaveToken: enclaveToken)
            },
            hardware: nil,
            confirmation: .init(
                title: lang("Sign Data"),
                header: DappHeaderView(
                    dapp: update.dapp,
                    accountContext: accountContext,
                    compactAction: lang("Sign Data")
                )
            ),
            completion: .finish { _ in
                onCommitted()
            }
        )
    }
}

extension ProtectedAction where HeaderView == DappHeaderView, Result == DappSendSubmitResult {
    static func sendDappTransactions(
        account: MAccount,
        accountContext: AccountContext,
        request: ApiUpdate.DappSendTransactions,
        onCommitted: @escaping @MainActor () -> Void
    ) -> Self {
        Self(
            account: account,
            software: .single { enclaveToken in
                try await TonConnect.shared.submitSendTransactions(request: request, enclaveToken: enclaveToken)
            },
            hardware: .custom { _ in
                let signedMessages: [ApiSignedTransfer]
                do {
                    let chain = request.operationChain
                    guard let address = account.getAddress(chain: chain) else {
                        throw DisplayError(text: lang("No matching chains"))
                    }
                    guard request.transactions.allSatisfy({ $0.chain == nil || $0.chain == chain }) else {
                        throw DisplayError(text: lang("Unexpected error"))
                    }
                    let dappChain = ApiDappSessionChain(
                        chain: chain,
                        address: address,
                        network: account.network
                    )
                    signedMessages = try await Api.signDappTransfers(
                        dappChain: dappChain,
                        accountId: request.accountId,
                        messages: request.transactions.map { ApiTransferToSign($0, chain: chain) },
                        options: .init(
                            enclaveToken: nil,
                            vestingAddress: request.vestingAddress,
                            validUntil: request.validUntil,
                            isLegacyOutput: request.isLegacyOutput
                        )
                    )
                } catch {
                    return actionSubmissionFailure(for: error)
                }
                do {
                    try await Api.confirmDappRequestSendTransaction(
                        promiseId: request.promiseId,
                        data: signedMessages
                    )
                    return .committed(ActionSubmissionReceipt())
                } catch {
                    return .indeterminate(error: error, receipt: nil)
                }
            },
            confirmation: .init(
                title: lang("Confirm Sending"),
                header: DappHeaderView(
                    dapp: request.dapp,
                    accountContext: accountContext,
                    compactAction: compactTransactionSummary(request)
                )
            ),
            completion: .finish { _ in
                onCommitted()
            }
        )
    }

    private static func compactTransactionSummary(
        _ request: ApiUpdate.DappSendTransactions
    ) -> String {
        guard request.shouldHideTransfers != true else {
            return lang("Send")
        }
        guard request.transactions.count == 1, let transaction = request.transactions.first else {
            return lang("$many_transactions", arg1: request.transactions.count)
        }

        var subjects = transaction.displayedAmounts(
            chain: request.operationChain,
            includeNativeFee: false
        )
        .map { $0.formatted(.defaultAdaptive) }
        if transaction.isNftTransferPayload {
            subjects.insert(lang("%amount% NFTs", arg1: 1), at: 0)
        }
        let subject = subjects.joined(separator: " + ").nilIfEmpty ?? lang("Send")
        return "\(subject) \(lang("to")) \(formatStartEndAddress(transaction.displayedToAddress))"
    }
}

extension ProtectedAction where HeaderView == DappHeaderView, Result == DappConnectSubmitResult {
    static func connectDapp(
        account: MAccount,
        accountContext: AccountContext,
        update: ApiUpdate.DappConnect,
        resolver: ConnectRequestResolver,
        onCommitted: @escaping @MainActor () -> Void
    ) -> Self {
        Self(
            account: account,
            software: .custom { enclaveToken in
                do {
                    let result = try await TonConnect.shared.prepareConnect(
                        request: update,
                        accountId: account.id,
                        enclaveToken: enclaveToken,
                        resolver: resolver
                    )
                    if result.mfaRequestHash != nil {
                        return .requiresMfa(result)
                    }
                    return .resolved(await result.resolveConfirmation())
                } catch {
                    // Proof signing and MFA-request creation only prepare Connect. Until the
                    // resolver claims confirmation, retrying the dapp request remains safe.
                    return .resolved(.notCommitted(error))
                }
            },
            hardware: .custom { _ in
                let signatures: [String]?
                do {
                    if let proof = update.proof {
                        guard let tonAddress = account.getAddress(chain: .ton) else {
                            throw DisplayError(text: lang("No matching chains"))
                        }
                        let dappChains = [
                            ApiDappSessionChain(
                                chain: .ton,
                                address: tonAddress,
                                network: account.network
                            ),
                        ]
                        let result = try await Api.signDappProof(
                            dappChains: dappChains,
                            accountId: account.id,
                            proof: proof,
                            enclaveToken: nil
                        )
                        signatures = result.signatures
                    } else {
                        signatures = nil
                    }
                } catch {
                    return .notCommitted(error)
                }
                let result = DappConnectSubmitResult(
                    accountId: account.id,
                    proofSignatures: signatures,
                    mfaRequestHash: nil,
                    resolver: resolver
                )
                return await result.resolveConfirmation()
            },
            confirmation: .init(
                title: lang("Confirm Connect"),
                header: DappHeaderView(
                    dapp: update.dapp,
                    accountContext: accountContext,
                    compactAction: lang("Connect")
                ),
                presentationStyle: .sheet,
                biometricPolicy: .beforePresentation
            ),
            completion: .finish { _ in
                onCommitted()
            }
        )
    }
}

extension ProtectedAction where HeaderView == WalletConnectPayAuthHeaderView, Result == ApiSignDappTransfersResult {
    static func walletConnectPayTransaction(
        account: MAccount,
        accountContext: AccountContext,
        request: ApiUpdate.WalletConnectPaySignTransaction,
        submit: @escaping (ApiUpdate.WalletConnectPaySignTransaction, EnclaveToken?) async throws -> ApiSignDappTransfersResult,
        onCommitted: @escaping @MainActor () -> Void
    ) -> Self {
        Self(
            account: account,
            software: .single { enclaveToken in
                try await submit(request, enclaveToken)
            },
            hardware: nil,
            confirmation: .init(
                title: lang("Confirm Sending"),
                header: WalletConnectPayAuthHeaderView(
                    merchant: request.merchant,
                    paymentContext: WalletConnectPayPaymentContext(
                        paymentInfo: request.paymentInfo,
                        paymentOption: request.paymentOption
                    ),
                    accountContext: accountContext
                ),
                prefersNavigationTitleWithCustomHeader: true
            ),
            completion: .handoff { _ in
                onCommitted()
            }
        )
    }
}

extension ProtectedAction where HeaderView == WalletConnectPayAuthHeaderView, Result == ApiMfaProtectedResult {
    static func walletConnectPaySignData(
        account: MAccount,
        accountContext: AccountContext,
        update: ApiUpdate.WalletConnectPaySignData,
        submit: @escaping (ApiUpdate.WalletConnectPaySignData, EnclaveToken?) async throws -> ApiMfaProtectedResult,
        onCommitted: @escaping @MainActor () -> Void
    ) -> Self {
        Self(
            account: account,
            software: .single { enclaveToken in
                try await submit(update, enclaveToken)
            },
            hardware: nil,
            confirmation: .init(
                title: lang("Confirm Sending"),
                header: WalletConnectPayAuthHeaderView(
                    merchant: update.merchant,
                    paymentContext: WalletConnectPayPaymentContext(
                        paymentInfo: update.paymentInfo,
                        paymentOption: update.paymentOption
                    ),
                    accountContext: accountContext
                ),
                prefersNavigationTitleWithCustomHeader: true
            ),
            completion: .handoff { _ in
                onCommitted()
            }
        )
    }
}
