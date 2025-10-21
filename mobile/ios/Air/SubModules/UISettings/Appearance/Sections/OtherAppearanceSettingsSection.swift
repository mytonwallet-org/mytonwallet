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
    @State private var color = Color.air.tint
    
    var body: some View {
        InsetSection {
            InsetCell(verticalPadding: 0) {
                HStack {
                    Text(lang("Enable Animations"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack {
                        Toggle(lang("Enable Animations"), isOn: $animationEnabled)
                            .labelsHidden()
                            .tint(color)
                            .transition(.opacity.animation(.default))
                            .id(color) // bug: as of iOS 26 color changes without animation without id trick
                    }
                }
                .frame(minHeight: 44)
            }
        } header: {
            Text(lang("Other"))
        }
        .onChange(of: animationEnabled) { animationEnabled in
            Task {
                AppStorageHelper.animations = animationEnabled
                try await GlobalStorage.syncronize()
            }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .updateTheme) {
                withAnimation(.default) {
                    color = Color.air.tint
                }
            }
        }
    }
}
