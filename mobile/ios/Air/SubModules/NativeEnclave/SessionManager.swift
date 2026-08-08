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
        var remainingUsages: Int
    }

    private var sessions: [EnclaveToken: Session] = [:]

    func createSession(
        authType: AuthType,
        isLong: Bool,
        usageCount: Int = 1,
        masterKey: Data
    ) throws -> SessionResult {
        let token = EnclaveToken("\(authType.rawValue):\(try randomHex(bytesCount: 16))")
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let validUntil = isLong ? nowMs + Self.longSessionDurationMs : 0
        sessions[token] = Session(
            validUntil: validUntil,
            masterKey: masterKey,
            remainingUsages: max(usageCount, 1)
        )
        return SessionResult(token: token, validUntil: validUntil)
    }

    func validateSessionAndGetMasterKey(token: EnclaveToken, invalidateShortSession: Bool) throws -> Data {
        guard var session = sessions[token] else {
            throw EnclaveError.invalidSessionToken
        }

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
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

    func clearAll() {
        sessions.removeAll()
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
