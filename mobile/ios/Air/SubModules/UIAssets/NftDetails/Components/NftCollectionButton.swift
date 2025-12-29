
import SwiftUI
import UIKit
import UIComponents
import WalletContext

struct NftCollectionButton: View {
    
    var name: String
    var onTap: () -> ()
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
//                NftImage(nft: nft, animateIfPossible: false)
//                    .clipShape(.rect(cornerRadius: 6))
//                    .frame(width: 20, height: 20)
//                    .padding(.trailing, 8)
                Text(name)
                    .font(.system(size: 16))
                Image(systemName: "chevron.right")
                    .imageScale(.small)
                    .font(.system(size: 16))
                    .frame(width: 24, height: 24)
                    .offset(y: 1)
                    .opacity(0.75)
            }
            .frame(height: 24)
            .padding(10) // larger tap target
            .contentShape(.rect)
        }
        .padding(-10)
        .buttonStyle(.plain)
        .compositingGroup()
        .drawingGroup()
        .fixedSize()
    }
}
