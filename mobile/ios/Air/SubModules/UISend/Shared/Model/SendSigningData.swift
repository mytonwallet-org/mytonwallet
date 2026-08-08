import WalletContext

struct SendSigningData: Equatable, Sendable {
    let binaryPayload: String?
    let stateInit: String?

    init(binaryPayload: String?, stateInit: String?) {
        self.binaryPayload = binaryPayload?.nilIfEmpty
        self.stateInit = stateInit?.nilIfEmpty
    }

    var isPresent: Bool {
        binaryPayload != nil || stateInit != nil
    }
}
