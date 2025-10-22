//
//  SizePreference.swift
//  MyTonWalletAir
//
//  Created by nikstar on 11.10.2025.
//

import SwiftUI

public enum SizePreference: PreferenceKey {
    
    public static var defaultValue: [String: CGSize] = [:]
    
    public static func reduce(value: inout [String: CGSize], nextValue: () -> [String: CGSize]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

