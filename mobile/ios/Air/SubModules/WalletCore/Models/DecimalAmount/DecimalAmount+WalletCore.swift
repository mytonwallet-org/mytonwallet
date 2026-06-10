import WalletContext
import WalletCoreTypes

extension DecimalAmount where Backing == MBaseCurrency {
    public static func baseCurrency(_ amount: BigInt) -> DecimalAmount? {
        let baseCurrency = TokenStore.baseCurrency
        return DecimalAmount(amount, baseCurrency)
    }
}
