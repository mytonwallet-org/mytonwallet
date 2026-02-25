import Foundation

public struct ApiSignDappProofResult: Sendable {
    public var signatures: [String]

    public init(signatures: [String]) {
        self.signatures = signatures
    }
}

public struct ApiSignDappProofResponse: Codable, Sendable {
    public var signatures: [String]?
    public var error: AnyCodable?

    public init(signatures: [String]? = nil, error: AnyCodable? = nil) {
        self.signatures = signatures
        self.error = error
    }
}
