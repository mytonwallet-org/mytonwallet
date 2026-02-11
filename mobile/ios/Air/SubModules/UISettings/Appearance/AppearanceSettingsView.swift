
import Foundation
import SwiftUI
import UIKit
import UIComponents
import WalletContext
import Perception

private let log = Log("AppearanceSettingsView")

struct AppearanceSettingsView: View {
    
    var canSwitchToCapacitor: Bool {
        // can't be force unwrapped because app delegate is different in previews
        (UIApplication.shared.delegate as? MtwAppDelegateProtocol)?.canSwitchToCapacitor ?? true
    }
    
    var body: some View {
        WithPerceptionTracking {
            InsetList(topPadding: 16, spacing: 24) {
                switchToClassicSection
                themeSection
                PaletteAndCardSection()
                OtherAppearanceSettingsSection()
                    .padding(.bottom, 48)
            }
        }
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
            .allowsHitTesting(canSwitchToCapacitor)
            .opacity(canSwitchToCapacitor ? 1 : 0.5)
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
}
