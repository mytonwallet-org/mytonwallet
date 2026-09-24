import Foundation
import Testing
import WalletContext
@testable import NativeEnclave

@Suite("Enclave Session Manager")
struct EnclaveSessionManagerTests {
    @Test(arguments: [AuthType.passcode, .biometric])
    func `remembered authentication uses a separate token for exactly five minutes`(authType: AuthType) async throws {
        let now = UnfairLock<Int64>(initialState: 1_000)
        let manager = SessionManager(now: { now.withLock { $0 } })
        let key = Data(repeating: 7, count: 32)
        let requested = try await manager.createSession(
            authType: authType, isLong: false, remember: true, masterKey: key
        )
        let remembered = try #require(await manager.rememberedSession())
        #expect(requested.validUntil == 0)
        #expect(remembered.token != requested.token)
        #expect(remembered.validUntil == 301_000)

        #expect(try await manager.validateSessionAndGetMasterKey(
            token: requested.token, invalidateShortSession: true
        ) == key)
        await #expect(throws: EnclaveError.self) {
            _ = try await manager.validateSessionAndGetMasterKey(token: requested.token, invalidateShortSession: true)
        }

        for elapsed: Int64 in [0, 100_000, 299_999] {
            now.withLock { $0 = 1_000 + elapsed }
            let current = await manager.rememberedSession()
            #expect(current?.token == remembered.token)
            #expect(current?.validUntil == remembered.validUntil)
            #expect(try await manager.validateSessionAndGetMasterKey(
                token: remembered.token, invalidateShortSession: true
            ) == key)
        }

        now.withLock { $0 = remembered.validUntil }
        await #expect(throws: EnclaveError.self) {
            _ = try await manager.validateSessionAndGetMasterKey(token: remembered.token, invalidateShortSession: false)
        }
        #expect(await manager.rememberedSession() == nil)
    }

    @Test(arguments: [AuthType.passcode, .biometric], [1, 3])
    func `one shot authorization survives a slow Add Wallet flow and keeps its usage budget`(
        authType: AuthType, usageCount: Int
    ) async throws {
        let now = UnfairLock<Int64>(initialState: 1_000)
        let manager = SessionManager(now: { now.withLock { $0 } })
        let key = Data(repeating: 7, count: 32)
        let requested = try await manager.createSession(
            authType: authType, isLong: false, usageCount: usageCount, remember: true, masterKey: key
        )
        let remembered = try #require(await manager.rememberedSession())

        now.withLock { $0 += 10 * 60 * 1_000 }
        #expect(await manager.rememberedSession() == nil)
        await #expect(throws: EnclaveError.self) {
            _ = try await manager.validateSessionAndGetMasterKey(token: remembered.token, invalidateShortSession: true)
        }
        #expect(requested.validUntil == 0)
        for _ in 0..<usageCount {
            #expect(try await manager.validateSessionAndGetMasterKey(
                token: requested.token, invalidateShortSession: true
            ) == key)
        }
        await #expect(throws: EnclaveError.self) {
            _ = try await manager.validateSessionAndGetMasterKey(token: requested.token, invalidateShortSession: true)
        }
    }

    @Test
    func `operation sessions are never discovered as remembered authorization`() async throws {
        let manager = SessionManager()
        for isLong in [false, true] {
            _ = try await manager.createSession(
                authType: .passcode, isLong: isLong, masterKey: Data(repeating: 1, count: 32)
            )
        }
        #expect(await manager.rememberedSession() == nil)
    }

    @Test(arguments: [Int64(0), 100_000])
    func `fresh authentication selects the latest remembered token without extending old tokens`(elapsed: Int64) async throws {
        let now = UnfairLock<Int64>(initialState: 1_000)
        let manager = SessionManager(now: { now.withLock { $0 } })
        let key = Data(repeating: 1, count: 32)
        _ = try await manager.createSession(authType: .passcode, isLong: false, remember: true, masterKey: key)
        let first = try #require(await manager.rememberedSession())
        now.withLock { $0 += elapsed }
        _ = try await manager.createSession(authType: .biometric, isLong: false, remember: true, masterKey: key)
        let second = try #require(await manager.rememberedSession())
        #expect(second.token != first.token)
        #expect(second.validUntil == first.validUntil + elapsed)
        #expect(try await manager.validateSessionAndGetMasterKey(
            token: first.token, invalidateShortSession: true
        ) == key)

        now.withLock { $0 = first.validUntil }
        await #expect(throws: EnclaveError.self) {
            _ = try await manager.validateSessionAndGetMasterKey(token: first.token, invalidateShortSession: true)
        }
        #expect(await manager.rememberedSession()?.token == (elapsed > 0 ? second.token : nil))
    }

    @Test(arguments: [false, true])
    func `disabling remembering revokes internal tokens and preserves requested sessions`(isLong: Bool) async throws {
        let manager = SessionManager()
        let key = Data(repeating: 1, count: 32)
        let requested = try await manager.createSession(authType: .passcode, isLong: isLong, remember: true, masterKey: key)
        let first = try #require(await manager.rememberedSession())
        _ = try await manager.createSession(authType: .biometric, isLong: false, remember: true, masterKey: key)
        let second = try #require(await manager.rememberedSession())
        let revision = await manager.revision
        await manager.invalidateRememberedSessions()

        for token in [first.token, second.token] {
            await #expect(throws: EnclaveError.self) {
                _ = try await manager.validateSessionAndGetMasterKey(token: token, invalidateShortSession: true)
            }
        }
        #expect(try await manager.validateSessionAndGetMasterKey(
            token: requested.token, invalidateShortSession: true
        ) == key)
        await #expect(throws: CancellationError.self) {
            _ = try await manager.createSession(
                authType: .biometric, isLong: isLong, remember: true, expectedRevision: revision, masterKey: key
            )
        }
        #expect(await manager.rememberedSession() == nil)
    }

    @Test(arguments: [false, true])
    func `locking revokes requested and remembered tokens and pending authentication`(isLong: Bool) async throws {
        let manager = SessionManager()
        let key = Data(repeating: 1, count: 32)
        let requested = try await manager.createSession(authType: .passcode, isLong: isLong, remember: true, masterKey: key)
        let remembered = try #require(await manager.rememberedSession())
        let revision = await manager.revision
        await manager.clearAll()

        for token in [requested.token, remembered.token] {
            await #expect(throws: EnclaveError.self) {
                _ = try await manager.validateSessionAndGetMasterKey(token: token, invalidateShortSession: false)
            }
        }
        await #expect(throws: CancellationError.self) {
            _ = try await manager.createSession(
                authType: .passcode, isLong: isLong, remember: true, expectedRevision: revision, masterKey: key
            )
        }
        #expect(await manager.rememberedSession() == nil)
    }

    @Test
    func `credential changes invalidate long sessions and preserve unrelated one shot operations`() async throws {
        let manager = SessionManager()
        let key = Data(repeating: 1, count: 32)
        let operation = try await manager.createSession(authType: .passcode, isLong: false, masterKey: key)
        let current = try await manager.createSession(authType: .passcode, isLong: false, masterKey: key)
        let reusable = try await manager.createSession(authType: .passcode, isLong: true, remember: true, masterKey: key)
        let remembered = try #require(await manager.rememberedSession())
        let revision = await manager.revision
        await manager.invalidateShortSession(token: current.token)
        await manager.invalidateLongSessions()
        let replacement = try await manager.createSession(authType: .biometric, isLong: false, masterKey: key)

        #expect(await manager.rememberedSession() == nil)
        for token in [current.token, reusable.token, remembered.token] {
            await #expect(throws: EnclaveError.self) {
                _ = try await manager.validateSessionAndGetMasterKey(token: token, invalidateShortSession: false)
            }
        }
        for token in [operation.token, replacement.token] {
            #expect(try await manager.validateSessionAndGetMasterKey(token: token, invalidateShortSession: true) == key)
        }
        await #expect(throws: CancellationError.self) {
            _ = try await manager.createSession(
                authType: .passcode, isLong: false, remember: true, expectedRevision: revision, masterKey: key
            )
        }
    }

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

    @Test(arguments: [false, true])
    func `concurrent reads cannot exceed the short session budget`(remember: Bool) async throws {
        let manager = SessionManager()
        let result = try await manager.createSession(
            authType: .biometric,
            isLong: false,
            usageCount: 3,
            remember: remember,
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
