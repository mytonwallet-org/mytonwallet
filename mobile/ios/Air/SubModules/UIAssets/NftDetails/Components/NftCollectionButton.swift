
import SwiftUI
import UIKit
import UIComponents
import WalletContext

struct NftCollectionButton: View {
    
    var name: String
    var onTap: () -> ()
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 3) {
                Text(name)
                    .font(.system(size: 16))
                Image(systemName: "chevron.right")
                    .imageScale(.small)
                    .font(.system(size: 16))
                    .opacity(0.75)
            }
            .foregroundStyle(.primary)
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
