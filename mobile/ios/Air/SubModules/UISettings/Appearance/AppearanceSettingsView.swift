
import Foundation
import SwiftUI
import UIKit
import UIComponents
import WalletContext
import Perception

private let log = Log("AppearanceSettingsView")

struct AppearanceSettingsView: View {
    
    var canSwitchToCapacitor: Bool {
        isCapacitorAvailable
    }
    
    var body: some View {
        WithPerceptionTracking {
            InsetList(topPadding: 16, spacing: 24) {
                if canSwitchToCapacitor {
                    switchToClassicSection
                }
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
