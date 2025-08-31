
import Foundation
import WalletContext
import WalletCore
import OrderedCollections

private let START_STEPS: OrderedDictionary<StepId, StepStatus> = [
    .connect: .current,
    .openApp: .none,
    .sign: .none,
]
private let log = Log("LedgerSignModel")

public final class LedgerSignModel: LedgerBaseModel, @unchecked Sendable {
    
    public let accountId: String
    public let fromAddress: String
    public let ledger: MAccount.Ledger
    public let signData: SignData
    
    public init(accountId: String, fromAddress: String, ledger: MAccount.Ledger, signData: SignData) async {
        self.accountId = accountId
        self.fromAddress = fromAddress
        self.ledger = ledger
        self.signData = signData
        await super.init(steps: START_STEPS)
    }
    
    deinit {
        log.info("deinit")
        task?.cancel()
    }
    
    override func performSteps() async throws {
        try await connect(knownLedger: self.ledger)
        try await openApp()
        try await signAndSend()
        try? await Task.sleep(for: .seconds(0.8))
        await onDone?()
    }
    
    func signAndSend() async throws {
    
        await updateStep(.sign, status: .current)
        do {
            let pub = try await connection.getPublicKey(walletIndex: ledger.index)
            assert(pub.count == 32)
            let wallet = try await Api.addressFromPublicKey(publicKey: pub, network: .mainnet, version: LEDGER_WALLET_VERSION)
            guard wallet.address == self.fromAddress else {
                throw LedgerError.wrongFromAddress
            }
            try await _signImpl()
            await updateStep(.sign, status: .done)
        } catch {
            let errorString = (error as? LocalizedError)?.errorDescription
            await updateStep(.sign, status: .error(errorString))
            throw error
        }
    }
    
    private func _signImpl() async throws {
        
        switch signData {
        case .signTransfer(let transferOptions):
            do {
                let result = try await Api.submitTransfer(chain: .ton, options: transferOptions)
                log.info("\(result)")
            } catch {
                throw error
            }
            
        case .signDappTransfers(update: let update):
            do {
                let signedMessages = try await Api.signTransfers(
                    accountId: update.accountId,
                    messages: update.transactions.map(ApiTransferToSign.init),
                    options: .init(
                        password: nil,
                        vestingAddress: update.vestingAddress,
                        validUntil: update.validUntil,
                    )
                )
                try await Api.confirmDappRequestSendTransaction(
                    promiseId: update.promiseId,
                    data: signedMessages
                )
            } catch {
                try? await Api.cancelDappRequest(promiseId: update.promiseId, reason: error.localizedDescription)
                throw error
            }
            
        case .signLedgerProof(let promiseId, let proof):
            do {
                let accountId = try AccountStore.accountId.orThrow()
                let network = AccountStore.activeNetwork
                let index = ledger.index
                let path = APDUHelpers.getLedgerAccountPath(isTestnet: network == .testnet, workChain: 0, index: Int32(index))
                var result: Api.SignTonProofResult?
                if let proof {
                    result = try await Api.signTonProof(accountId: accountId, proof: proof, password: "")
                }
                try await Api.confirmDappRequestConnect(
                    promiseId: promiseId,
                    data: .init(
                        accountId: accountId,
                        proofSignature: result?.signature
                    )
                )
            } catch {
                try? await Api.cancelDappRequest(promiseId: promiseId, reason: error.localizedDescription)
                throw error
            }

        case .signNftTransfer(accountId: let accountId, nft: let nft, toAddress: let toAddress, comment: let comment, realFee: let realFee):
            do {
                let txId = try await Api.submitNftTransfers(
                    accountId: accountId,
                    password: "",
                    nfts: [nft],
                    toAddress: toAddress,
                    comment: comment,
                    totalRealFee: realFee
                )
                log.info("\(txId)")
            } catch {
                throw error
            }
            
        case .staking(isStaking: let isStaking, accountId: let accountId, amount: let amount, stakingState: let stakingState, realFee: let realFee):
            do {
                let txId = if isStaking {
                    try await Api.submitStake(accountId: accountId, password: "", amount: amount, state: stakingState, realFee: realFee)
                } else {
                    try await Api.submitUnstake(accountId: accountId, password: "", amount: amount, state: stakingState, realFee: realFee)
                }
                log.info("\(txId)")
            } catch {
                throw error
            }
        
        case let .submitStakingClaimOrUnlock(accountId, state, realFee):
            do {
                _ = try await Api.submitStakingClaimOrUnlock(accountId: accountId, password: "", state: state, realFee: realFee)
            } catch {
                log.error("\(error, .public)")
                throw error
            }
        }
    }
}
