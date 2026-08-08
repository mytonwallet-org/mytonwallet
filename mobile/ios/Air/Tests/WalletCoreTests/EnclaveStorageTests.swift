import Foundation
import Testing
@testable import NativeEnclave

@Suite("Enclave Storage", .serialized)
struct EnclaveStorageTests {
    @Test
    func `passcode credential round trips as one payload`() throws {
        let credential = PasscodeCredential(
            salt: Data(repeating: 1, count: 16),
            wrappedMasterKey: "wrapped"
        )
        let encoded = try JSONEncoder().encode(credential)
        let decoded = try JSONDecoder().decode(PasscodeCredential.self, from: encoded)

        #expect(decoded == credential)
    }
}
