import SwiftUI
import UIComponents
import WalletContext
import WalletCore

struct AppTabsSection: View {
        
    var body: some View {
        InsetSection {
            InsetButtonCell(action: onTap) {
                HStack(spacing: 16) {
                    Image.airBundle("AppearanceIcon")
                        .clipShape(.rect(cornerRadius: 8))
                    Text(lang("Customize Tabs"))
                        .foregroundStyle(Color.air.primaryLabel)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image.airBundle("RightArrowIcon")
                }
            }
        } header: {
            Text(lang("Tabs"))
        }
    }
    
    private func onTap() {
        AppActions.showCustomizeAppTabs()
    }
}

#if DEBUG
@available(iOS 18.0, *)
#Preview {
    Color.blue.opacity(0.2)
        .overlay {
            AppTabsSection()
                .fixedSize(horizontal: false, vertical: true)
        }
}
#endif
