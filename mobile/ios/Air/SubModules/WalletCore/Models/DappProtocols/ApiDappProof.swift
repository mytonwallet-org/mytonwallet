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

    func validatedResult(expectedSignatureCount: Int) throws -> ApiSignDappProofResult {
        if let error = error?.stringValue {
            throw SdkError.apiReturnedError(error: error, context: self)
        }
        if let errorDict = error?.dictionaryValue, let message = errorDict["message"]?.stringValue {
            throw SdkError.apiReturnedError(error: message, context: errorDict)
        }
        guard error == nil,
              expectedSignatureCount > 0,
              let signatures,
              signatures.count == expectedSignatureCount,
              signatures.allSatisfy({ signature in
                  guard signature.utf8.count == 88,
                        let bytes = Data(base64Encoded: signature) else { return false }
                  return bytes.count == 64 && bytes.base64EncodedString() == signature
              }) else {
            throw SdkError.unexpected(message: "Invalid signDappProof response", context: self)
        }
        return ApiSignDappProofResult(signatures: signatures, publicKeys: publicKeys)
    }
}
