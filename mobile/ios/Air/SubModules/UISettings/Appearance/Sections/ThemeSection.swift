//
//  ThemeSection.swift
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
import Perception

@Perceptible final class ThemeSettingsViewModel {
    var theme: NightMode = AppStorageHelper.activeNightMode
}

struct ThemeSection: View {
    
    @State var viewModel = ThemeSettingsViewModel()
    
    var body: some View {
        WithPerceptionTracking {
            HStack(spacing: 0) {
                ThemeOption(
                    theme: .light,
                    isCurrent: viewModel.theme == .light,
                    onTap: { selectTheme(.light)}
                )
                ThemeOption(
                    theme: .system,
                    isCurrent: viewModel.theme == .system,
                    onTap: { selectTheme(.system) }
                )
                ThemeOption(
                    theme: .dark,
                    isCurrent: viewModel.theme == .dark,
                    onTap: { selectTheme(.dark)}
                )
            }
        }
    }
    
    func selectTheme(_ theme: NightMode) {
            if let window = topViewController()?.view.window as? WWindow {
                UIView.transition(with: window, duration: 0.25, options: [.transitionCrossDissolve, .allowUserInteraction]) {
                    viewModel.theme = theme
                    AppStorageHelper.activeNightMode = theme
                    window.overrideUserInterfaceStyle = theme.userInterfaceStyle
                    window.updateTheme()
                }
            }
    }
}

struct ThemeOption: View {
    
    var theme: NightMode
    var isCurrent: Bool
    var onTap: () -> ()
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                Image(uiImage: theme.image)
                    .overlay {
                        if isCurrent {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(.tint, lineWidth: 2)
                                .padding(0)
                        }
                    }
                Text(theme.text)
                    .font(.system(size: 16, weight: .medium))
                    .fixedSize()
                    .frame(height: 22)
                    .foregroundStyle(isCurrent ? .accentColor : Color.air.secondaryLabel)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
    }
}
