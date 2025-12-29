//
//  TokenStore.swift
//  MyTonWalletAir
//
//  Created by Sina on 10/30/24.
//

import Foundation
import WalletContext
import Perception
import Dependencies


@Perceptible
public final class SensitiveData {
    
    static let shared = SensitiveData()
    
    public var isHidden: Bool {
        get {
            access(keyPath: \.isHidden)
            return AppStorageHelper.isSensitiveDataHidden
        }
        set {
            withMutation(keyPath: \.isHidden) {
                AppStorageHelper.isSensitiveDataHidden = newValue
            }
        }
    }
}

extension SensitiveData: DependencyKey {
    public static let liveValue: SensitiveData = .shared
}

extension DependencyValues {
    public var sensitiveData: SensitiveData {
        get { self[SensitiveData.self] }
        set { self[SensitiveData.self] = newValue }
    }
}
