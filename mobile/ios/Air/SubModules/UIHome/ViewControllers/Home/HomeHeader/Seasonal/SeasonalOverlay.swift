import WalletCore
import WalletContext
import SwiftUI

struct SeasonalOverlay: View {
    var seasonalTheme: ApiUpdate.UpdateConfig.SeasonalTheme?

    @ViewBuilder
    var body: some View {
        Group {
            switch seasonalTheme {
            case .newYear:
                NewYearGarland()
            case .valentine:
                ValentineHeartsOverlay()
            case nil:
                EmptyView()
            }
        }
        .contextMenu {
            if seasonalTheme != nil {
                Button {
                    AppStorageHelper.isSeasonalThemingDisabled = true
                    Task {
                        try? await GlobalStorage.syncronize()
                    }
                    AppActions.showToast(message: lang("You can always enable seasonal theming again in the appearance settings."))
                } label: {
                    Label(lang("Disable Seasonal Theming"), systemImage: "eye.slash")
                }
            }
        }
    }
}
