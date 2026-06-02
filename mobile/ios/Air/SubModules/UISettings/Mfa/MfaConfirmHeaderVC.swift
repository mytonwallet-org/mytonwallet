import SwiftUI
import UIKit
import UIComponents
import UIPasscode
import WalletCore
import WalletContext

@MainActor
final class MfaConfirmHeaderVC: WViewController {
    static let height: CGFloat = 296

    private let account: MAccount
    private let titleText: String
    private let user: AccountMfa.User?
    private var hostingController: UIHostingController<MfaConfirmHeaderView>?

    init(account: MAccount, title: String, user: AccountMfa.User?) {
        self.account = account
        self.titleText = title
        self.user = user
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = UIView()
        view.backgroundColor = .air.groupedBackground
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        hostingController = addHostingController(makeView(), constraints: .fill)
        view.heightAnchor.constraint(equalToConstant: Self.height).isActive = true
    }

    private func makeView() -> MfaConfirmHeaderView {
        MfaConfirmHeaderView(account: account, title: titleText, user: user)
    }
}

struct MfaConfirmHeaderView: View {
    let account: MAccount
    let title: String
    let user: AccountMfa.User?

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)

            HStack(spacing: -28) {
                MfaAccountAvatarView(account: account, size: 80)
                MfaUserAvatarView(user: user, size: 80)
            }

            Text(title)
                .font(.system(size: 28, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color(.label))
                .padding(.horizontal, 32)

            HStack(spacing: 4) {
                Image.airBundle("TelegramLogo20")
                    .resizable()
                    .frame(width: 20, height: 20)
                Text(verbatim: userDisplayText)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.tint)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.12), in: Capsule())

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(height: MfaConfirmHeaderVC.height)
        .background(Color.air.groupedBackground)
    }

    private var userDisplayText: String {
        let name = user?.name.nilIfEmpty ?? lang("Telegram Account")
        if let username = user?.username?.nilIfEmpty {
            return "\(name) · @\(username)"
        }
        return name
    }
}

#if DEBUG
@available(iOS 18, *)
#Preview {
    let user = AccountMfa.User(id: "1", name: "Artemii Ledenev", username: "artemii")
    let unlockVC = UnlockVC(
        title: lang("Confirm Connection"),
        replacedTitle: nil,
        subtitle: nil,
        customHeaderVC: MfaConfirmHeaderVC(
            account: .sampleMnemonic,
            title: lang("Confirm Connection"),
            user: user
        ),
        animatedPresentation: false,
        dissmissWhenAuthorized: false,
        shouldBeThemedLikeHeader: false,
        onAuthTask: { _, onTaskDone in
            onTaskDone()
        },
        onDone: { _ in },
        cancellable: false,
        onCancel: nil,
        useBioOnPresent: false,
        successCompletionDelay: 0
    )
    previewNc(unlockVC)
}
#endif
