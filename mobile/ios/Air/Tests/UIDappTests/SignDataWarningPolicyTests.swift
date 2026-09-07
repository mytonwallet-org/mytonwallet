import Foundation
import Testing
@testable import UIDapp
import WalletCore

@Suite("Sign Data Warning Policy")
struct SignDataWarningPolicyTests {
    @Test
    func `every sign data payload shows exactly one generic trust warning`() throws {
        let payloads = [
            try payload(#"{"type":"text","text":"Message"}"#),
            try payload(#"{"type":"binary","bytes":"00"}"#),
            try payload(#"{"type":"eip712","domain":{},"types":{},"primaryType":"Message","message":{}}"#),
            try cellPayload(),
        ]

        for payload in payloads {
            #expect(signDataWarningKinds(payload: payload) == [.genericTrust])
        }
    }

    private func cellPayload() throws -> SignDataPayload {
        try payload(#"{"type":"cell","schema":"root$_ = Root;","cell":"te6ccgEBAQEAAgAAAA=="}"#)
    }

    private func payload(_ json: String) throws -> SignDataPayload {
        try JSONDecoder().decode(SignDataPayload.self, from: Data(json.utf8))
    }
}
