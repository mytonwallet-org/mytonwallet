
import SwiftUI
import UIComponents
import WalletCore
import WalletContext

struct HiddenByUserCell: View {

    var displayNft: DisplayNft
    var isHighlighted: Bool
    var action: (Bool) -> ()
    
    @State private var isHiddenByUser = false
    
    var body: some View {
        HStack {
            NftPreviewRow(nft: displayNft.nft, horizontalPadding: 12, verticalPadding: 10)
                .padding(.trailing, -2)
            Button(action: toggle) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: isHiddenByUser ? "eye.fill" : "eye.slash.fill")
                        .imageScale(.small)
                    Text(isHiddenByUser ? "Unhide" : "Hide")
                }
                .font(.system(size: 16, weight: .semibold))
                .contentShape(.capsule)
            }
            .transition(.opacity.combined(with: .scale))
            .id(isHiddenByUser)
            .buttonBorderShape(.capsule)
            .buttonStyle(.bordered)
            .tint(Color(WTheme.tint))
            .padding(.trailing, 12)
            .animation(.snappy, value: isHiddenByUser)
        }
        .highlightBackground(isHighlighted)
        .onChange(of: displayNft) { nft in
            isHiddenByUser = displayNft.isHiddenByUser
        }
        .onAppear {
            isHiddenByUser = displayNft.isHiddenByUser
        }
    }
    
    func toggle() {
        action(!isHiddenByUser)
        isHiddenByUser.toggle()
    }
}
