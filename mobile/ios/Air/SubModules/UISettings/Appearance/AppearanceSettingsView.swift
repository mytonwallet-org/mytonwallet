
import Foundation
import SwiftUI
import UIKit
import UIComponents
import WalletContext
import Perception

struct AppearanceSettingsView: View {

    var body: some View {
        WithPerceptionTracking {
            InsetList(topPadding: 16, spacing: 24) {
                themeSection
                PaletteAndCardSection()
                
                if IS_DEBUG_OR_TESTFLIGHT {
                    AppTabsSection()
                }
                
                OtherAppearanceSettingsSection()
                    .padding(.bottom, 48)
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
