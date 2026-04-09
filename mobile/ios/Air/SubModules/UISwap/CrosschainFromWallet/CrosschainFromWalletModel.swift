import Foundation
import UIKit
import Perception
import SwiftNavigation
import UIComponents
import WalletCore
import WalletContext

private let log = Log("CrosschainFromWalletModel")
private let debounceAddressValidation: Duration = .seconds(0.250)

@Perceptible
@MainActor
final class CrosschainFromWalletModel {
    
    let sellingToken: TokenAmount
    let buyingToken: TokenAmount
    private let swapFee: MDouble
    private let networkFee: MDouble
    
    var addressInputString: String = ""
    var addressWithTrimming: String {
        get { addressInputString }
        set { addressInputString = newValue.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    
    var isAddressFocused = false
    var hasAddressError = false
    var canContinue = false

    @PerceptionIgnored
    private var validateAddressTask: Task<Void, Never>?
    @PerceptionIgnored
    private var validateObserver: ObserveToken?
    @PerceptionIgnored
    @AccountContext var account: MAccount
    
    init(
        sellingToken: TokenAmount,
        buyingToken: TokenAmount,
        swapFee: MDouble,
        networkFee: MDouble,
        accountContext: AccountContext
    ) {
        self._account = accountContext
        self.sellingToken = sellingToken
        self.buyingToken = buyingToken
        self.swapFee = swapFee
        self.networkFee = networkFee
        validateObserver = observe { [weak self] in
            guard let self else { return }
            let address = self.toAddress
            self.validateAddress(address)
        }
    }

    deinit {
        validateAddressTask?.cancel()
    }

    var toAddress: String {
        addressInputString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var infoText: String {
        hasAddressError
            ? lang("Incorrect address.")
            : lang("Please provide an address of your wallet in %blockchain% blockchain to receive bought tokens.", arg1: getChainName(buyingToken.type.chain))
    }

    var showsSuggestions: Bool {
        buyingToken.type.chain.isSupported
    }

    func applyAddress(_ address: String) {
        addressInputString = address
        isAddressFocused = false
    }

    func clearAddress() {
        addressInputString = ""
        isAddressFocused = false
    }

    func pasteAddress() {
        guard let pastedAddress = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !pastedAddress.isEmpty else { return }
        applyAddress(pastedAddress)
        endEditing()
    }

    func handleScanResult(_ result: ScanResult) {
        switch result {
        case .url:
            return
        case .address(let address, let possibleChains):
            guard possibleChains.isEmpty || possibleChains.contains(buyingToken.type.chain) else { return }
            applyAddress(address)
        }
    }
    
    func performSwap(passcode: String) async throws {
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

    private func validateAddress(_ address: String) {
        validateAddressTask?.cancel()

        guard !address.isEmpty else {
            hasAddressError = false
            canContinue = false
            return
        }

        hasAddressError = false
        canContinue = false

        let tokenSlug = buyingToken.type.slug
        validateAddressTask = Task { [weak self] in
            do {
                try await Task.sleep(for: debounceAddressValidation)
                let result = try await Api.swapCexValidateAddress(
                    params: ApiSwapCexValidateAddressParams(slug: tokenSlug, address: address)
                )
                guard !Task.isCancelled, let self else { return }
                self.hasAddressError = !result.result
                self.canContinue = result.result
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.hasAddressError = false
                self.canContinue = false
            }
        }
    }
}
