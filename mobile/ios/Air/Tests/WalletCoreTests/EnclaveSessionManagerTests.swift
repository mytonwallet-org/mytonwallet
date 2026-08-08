import Foundation
import Testing
@testable import NativeEnclave

@Suite("Enclave Session Manager")
struct EnclaveSessionManagerTests {
    @Test
    func `short session grants exactly its configured number of uses`() async throws {
        let manager = SessionManager()
        let masterKey = Data(repeating: 7, count: 32)
        let result = try await manager.createSession(
            authType: .passcode,
            isLong: false,
            usageCount: 2,
            masterKey: masterKey
        )

        let firstRead = try await manager.validateSessionAndGetMasterKey(
            token: result.token,
            invalidateShortSession: true
        )
        let secondRead = try await manager.validateSessionAndGetMasterKey(
            token: result.token,
            invalidateShortSession: true
        )

        #expect(firstRead == masterKey)
        #expect(secondRead == masterKey)
        await #expect(throws: EnclaveError.self) {
            _ = try await manager.validateSessionAndGetMasterKey(
                token: result.token,
                invalidateShortSession: true
            )
        }
    }

    @Test
    func `concurrent reads cannot exceed the short session budget`() async throws {
        let manager = SessionManager()
        let result = try await manager.createSession(
            authType: .biometric,
            isLong: false,
            usageCount: 3,
            masterKey: Data(repeating: 3, count: 32)
        )

        let successfulReads = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    do {
                        _ = try await manager.validateSessionAndGetMasterKey(
                            token: result.token,
                            invalidateShortSession: true
                        )
                        return true
                    } catch {
                        return false
                    }
                }
            }

            var count = 0
            for await succeeded in group where succeeded {
                count += 1
            }
            return count
        }

        #expect(successfulReads == 3)
    }
}
