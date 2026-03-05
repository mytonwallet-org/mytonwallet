//
//  SizePreference.swift
//  MyTonWalletAir
//
//  Created by nikstar on 11.10.2025.
//

import SwiftUI

public enum HasScrollPreference: PreferenceKey {
    
    public static let defaultValue: Bool = false
    
    public static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

