import SwiftUI
import WalletCore
import WalletContext

public struct MfaAccountAvatarView: View {
    private let account: MAccount
    private let size: CGFloat

    public init(account: MAccount, size: CGFloat) {
        self.account = account
        self.size = size
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: account.firstAddress.gradientColors.map { Color($0) },
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            switch account.avatarContent {
            case .initial(let value):
                Text(verbatim: value)
                    .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
            case .sixCharacters(let top, let bottom):
                VStack(spacing: -size * 0.03) {
                    Text(verbatim: top)
                    Text(verbatim: bottom)
                }
                .font(.system(size: size * 0.24, weight: .heavy, design: .rounded))
            case .typeIcon, .image:
                Text(account.displayName.prefix(1).uppercased())
                    .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
            }
        }
        .foregroundStyle(.white)
        .frame(width: size, height: size)
    }
}
