//
//  BiometricHelper.swift
//  UIPasscode
//
//  Created by Sina on 4/20/23.
//

import WalletContext
import LocalAuthentication

private let log = Log("Biometry")

public enum BiometryType {
    case touch
    case face
}

public struct BiometricHelper {
    
    /// Returns the effectively available biometry type that is ready to be used, or `nil` otherwise.
    ///
    /// This property checks all necessary conditions for biometric authentication:
    /// - Hardware support (Face ID, Optic ID, or Touch ID)
    /// - Biometric data is enrolled (e.g., face or fingerprint is registered)
    /// - Permission is granted in device settings for this app
    ///
    /// - Note: It is not necessary to add listeners for biometry type changes because the most common case
    ///   (when a user disables or enables biometrics in device settings) terminates the app. All other cases
    ///   are rare and will be considered for handling on demand.
    ///
    /// - Returns: `.face` for Face ID/Optic ID, `.touch` for Touch ID, or `nil` if biometric authentication
    ///   is not available or not ready to use.
    public static var biometryType: BiometryType? {
        getBiometryType(context: LAContext()).type
    }
    
    private struct Texts {
        static var notAvailable: String { lang("Biometric authentication not available.")}
        static var reason: String { lang("MyTonWallet uses biometric authentication to unlock and authorize transactions") }
        static var setPasscode: String { lang("Please set a passcode on your device, and then try to use biometric authentication.") }
    }
    
    private static func getBiometryType(context: LAContext) -> (type: BiometryType?, result: OperationResult) {
        var error: NSError?
        let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        let result = parseOperationResult(success: canEvaluate, error: error)
        
        if case .success = result {
            switch context.biometryType {
            case .faceID, .opticID:
                return (type: .face, result: .success)
            case .touchID:
                return (type: .touch, result: .success)
            case .none:
                fallthrough // this must not happen for .success
            @unknown default:
                logErrorWithAssertion("Unexpected biometry type \(context.biometryType)")
                return (type: nil, result: .internalError)
            }
        }
        
        return (type: nil, result: result)
    }
        
    private static var inProgress = false
    
    private static func logErrorWithAssertion(_ message: String, function: String = #function, line: Int = #line) {
        log.error("\(message, .public)", function: function, line: line)
        assertionFailure(message, line: UInt(line))
    }

    /// The result of `authenticate` call.
    public enum BiometricAuthenticationResult {
        case success
        
        /// Any canceling: by user, by system, by the app
        case canceled
        
        /// This happens when user explicitly disabled biometry for the given app,
        /// for example, tapped "Do not allow" for the first time of FaceID dialog appearance
        /// Technically, this is the same "not available" but it happens during the
        /// authorization session. We need to distinguish this to react accordingly in the UI
        case userDeniedBiometrics
        
        /// All other errors, including non-available hardware or disabled service
        /// Texts are localized and ready to be displayed to user
        case error(localizedDescription: String, title: String?)
    }
    
    @MainActor
    public static func authenticate() async -> BiometricAuthenticationResult {
        guard !inProgress else {
            logErrorWithAssertion("Only one biometric operation may be performed at a time")
            return .canceled
        }
        inProgress = true
        defer { inProgress = false }
        
        let context = LAContext()
        context.localizedFallbackTitle = "" // suppress "Enter password" user fallback on biometric mismatch
                
        // Make sure that biometry authentication is still available and properly configured
        let bt = getBiometryType(context: context)
        guard case .success = bt.result else {
            return toAuthenticationResult(bt.result)
        }
                            
        let result: OperationResult
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: Texts.reason)
            result = parseOperationResult(success: success, error: nil)
        } catch {
            result = parseOperationResult(success: false, error: error as NSError?)
        }

        // Prepare the result        
        // If the user taps "Do not allow" when prompted for Face ID/Touch ID the very first time, the system reports this as "not available".
        // At this point, true hardware absence has already been handled above, so a "not available" case here signifies user denial.
        // Note: the permission dialog is not always shown on iOS Simulator, this was confirmed at least for iOS 26.2.
        var authResult = toAuthenticationResult(result)        
        if case .notAvailable = result {
            authResult = .userDeniedBiometrics
        }        
        return authResult
    }

    // Cast internal operation result to public one, providing with localized message texts
    private static func toAuthenticationResult(_ opResult: OperationResult) -> BiometricAuthenticationResult {
        switch opResult {
        case .success:
            return .success
        case .canceled:
            return .canceled
        case .passcodeNotSet:
            return .error(localizedDescription: Texts.setPasscode, title: Texts.notAvailable)
        case let .notAvailable(localizedDescription):
            return .error(localizedDescription: localizedDescription, title: Texts.notAvailable)
        case let .otherError(localizedDescription):
            return .error(localizedDescription: localizedDescription, title: Texts.notAvailable)
        case .internalError:
            return .error(localizedDescription: Texts.notAvailable, title: nil)
        }
    }
    
    /// An internal result of a system biometric interaction. For public accessing the data is narrowed and casted to `BiometricAuthenticationResult`
    private enum OperationResult {
        case success
        case canceled
        case passcodeNotSet
        case notAvailable(_ localizedDescription: String)
        case otherError(_ localizedDescription: String)
        case internalError
    }
    
    private static func parseOperationResult(success: Bool, error: NSError?) -> OperationResult {
        if success {
            return .success
        }
        
        guard let error else {
            logErrorWithAssertion("Biometric evaluation did not succeed, but no error was reported")
            return .internalError
        }
        
        guard let laError = error as? LAError else {
            logErrorWithAssertion("Biometric evaluation did not succeed, but an unexpected error \(error) was reported")
            return .otherError(error.localizedDescription)
        }
        
        switch laError.code {
        case .biometryNotAvailable:
            // This error can indicate two situations:
            // 1. The device does not have biometric hardware or it is disabled—however, this is extremely rare on modern devices.
            //    One plausible example is running the app on macOS without biometric support (e.g., Mac mini).
            // 2. The user has explicitly disabled biometric authentication for this app in device Settings.
            return .notAvailable(error.localizedDescription)
        case .passcodeNotSet:
            return .passcodeNotSet
        case .appCancel:
            // This scenario should not occur under typical app operation (as we do not invoke invalidate()), so it's unexpected.
            // Still, treat this as a cancellation.
            logErrorWithAssertion("Unexpected biometric error \(laError)")
            return .canceled
        case .userCancel, .systemCancel:
            return .canceled
        default:
            return .otherError(error.localizedDescription)
        }
    }
}
