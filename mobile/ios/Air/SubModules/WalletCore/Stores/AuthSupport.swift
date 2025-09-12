
import Foundation
import WalletContext
import UIKit
import Kingfisher

public protocol AuthSupportProtocol {
    static var accountsSupportAppLock: Bool { get }
    static func verifyPassword(password: String) async throws -> Bool
}

public var AuthSupport: AuthSupportProtocol.Type = AuthSupportImpl.self

public struct AuthCooldownError: Error {
    public var waitFor: TimeInterval
}

private final class AuthSupportImpl: AuthSupportProtocol {
    
    static var accountsSupportAppLock: Bool {
        AccountStore.accountsById.values.any { $0.type.isStoredEncrypted }
    }

    static var failedLoginAttempts: Int {
        get {
            let (_, s) = KeychainStorageProvider.get(key: "failedLoginAttempts")
            if let s, let count = Int(s) {
                return count
            }
            return 0
        }
        set {
            _ = KeychainStorageProvider.set(key: "failedLoginAttempts", value: String(newValue))
        }
    }
    
    static var lastFailedAttempt: Date {
        get {
            let (_, s) = KeychainStorageProvider.get(key: "lastFailedAttempt")
            if let s, let ts = Double(s) {
                return Date(timeIntervalSince1970: ts)
            }
            return .distantPast
        }
        set {
            _ = KeychainStorageProvider.set(key: "lastFailedAttempt", value: String(newValue.timeIntervalSince1970))
        }
    }
    
    static func verifyPassword(password: String) async throws -> Bool {
        do {
            let waitFor = cooldownForNumberOfFailedAttempts(failedLoginAttempts) - Date.now.timeIntervalSince(lastFailedAttempt)
            if waitFor > 0 {
                throw AuthCooldownError(waitFor: waitFor)
            }
            if failedLoginAttempts >= 5 {
                try await Task.sleep(for: .seconds(3))
            }
            let ok = try await Api.verifyPassword(password: password)
            if ok {
                failedLoginAttempts = 0
                lastFailedAttempt = .distantPast
            } else {
                failedLoginAttempts += 1
                lastFailedAttempt = .now
                
                let waitFor = cooldownForNumberOfFailedAttempts(failedLoginAttempts)
                if waitFor > 0 {
                    throw AuthCooldownError(waitFor: waitFor)
                }
            }
            return ok
        } catch {
            // We couldn't check the password one way or another so failedLoginAttempts shouldn't be incremented.
            throw error
        }
    }
    
    private static func cooldownForNumberOfFailedAttempts(_ attempts: Int) -> TimeInterval {
        switch attempts {
        case ...4:
            0
        case 5:
            60
        case 6:
            300
        case 7:
            900
        default:
            3600
        }
    }
}
