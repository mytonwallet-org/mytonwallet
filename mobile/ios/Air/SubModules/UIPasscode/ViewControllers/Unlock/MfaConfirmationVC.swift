import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext

private let log = Log("MfaConfirmationVC")

@MainActor
public final class MfaConfirmationVC: WViewController {
    private let account: MAccount
    private let requestHash: String
    private let titleText: String
    private var pollingTask: Task<Void, Never>?
    private var didComplete = false

    public var onDone: ((ApiMfaRequest) async -> Void)?
    public var onCancel: (() -> Void)?

    public init(account: MAccount, requestHash: String, title: String) {
        self.account = account
        self.requestHash = requestHash
        self.titleText = title
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = titleText
        view.backgroundColor = .air.groupedBackground
        if isPresentationModal {
            navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in
                self?.cancel()
            })
        }
        _ = addHostingController(
            MfaConfirmationView(
                account: account,
                user: account.getChainInfo(chain: .ton)?.mfa?.user,
                onOpenTelegram: { [weak self] in self?.openTelegram() },
                onCancel: { [weak self] in self?.cancel() }
            ),
            constraints: .fill
        )
        startPolling()
    }

    deinit {
        pollingTask?.cancel()
    }

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.poll()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func poll() async {
        guard !didComplete else { return }
        do {
            let request = try await Api.fetchMfaRequest(hash: requestHash)
            guard request.isConfirmed else { return }
            didComplete = true
            pollingTask?.cancel()
            Haptics.play(.success)
            await onDone?(request)
        } catch {
            log.error("fetchMfaRequest failed while polling \(requestHash, .public): \(error, .public)")
            if shouldStopPolling(for: error) {
                didComplete = true
                pollingTask?.cancel()
                showAlert(error: error)
            }
        }
    }

    private func shouldStopPolling(for error: any Error) -> Bool {
        guard let error = error as? SdkError else {
            return false
        }
        switch error {
        case .message(let message):
            return message != .serverError
        case .sdkNotReady, .decoding, .invalidResponse:
            return false
        case .apiReturnedError, .javaScriptException, .unexpected:
            return true
        }
    }

    private func openTelegram() {
        guard let url = buildMfaBotUrl(startApp: requestHash) else {
            log.error("Failed to build MFA bot url for requestHash: \(requestHash, .public)")
            return
        }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    private func cancel() {
        pollingTask?.cancel()
        onCancel?()
    }
}

private struct MfaConfirmationView: View {
    let account: MAccount
    let user: AccountMfa.User?
    let onOpenTelegram: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                WUIAnimatedSticker("duck_wait", size: 124, loop: true)

                HStack(spacing: -20) {
                    AccountIcon(account: account)
                        .frame(width: 64, height: 64)
                        .scaleEffect(1.6)
                        .frame(width: 64, height: 64)
                    MfaUserAvatarView(user: user, size: 64, showsOuterStroke: true)
                }
                .padding(.top, 4)

                VStack(spacing: 8) {
                    (
                        Text(lang("Confirm with")) +
                        Text(" ") +
                        Text(Image.airBundle("TelegramLogo20")) +
                        Text("\u{00A0}Telegram")
                    )
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.air.primaryLabel)
                    .multilineTextAlignment(.center)

                    Text(userDisplayName)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.tint)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

                InsetSection(addDividers: false, horizontalPadding: 16) {
                    InsetCell(verticalPadding: 12) {
                        HStack(spacing: 16) {
                            Image.airBundle("MfaBenefitKeyIcon")
                                .resizable()
                                .frame(width: 30, height: 30)
                            Text(lang("An extra security layer requires confirming actions in Telegram after signing."))
                                .font(.system(size: 16))
                                .foregroundStyle(Color.air.primaryLabel)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                Button(action: onCancel) {
                    Text(lang("Cancel"))
                }
                .buttonStyle(WUIButtonStyle(style: .secondary))

                Button(action: onOpenTelegram) {
                    Text(lang("Confirm"))
                }
                .buttonStyle(WUIButtonStyle(style: .primary))
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .background(Color.air.groupedBackground)
        }
        .background(Color.air.groupedBackground.ignoresSafeArea())
    }

    private var userDisplayName: String {
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
    MfaConfirmationView(
        account: .sampleMnemonic,
        user: AccountMfa.User(id: "1", name: "Artemii Ledenev", username: "artemii"),
        onOpenTelegram: {},
        onCancel: {}
    )
}
#endif
