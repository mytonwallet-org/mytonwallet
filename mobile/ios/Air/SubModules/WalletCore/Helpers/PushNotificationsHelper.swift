
public func normalizeNotificationTxId(_ txId: String) -> String {
    guard let splitIndex = txId.firstIndex(of: ":") else {
        return txId
    }
    let prefix = txId[..<splitIndex]
    if prefix.allSatisfy(\.isNumber) {
        return String(txId[txId.index(after: splitIndex)...])
    }
    return txId
}
