//
//  BiometricHelper.swift
//  UIPasscode
//
//  Created by Sina on 4/20/23.
//

import LocalAuthentication

public struct BiometricHelper {

    public static func biometricType() -> BiometricType {
        let authContext = LAContext()
        if #available(iOS 11, *) {
            let _ = authContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
            switch(authContext.biometryType) {
            case .none:
                return .none
            case .touchID:
                return .touch
            case .faceID:
                return .face
            case .opticID:
                return .face
            @unknown default:
                return .none
            }
        } else {
            return authContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) ? .touch : .none
        }
    }

    public enum BiometricType {
        case none
        case touch
        case face
    }
}
