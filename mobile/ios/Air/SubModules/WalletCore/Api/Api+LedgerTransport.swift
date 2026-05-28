

import Foundation
import WebKit
import WalletContext

extension Api {
    
    public static func signLedgerTransaction(path: [Int32], transaction: [String: Any]) async throws -> String {
        try await bridge.callApi("signLedgerTransaction", path, AnyEncodable(dict: transaction), decoding: String.self)
    }
}
