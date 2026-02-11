//
//  OtherAppearanceSettingsSection.swift
//  MyTonWalletAir
//
//  Created by nikstar on 17.10.2025.
//

import Foundation
import SwiftUI
import UIKit
import UIComponents
import WalletContext
import WalletCore
import Flow

struct OtherAppearanceSettingsSection: View {
    
    @State private var animationEnabled: Bool = AppStorageHelper.animations
    @State private var seasonalThemingEnabled: Bool = !AppStorageHelper.isSeasonalThemingDisabled
    
    var body: some View {
        InsetSection {
            InsetCell(verticalPadding: 0) {
                HStack {
                    Text(lang("Enable Animations"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack {
                        Toggle(lang("Enable Animations"), isOn: $animationEnabled)
                            .labelsHidden()
                    }
                }
                .frame(minHeight: 44)
            }
            InsetCell(verticalPadding: 0) {
                HStack {
                    Text(lang("Enable Seasonal Theming"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack {
                        Toggle(lang("Enable Seasonal Theming"), isOn: $seasonalThemingEnabled)
                            .labelsHidden()
                    }
                }
                .frame(minHeight: 44)
            }
        } header: {
            Text(lang("Other"))
        }
        .task(id: animationEnabled) {
            do {
                try await Task.sleep(for: .seconds(0.2)) // delay so button animation doesn't get disabled inflight
                if animationEnabled != AppStorageHelper.animations {
                    AppStorageHelper.animations = animationEnabled
                    try await GlobalStorage.syncronize()
                }
            } catch {}
        }
        .task(id: seasonalThemingEnabled) {
            do {
                try await Task.sleep(for: .seconds(0.2))
                let isDisabled = !seasonalThemingEnabled
                if isDisabled != AppStorageHelper.isSeasonalThemingDisabled {
                    AppStorageHelper.isSeasonalThemingDisabled = isDisabled
                    try await GlobalStorage.syncronize()
                }
            } catch {}
        }
    }
}
