import Foundation
import Security

public struct SessionResult: Sendable {
    public let token: EnclaveToken
    public let validUntil: Int64

    public init(token: EnclaveToken, validUntil: Int64) {
        self.token = token
        self.validUntil = validUntil
    }
}

actor SessionManager {
    private static let longSessionDurationMs: Int64 = 5 * 60 * 1000

    private struct Session {
        let validUntil: Int64
        let masterKey: Data
        var isRemembered: Bool
        var remainingUsages: Int
    }

    private var sessions: [EnclaveToken: Session] = [:]
    private var rememberedToken: EnclaveToken?
    private let now: @Sendable () -> Int64
    private(set) var revision = 0

    init(now: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }) {
        self.now = now
    }

    func createSession(
        authType: AuthType,
        isLong: Bool,
        usageCount: Int = 1,
        remember: Bool = false,
        expectedRevision: Int? = nil,
        masterKey: Data
    ) throws -> SessionResult {
        // Reject authentication that finished after its sessions were invalidated.
        if let expectedRevision, expectedRevision != revision {
            throw CancellationError()
        }
        let token = EnclaveToken("\(authType.rawValue):\(try randomHex(bytesCount: 16))")
        if remember {
            // Remembering must not change the caller's lifetime or usage budget.
            let remembered = try createSession(authType: authType, isLong: true, masterKey: masterKey)
            sessions[remembered.token]?.isRemembered = true
            rememberedToken = remembered.token
        }
        let validUntil = isLong ? now() + Self.longSessionDurationMs : 0
        sessions[token] = Session(
            validUntil: validUntil,
            masterKey: masterKey,
            isRemembered: false,
            remainingUsages: max(usageCount, 1)
        )
        if validUntil > 0 {
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(Self.longSessionDurationMs))
                await self?.removeSession(token: token)
            }
        }
        return SessionResult(token: token, validUntil: validUntil)
    }

    func rememberedSession() -> SessionResult? {
        let nowMs = now()
        sessions = sessions.filter { $0.value.validUntil == 0 || $0.value.validUntil > nowMs }
        guard let token = rememberedToken, let session = sessions[token] else {
            return nil
        }
        return SessionResult(token: token, validUntil: session.validUntil)
    }

    func invalidateRememberedSessions() {
        revision += 1
        rememberedToken = nil
        sessions = sessions.filter { !$0.value.isRemembered }
    }

    func validateSessionAndGetMasterKey(token: EnclaveToken, invalidateShortSession: Bool) throws -> Data {
        guard var session = sessions[token] else {
            throw EnclaveError.invalidSessionToken
        }

        let nowMs = now()
        if session.validUntil > 0 {
            if nowMs >= session.validUntil {
                sessions[token] = nil
                throw EnclaveError.sessionExpired
            }
            return session.masterKey
        }

        guard session.remainingUsages > 0 else {
            sessions[token] = nil
            throw EnclaveError.invalidSessionToken
        }

        if invalidateShortSession {
            session.remainingUsages -= 1
            sessions[token] = session.remainingUsages > 0 ? session : nil
        }

        return session.masterKey
    }

    func invalidateShortSession(token: EnclaveToken) {
        guard let session = sessions[token] else {
            return
        }
        if session.validUntil == 0 {
            sessions[token] = nil
        }
    }

    func invalidateLongSessions() {
        revision += 1
        rememberedToken = nil
        sessions = sessions.filter { $0.value.validUntil == 0 }
    }

    func clearAll() {
        revision += 1
        rememberedToken = nil
        sessions.removeAll()
    }

    private func removeSession(token: EnclaveToken) {
        sessions[token] = nil
    }

    private func randomHex(bytesCount: Int) throws -> String {
        var data = Data(count: bytesCount)
        let status = data.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, bytesCount, bytes.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw EnclaveError.keychainError(status)
        }
        return data.map { String(format: "%02x", $0) }.joined()
    }
}
