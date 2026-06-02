import SwiftUI
import UIKit
import WalletCore
import WalletContext
import Kingfisher

public struct AccountIcon: View {
    private enum RemoteAvatarState {
        case idle
        case loaded(URL)
        case failed(URL)
        case unavailable(URL)

        func isFailed(for avatarUrl: URL) -> Bool {
            if case .failed(let failedUrl) = self {
                return failedUrl == avatarUrl
            }
            return false
        }

        func isUnavailable(for avatarUrl: URL) -> Bool {
            if case .unavailable(let unavailableUrl) = self {
                return unavailableUrl == avatarUrl
            }
            return false
        }
    }
    
    var account: MAccount
    @State private var activeAvatarUrl: URL?
    @State private var remoteAvatarState = RemoteAvatarState.idle
    @State private var avatarRetryKey = 0
    
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
            if let avatarUrl = account.telegramAvatarUrl, !remoteAvatarState.isUnavailable(for: avatarUrl) {
                let requestKey = avatarRetryKey
                KFImage(avatarUrl)
                    .resizable()
                    .onSuccess { result in
                        guard activeAvatarUrl == avatarUrl, avatarRetryKey == requestKey else { return }
                        if result.image.size.width <= 1, result.image.size.height <= 1 {
                            remoteAvatarState = .unavailable(avatarUrl)
                        } else {
                            remoteAvatarState = .loaded(avatarUrl)
                        }
                    }
                    .onFailure { error in
                        guard !error.isTaskCancelled, activeAvatarUrl == avatarUrl, avatarRetryKey == requestKey else { return }
                        remoteAvatarState = .failed(avatarUrl)
                    }
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                    .id("\(avatarUrl.absoluteString):\(requestKey)")
            }
        }
        .foregroundStyle(.white)
        .frame(width: 40, height: 40)
        .drawingGroup()
        .onAppear {
            setActiveAvatarUrl(account.telegramAvatarUrl)
            retryFailedRemoteAvatar()
        }
        .onChange(of: account.telegramAvatarUrl) { avatarUrl in
            setActiveAvatarUrl(avatarUrl)
        }
        .task(id: avatarRetryTaskId) {
            guard let avatarUrl = account.telegramAvatarUrl, remoteAvatarState.isFailed(for: avatarUrl) else { return }

            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                retryFailedRemoteAvatar()
            }
        }
    }

    private var avatarRetryTaskId: String? {
        guard let avatarUrl = account.telegramAvatarUrl, remoteAvatarState.isFailed(for: avatarUrl) else {
            return nil
        }

        return "\(avatarUrl.absoluteString):\(avatarRetryKey)"
    }

    private func setActiveAvatarUrl(_ avatarUrl: URL?) {
        guard activeAvatarUrl != avatarUrl else { return }

        activeAvatarUrl = avatarUrl
        avatarRetryKey += 1
        remoteAvatarState = .idle
    }

    private func retryFailedRemoteAvatar() {
        guard let avatarUrl = account.telegramAvatarUrl, remoteAvatarState.isFailed(for: avatarUrl) else { return }

        activeAvatarUrl = avatarUrl
        avatarRetryKey += 1
        remoteAvatarState = .idle
    }
}
