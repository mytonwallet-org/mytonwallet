
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
    public let signData: SignData
    
    public init(accountId: String, fromAddress: String, signData: SignData) async {
        self.accountId = accountId
        self.fromAddress = fromAddress
        self.signData = signData
        await super.init(steps: START_STEPS)
    }
    
    deinit {
        log.info("deinit")
        task?.cancel()
    }
    
    override func performSteps() async throws {
        try await connect()
        try await openApp()
        try await signAndSend()
        try? await Task.sleep(for: .seconds(0.8))
        await onDone?()
    }
    
    func signAndSend() async throws {
    
        await updateStep(.sign, status: .current)
        do {
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
                let account = AccountStore.get(accountId: update.accountId)
                let chain = update.operationChain
                let address = account.getAddress(chain: chain) ?? ""
                let dappChain = ApiDappSessionChain(chain: chain, address: address, network: account.network)
                let signedMessages = try await Api.signDappTransfers(
                    dappChain: dappChain,
                    accountId: update.accountId,
                    messages: update.transactions.map(ApiTransferToSign.init),
                    options: .init(
                        password: nil,
                        vestingAddress: update.vestingAddress,
                        validUntil: update.validUntil,
                        isLegacyOutput: update.isLegacyOutput,
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
                var signatures: [String]? = nil
                if let proof {
                    let account = AccountStore.get(accountId: accountId)
                    let tonAddress = account.getAddress(chain: .ton) ?? ""
                    let dappChains = [
                        ApiDappSessionChain(chain: .ton, address: tonAddress, network: account.network),
                    ]
                    let result = try await Api.signDappProof(dappChains: dappChains, accountId: accountId, proof: proof, password: nil)
                    signatures = result.signatures
                }
                try await Api.confirmDappRequestConnect(
                    promiseId: promiseId,
                    data: .init(
                        accountId: accountId,
                        proofSignatures: signatures
                    )
                )
            } catch {
                try? await Api.cancelDappRequest(promiseId: promiseId, reason: error.localizedDescription)
                throw error
            }

        case .signNftTransfer(chain: let chain, accountId: let accountId, nft: let nft, toAddress: let toAddress, comment: let comment, realFee: let realFee, let isNftBurn):
            do {
                let result = try await Api.submitNftTransfers(
                    chain: chain,
                    accountId: accountId,
                    password: nil,
                    nfts: [nft],
                    toAddress: toAddress,
                    comment: comment,
                    totalRealFee: realFee,
                    isNftBurn: isNftBurn,
                )
                if let error = result.error {
                    throw BridgeCallError(message: error, payload: nil)
                }
            } catch {
                throw error
            }
            
        case .staking(isStaking: let isStaking, accountId: let accountId, amount: let amount, stakingState: let stakingState, realFee: let realFee):
            do {
                let txId = if isStaking {
                    try await Api.submitStake(accountId: accountId, password: nil, amount: amount, state: stakingState, realFee: realFee)
                } else {
                    try await Api.submitUnstake(accountId: accountId, password: nil, amount: amount, state: stakingState, realFee: realFee)
                }
                log.info("\(txId)")
            } catch {
                throw error
            }
        
        case let .submitStakingClaimOrUnlock(accountId, state, realFee):
            do {
                _ = try await Api.submitStakingClaimOrUnlock(accountId: accountId, password: nil, state: state, realFee: realFee)
            } catch {
                log.error("\(error, .public)")
                throw error
            }
        }
    }
}
