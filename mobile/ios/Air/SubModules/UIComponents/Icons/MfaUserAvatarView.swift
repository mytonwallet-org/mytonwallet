import SwiftUI
import Kingfisher
import WalletCore
import WalletContext

public struct MfaUserAvatarView: View {
    private let user: AccountMfa.User?
    private let size: CGFloat
    private let showsOuterStroke: Bool

    public init(
        user: AccountMfa.User?,
        size: CGFloat,
        showsOuterStroke: Bool = false
    ) {
        self.user = user
        self.size = size
        self.showsOuterStroke = showsOuterStroke
    }

    public var body: some View {
        ZStack {
            telegramFallback

            if let avatarUrl {
                remoteAvatar(avatarUrl)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            if showsOuterStroke {
                Circle().outerStroke(Color.air.groupedBackground, lineWidth: 2)
            }
        }
    }

    @ViewBuilder
    private func remoteAvatar(_ avatarUrl: URL) -> some View {
        KFImage(avatarUrl)
            .setProcessor(SVGImageProcessor.default)
            .resizable()
            .diskCacheExpiration(.days(1))
            .scaledToFill()
    }

    private var telegramFallback: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(UIColor(hex: "38B0E3")),
                            Color(UIColor(hex: "1D93D2")),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image.airBundle("TelegramLogo20")
                .resizable()
                .renderingMode(.template)
                .interpolation(.high)
                .scaledToFit()
                .foregroundStyle(.white)
                .frame(width: size * 0.5, height: size * 0.5)
        }
    }

    private var avatarUrl: URL? {
        guard let avatarUrlString = user?.avatarUrl?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        else {
            return nil
        }
        return URL(string: avatarUrlString)
    }
}
