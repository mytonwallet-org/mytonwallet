
import Foundation
import WalletContext
import WalletCore
import OrderedCollections

private let START_STEPS: OrderedDictionary<StepId, StepStatus> = [
    .connect: .current,
    .openApp: .none,
    .discoveringWallets: .hidden,
]
private let log = Log("LedgerAddAccountModel")

public final class LedgerAddAccountModel: LedgerBaseModel, @unchecked Sendable {
    
    public init() async {
        await super.init(steps: START_STEPS)
    }
    
    deinit {
        log.info("deinit")
        task?.cancel()
    }
    
    override func performSteps() async throws {
        try await connect(knownLedger: nil)
        try await openApp()
        try await discoverAccounts()
        try? await Task.sleep(for: .seconds(1.0))
        await onDone?()
    }
    
    func discoverAccounts() async throws {
        await updateStep(.discoveringWallets, status: .current)
        do {
            try await _discoverAccountsImpl()
            await updateStep(.discoveringWallets, status: .done)
        } catch {
            log.error("\(error)")
            let errorString = (error as? LocalizedError)?.errorDescription
            await updateStep(.discoveringWallets, status: .error(errorString))
        }
    }
    
    func _discoverAccountsImpl() async throws {
        let peripheralID = try self.connectedIdentifier.orThrow()
        let importedHardwareAdresses: Set<String> = Set(AccountStore.allAccounts
            .filter(\.isHardware)
            .compactMap(\.tonAddress))
        var newWallets: [LedgerWalletInfo] = []
        for idx in 0... {
            do {
                let pub = try await connection.getPublicKey(walletIndex: idx)
                assert(pub.count == 32)
                let wallet = try await Api.addressFromPublicKey(publicKey: pub, network: .mainnet, version: LEDGER_WALLET_VERSION)
                if importedHardwareAdresses.contains(wallet.address) {
                    continue
                }
                let balance = try await Api.getWalletBalance(chain: .ton, network: .mainnet, address: wallet.address)
                let walletInfo = LedgerWalletInfo(
                    index: idx,
                    address: wallet.address,
                    publicKey: wallet.publicKey,
                    balance: balance,
                    version: LEDGER_WALLET_VERSION,
                    driver: .hid,
                    deviceId: peripheralID.uuid.uuidString,
                    deviceName: peripheralID.name
                )
                if balance > 0 {
                    newWallets.append(walletInfo)
                } else if newWallets.isEmpty {
                    newWallets.append(walletInfo)
                    break
                } else {
                    break
                }
                
            } catch {
                log.error("\(error)")
                throw error
            }
        }
        var firstId: String?
        for walletInfo in newWallets {
            let accountId = try await AccountStore.importLedgerWallet(walletInfo: walletInfo)
            if firstId == nil {
                firstId = accountId
            }
        }
        if let firstId {
            _ = try await AccountStore.activateAccount(accountId: firstId)
        }
    }
}
