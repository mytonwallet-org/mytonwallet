import Foundation

public struct ApiSignDappProofResult: Sendable {
    public var signatures: [String]
    public var publicKeys: [String]?

    public init(signatures: [String], publicKeys: [String]?) {
        self.signatures = signatures
        self.publicKeys = publicKeys
    }
}

public struct ApiSignDappProofResponse: Codable, Sendable {
    public var signatures: [String]?
    public var publicKeys: [String]?
    public var error: AnyCodable?

    public init(signatures: [String]? = nil, publicKeys: [String]? = nil, error: AnyCodable? = nil) {
        self.signatures = signatures
        self.publicKeys = publicKeys
        self.error = error
    }
}
