//
//  EarnGradient.swift
//  MyTonWalletAir
//
//  Created by nikstar on 20.07.2025.
//

import SwiftUI
import WalletContext

public let earnGradient = LinearGradient(colors: [
    Color("EarnGradientColorLeft", bundle: AirBundle),
    Color("EarnGradientColorRight", bundle: AirBundle),
], startPoint: .leading, endPoint: .trailing)
