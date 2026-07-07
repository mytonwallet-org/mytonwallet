import Foundation
import Testing
import WalletCore

@Suite("SDK Error Handling")
struct SdkErrorHandlingTests {
    @Test
    func `unknown display error decoding preserves raw value`() throws {
        let data = Data(#""Provider exploded""#.utf8)

        let error = try JSONDecoder().decode(ApiAnyDisplayError.self, from: data)

        #expect(error == .unknown("Provider exploded"))
        #expect(error.rawValue == "Provider exploded")
        #expect(error.errorDescription == "Provider exploded")
    }

    @Test
    func `returned SDK error preserves raw unknown error`() {
        let error = SdkError.apiReturnedError(
            error: "Requests limit exceeded",
            data: #"{"error":"Requests limit exceeded"}"#
        )

        guard case .apiReturnedError(let rawError, let displayError, let data) = error else {
            Issue.record("Expected apiReturnedError")
            return
        }

        #expect(rawError == "Requests limit exceeded")
        #expect(displayError == nil)
        #expect(data == #"{"error":"Requests limit exceeded"}"#)
        #expect(error.backendMessage == "Requests limit exceeded")
        #expect(error.errorDescription == "Requests limit exceeded")
    }

    @Test
    func `returned SDK error captures known display error`() {
        let error = SdkError.apiReturnedError(error: "InvalidMnemonic", data: nil)

        guard case .apiReturnedError(let rawError, let displayError, _) = error else {
            Issue.record("Expected apiReturnedError")
            return
        }

        #expect(rawError == "InvalidMnemonic")
        #expect(displayError == .invalidMnemonic)
        #expect(error.backendMessage == "InvalidMnemonic")
    }
}
