
import Foundation
import SwiftUI
import UIKit
import UIComponents
import WalletContext
import WalletCore

private let log = Log("AppearanceSettingsView")

struct AppearanceSettingsView: View {
    
    var navigationBarHeight: CGFloat
    var onScroll: (CGFloat) -> ()
    var tintColor: Color
    
    @Namespace private var ns
    
    var body: some View {
        InsetList(topPadding: 16, spacing: 24) {
            switchToClassicSection
                .scrollPosition(ns: ns, offset: navigationBarHeight + 16, callback: onScroll)
            themeSection
            paletteSection
            OtherAppearanceSettingsSection()
                .padding(.bottom, 48)
        }
        .navigationBarInset(navigationBarHeight)
        .coordinateSpace(name: ns)
        .animation(.default, value: tintColor)
        .tint(tintColor)
    }    
    
    var switchToClassicSection: some View {
        InsetSection {
            InsetButtonCell(alignment: .center) {
                log.info("switchToCapacitor")
                WalletContextManager.delegate?.switchToCapacitor()
            } label: {
                Text(lang("Switch to Legacy Version"))
                    .padding(.vertical, 1)
                    .foregroundStyle(Color.accentColor)
            }
        }
    }
    
    var themeSection: some View {
        InsetSection {
            InsetCell(horizontalPadding: 16, verticalPadding: 8) {
                ThemeSection()
            }
        } header: {
            Text(lang("Theme"))
        }
    }
    
    var paletteSection: some View {
        InsetSection {
            PaletteSection()
        } header: {
            Text(lang("Palette"))
        } footer: {
            Text(lang("Get a unique MyTonWallet Card to unlock new palettes."))
        }
    }
}

