import Foundation
import UIComponents
import WalletCore
import WalletContext

private let log = Log("CrosschainFromWalletModel")

@MainActor
final class CrosschainFromWalletModel {
    
    let sellingToken: TokenAmount
    let buyingToken: TokenAmount
    private let swapFee: MDouble
    private let networkFee: MDouble
    
    var addressInputString: String = ""
    
    @AccountContext(source: .current) private var account: MAccount
    
    init(
        sellingToken: TokenAmount,
        buyingToken: TokenAmount,
        swapFee: MDouble,
        networkFee: MDouble
    ) {
        self.sellingToken = sellingToken
        self.buyingToken = buyingToken
        self.swapFee = swapFee
        self.networkFee = networkFee
    }
    
    func performSwap(toAddress: String, passcode: String) async throws {
        let cexParams = try ApiSwapCexCreateTransactionParams(
            from: sellingToken.type.swapIdentifier,
            fromAmount: MDouble(sellingToken.amount.doubleAbsRepresentation(decimals: sellingToken.decimals)),
            fromAddress: account.crosschainIdentifyingFromAddress.orThrow(),
            to: buyingToken.type.swapIdentifier,
            toAddress: toAddress,
            swapFee: swapFee,
            networkFee: networkFee
        )
        do {
            _ = try await SwapCexSupport.swapCexCreateTransaction(
                accountId: account.id,
                sellingToken: sellingToken.type,
                params: cexParams,
                shouldTransfer: true,
                passcode: passcode
            )
        } catch {
            log.error("SwapCexSupport.swapCexCreateTransaction: \(error, .public)")
            throw error
        }
    }
}
