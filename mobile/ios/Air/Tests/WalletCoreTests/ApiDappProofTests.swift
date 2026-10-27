import Foundation
import Testing
@testable import WalletCore

@Suite("Dapp proof responses")
struct ApiDappProofTests {
    private let signature = Data(repeating: 1, count: 64).base64EncodedString()

    @Test
    func `preserves a complete proof and its public key`() throws {
        let response = ApiSignDappProofResponse(signatures: [signature], publicKeys: ["public-key"])

        let result = try response.validatedResult(expectedSignatureCount: 1)

        #expect(result.signatures == [signature])
        #expect(result.publicKeys == ["public-key"])
    }

    @Test
    func `rejects absent empty and partial proof results`() {
        for signatures: [String]? in [nil, [], [signature]] {
            let response = ApiSignDappProofResponse(signatures: signatures)
            #expect(throws: SdkError.self) {
                try response.validatedResult(expectedSignatureCount: 2)
            }
        }
        #expect(throws: SdkError.self) {
            try ApiSignDappProofResponse(signatures: []).validatedResult(expectedSignatureCount: 0)
        }
        #expect(throws: SdkError.self) {
            try ApiSignDappProofResponse(signatures: [signature, signature]).validatedResult(expectedSignatureCount: 1)
        }
    }

    @Test(arguments: [
        "",
        String(repeating: "!", count: 88),
        Data(repeating: 1, count: 63).base64EncodedString(),
        Data(repeating: 1, count: 65).base64EncodedString(),
        Data(repeating: 1, count: 64).base64EncodedString() + "\n",
    ])
    func `rejects malformed signatures`(signature: String) {
        #expect(throws: SdkError.self) {
            try ApiSignDappProofResponse(signatures: [signature]).validatedResult(expectedSignatureCount: 1)
        }
    }

    @Test(arguments: [#""InvalidPassword""#, #"{"message":"InvalidPassword"}"#])
    func `preserves SDK errors even when signatures are present`(errorJSON: String) throws {
        let json = """
        {"signatures":["\(signature)"],"error":\(errorJSON)}
        """
        let response = try JSONDecoder().decode(ApiSignDappProofResponse.self, from: Data(json.utf8))

        do {
            _ = try response.validatedResult(expectedSignatureCount: 1)
            Issue.record("Expected the signing error")
        } catch let error as SdkError {
            #expect(error.backendMessage == "InvalidPassword")
        }
    }
}
