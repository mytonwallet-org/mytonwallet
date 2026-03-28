extension SharedStore {
    func displayCurrency() async -> MBaseCurrency {
        await baseCurrency()
    }
}
