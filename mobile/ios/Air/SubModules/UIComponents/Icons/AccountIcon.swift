import SwiftUI
import UIKit
import WalletCore
import WalletContext

public struct AccountIcon: View {
    
    var account: MAccount
    
    public init(account: MAccount) {
        self.account = account
    }
    
    public var body: some View {
        ZStack {
            Color.clear
            let _colors = account.firstAddress.gradientColors
            let colors = _colors.map { Color($0) }
            Circle()
                .fill(
                    LinearGradient(
                        colors: colors,
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            let content = account.avatarContent
            switch content {
            case .initial(let string):
                Text(verbatim: string)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .fixedSize()
            case .sixCharacters(let top, let bottom):
                VStack(spacing: -1.333) {
                    Text(verbatim: top)
                    Text(verbatim: bottom)
                }
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .fixedSize()
            case .typeIcon:
                EmptyView()
            case .image(_):
                EmptyView()
            }
        }
        .foregroundStyle(.white)
        .frame(width: 40, height: 40)
        .drawingGroup()
    }
}
