
import Foundation
import WalletContext

public struct LedgerAppInfo: Equatable, Hashable, Codable, Sendable {
    
    public let version: String
    public let isUnsafeSupported: Bool
    public let isJettonIdSupported: Bool
    
    public init(version: String) {
        self.version = version
        self.isUnsafeSupported = SemanticVersion(version) >= SemanticVersion("2.1.0")
        self.isJettonIdSupported = SemanticVersion(version) >= SemanticVersion("2.2.0")
    }
}
