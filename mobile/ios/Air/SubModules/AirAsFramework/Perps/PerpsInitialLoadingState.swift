/// A read-only screen shows stale loading only until it first presents fresh data.
struct PerpsInitialLoadingState {
    private var hasPresentedFreshData = false

    mutating func update(isStale: Bool, hasData: Bool) -> Bool {
        guard hasData else {
            hasPresentedFreshData = false
            return isStale
        }
        if !isStale { hasPresentedFreshData = true }
        return isStale && !hasPresentedFreshData
    }
}
