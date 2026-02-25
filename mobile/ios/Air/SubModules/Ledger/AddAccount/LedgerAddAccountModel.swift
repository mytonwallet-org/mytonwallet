
import Foundation
import WalletContext
import WalletCore
import OrderedCollections
import SwiftUI
import UIKit
import UIComponents
import Perception

private let START_STEPS: OrderedDictionary<StepId, StepStatus> = [
    .connect: .current,
    .openApp: .none,
    .discoveringWallets: .hidden,
]
private let log = Log("LedgerAddAccountModel")

@MainActor
@Perceptible
public final class LedgerAddAccountModel: LedgerBaseModel, @unchecked Sendable {
    
    struct DiscoveredWallet: Identifiable, @unchecked Sendable {
        var id: Int
        var displayName: String?
        var address: String
        var balance: TokenAmount
        var domainName: String?
        var status: Status
        var accountInfo: ApiLedgerAccountInfo
        
        enum Status {
            case alreadyImported, available, selected
        }
    }
    
    @PerceptionIgnored
    var currentWalletAddresses: Set<String> = []
    var discoveredWallets: [DiscoveredWallet] = []
    var isLoadingMore: Bool = false
    
    var selectedCount: Int { discoveredWallets.count(where: { $0.status == .selected }) }
    var canContinue: Bool { discoveredWallets.any { $0.status == .selected } }
    
    public init() async {
        await super.init(steps: START_STEPS)
    }
    
    deinit {
        log.info("deinit")
        task?.cancel()
    }
    
    override func performSteps() async throws {
        try await connect()
        try await openApp()
        try await discoverAccounts()
        try? await Task.sleep(for: .seconds(0.5))
        await MainActor.run {
            topWViewController()?.navigationController?.pushViewController(LedgerSelectWalletsVC(model: self), animated: true)
        }
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
        
        currentWalletAddresses = Set(
            AccountStore.accountsById.values.filter(\.isHardware).compactMap { $0.getAddress(chain: .ton) }
        )
        await requestMoreWallets() // request first batch before pushing
    }
    
    func requestMoreWallets() async {
        do {
            withAnimation(.spring) {
                isLoadingMore = true
            }
            let newDiscoveredWallets = try await Api.getLedgerWallets(chain: .ton, network: .mainnet, startWalletIndex: discoveredWallets.count, count: 5)
            try appendDiscoveredWallets(newDiscoveredWallets)
        } catch {
            topWViewController()?.showAlert(error: error)
        }
    }
    
    func appendDiscoveredWallets(_ newWallets: [ApiLedgerWalletInfo]) throws {
        let startIndex = discoveredWallets.count
        let toncoin = ApiToken.toncoin
        let peripheralID = try self.connectedIdentifier.orThrow()

        let newWallets: [DiscoveredWallet] = newWallets.enumerated().map { (idx, walletInfo) in
            let alreadyImported = currentWalletAddresses.contains(walletInfo.wallet.address)
            let title = AccountStore.accountsById.values.first(where: { $0.getAddress(chain: .ton) == walletInfo.wallet.address })?.title
            return DiscoveredWallet(
                id: startIndex + walletInfo.wallet.index,
                displayName: title,
                address: walletInfo.wallet.address,
                balance: TokenAmount(walletInfo.balance, toncoin),
                domainName: nil,
                status: alreadyImported ? .alreadyImported : walletInfo.balance > 0 ? .selected : .available,
                accountInfo: ApiLedgerAccountInfo(
                    byChain: [
                        TON_CHAIN: walletInfo.wallet
                    ],
                    driver: .hid,
                    deviceId: peripheralID.uuid.uuidString,
                    deviceName: peripheralID.name
                ),
            )
        }
        withAnimation(.spring) {
            discoveredWallets.append(contentsOf: newWallets)
            isLoadingMore = false
        }
    }
    
    func finalizeImport() async throws {
        let walletsToImport = discoveredWallets.filter { $0.status == .selected }
        var firstId: String?
        for discoveredWallet in walletsToImport {
            let accountId = try await AccountStore.importLedgerAccount(accountInfo: discoveredWallet.accountInfo)
            if firstId == nil {
                firstId = accountId
            }
        }
        if let firstId {
            _ = try await AccountStore.activateAccount(accountId: firstId)
        }
        onDone?()
    }
}
