import Combine
import SwiftUI
import UIComponents
import WalletCore
import WalletContext
import Perception

struct MfaView: View {
    @State private var accountContext: AccountContext
    @ObservedObject private var model: MfaFlowModel

    private let pollingTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(accountContext: AccountContext, model: MfaFlowModel) {
        _accountContext = State(initialValue: accountContext)
        self.model = model
    }

    var body: some View {
        WithPerceptionTracking {
            let tonBalance = accountContext.balances[TONCOIN_SLUG]
            let mfa = accountContext.account.getChainInfo(chain: .ton)?.mfa
            let state = MfaScreenState(
                mfa: mfa,
                canInstallMfa: IS_GRAM_WALLET,
                isWalletSupported: accountContext.account.currentTonWalletVersion == ApiTonWalletVersion.W5.rawValue,
                hasInstallBalance: tonBalance.map { $0 >= MfaFlowModel.installFee } ?? false,
                isRefreshingMfa: model.isRefreshingMfa,
                isWaitingForTelegramInstall: model.isWaitingForTelegramInstall,
                isWaitingForTelegramRemoval: model.isWaitingForTelegramRemoval
            )

            MfaScreen(state: state) {
                Task {
                    await model.primaryAction(mfa: mfa)
                }
            } onAddInGramWallet: {
                UIApplication.shared.open(URL(string: "https://apps.apple.com/us/app/gram-wallet/id6763345750")!)
            }
            .onReceive(pollingTimer) { _ in
                Task {
                    await model.pollIfNeeded()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                Task {
                    await model.pollIfNeeded()
                }
            }
            .task {
                await model.refreshStoredMfaOnOpenIfNeeded()
                await model.pollIfNeeded()
            }
        }
    }
}

private struct MfaScreenState {
    let mfa: AccountMfa?
    let canInstallMfa: Bool
    let isWalletSupported: Bool
    let hasInstallBalance: Bool
    let isRefreshingMfa: Bool
    let isWaitingForTelegramInstall: Bool
    let isWaitingForTelegramRemoval: Bool

    var isConfigured: Bool {
        mfa != nil
    }

    var isInstallAvailable: Bool {
        canInstallMfa && isWalletSupported && hasInstallBalance
    }

    var shouldShowAddInGramWalletButton: Bool {
        !isConfigured && !canInstallMfa && !isWaitingForTelegramInstall && !isWaitingForTelegramRemoval
    }

    var shouldShowFooter: Bool {
        isConfigured || canInstallMfa || isWaitingForTelegramInstall || isWaitingForTelegramRemoval || shouldShowAddInGramWalletButton
    }

    var shouldShowConnectionFee: Bool {
        !shouldShowAddInGramWalletButton
    }

    var isPrimaryActionLoading: Bool {
        isRefreshingMfa || isWaitingForTelegramRemoval
    }

    var stickerName: String {
        isRefreshingMfa || isWaitingForTelegramInstall || isWaitingForTelegramRemoval ? "duck_wait" : "animation_snitch"
    }

    var feeTextColor: Color {
        canInstallMfa && !isConfigured && isWalletSupported && !hasInstallBalance ? .red : .air.secondaryLabel
    }

    var primaryButtonTitle: String {
        if isConfigured {
            return lang("Unlink Account")
        }
        if isWaitingForTelegramInstall {
            return lang("Open Telegram")
        }
        if !canInstallMfa {
            return lang("Confirm with Telegram")
        }
        if !isWalletSupported {
            return lang("Unsupported Wallet Version")
        }
        return isInstallAvailable ? lang("Connect Telegram") : lang("Insufficient Balance")
    }

    var isPrimaryActionEnabled: Bool {
        if isConfigured {
            return !isRefreshingMfa && !isWaitingForTelegramRemoval
        }
        if !canInstallMfa { return false }
        if isRefreshingMfa { return false }
        if isWaitingForTelegramInstall {
            return true
        }
        return isInstallAvailable
    }
}

private struct MfaScreen: View {
    let state: MfaScreenState
    let onPrimaryAction: () -> Void
    let onAddInGramWallet: () -> Void

    private let installBenefits: [MfaBenefit] = [
        .init(
            iconAssetName: "MfaBenefitShieldIcon",
            markdownText: lang("Add an **extra layer of security** for your wallet in TON network.")
        ),
        .init(
            iconAssetName: "MfaBenefitPlaneIcon",
            markdownText: lang("Sign transfers and important actions with your passcode, **then confirm them in Telegram**.")
        ),
        .init(
            iconAssetName: "MfaBenefitKeyIcon",
            markdownText: lang("This helps **protect your funds** even if your recovery phrase or keys are compromised.")
        )
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                WUIAnimatedSticker(state.stickerName, size: 124, loop: true)
                    .padding(.top, 0)

                MfaTitleView()
                    .padding(.top, 24)
                    .padding(.horizontal, 16)

                if state.isConfigured {
                    configuredContent
                } else {
                    installContent
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .safeAreaInset(edge: .bottom) {
            footer
        }
        .background(Color.air.groupedBackground.ignoresSafeArea())
    }

    private var installContent: some View {
        VStack(spacing: 16) {
            ForEach(installBenefits) { benefit in
                MfaBenefitCard(benefit: benefit)
            }
        }
        .padding(.top, 32)
    }

    private var configuredContent: some View {
        VStack(spacing: 16) {
            MfaAccountSection(user: state.mfa?.user)
            ForEach(installBenefits.dropFirst()) { benefit in
                MfaBenefitCard(benefit: benefit)
            }
        }
        .padding(.top, 32)
    }

    @ViewBuilder
    private var footer: some View {
        if state.shouldShowFooter {
            VStack(spacing: 12) {
                if state.shouldShowConnectionFee {
                    (
                        Text(lang("Connection Fee:")) +
                        Text(" ") +
                        Text(amount: TokenAmount(MfaFlowModel.installFee, .TONCOIN), format: .init())
                    )
                        .font(.system(size: 14))
                        .foregroundStyle(state.feeTextColor)
                }

                if state.shouldShowAddInGramWalletButton {
                    Button(action: onAddInGramWallet) {
                        Text(lang("Add in Gram Wallet"))
                    }
                    .buttonStyle(WUIButtonStyle(style: .primary))
                } else {
                    Button(action: onPrimaryAction) {
                        Text(state.primaryButtonTitle)
                    }
                    .buttonStyle(
                        state.isConfigured
                            ? WUIButtonStyle(style: .destructive)
                            : WUIButtonStyle(style: .primary)
                    )
                    .environment(\.isLoading, state.isPrimaryActionLoading)
                    .disabled(!state.isPrimaryActionEnabled)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .background(Color.air.groupedBackground)
        }
    }
}

struct MfaTitleView: View {
    var body: some View {
        (
            Text(lang("Confirm with")) +
            Text(" ") +
            Text(Image.airBundle("TelegramLogo20")) +
            Text("\u{00A0}Telegram")
        )
        .font(.system(size: 28, weight: .semibold))
        .foregroundStyle(Color.air.primaryLabel)
        .multilineTextAlignment(.center)
    }
}

private struct MfaBenefit: Identifiable {
    let iconAssetName: String
    let markdownText: String

    var id: String { iconAssetName }
}

private struct MfaBenefitCard: View {
    let benefit: MfaBenefit

    private var attributedText: AttributedString {
        (try? AttributedString(markdown: benefit.markdownText)) ?? AttributedString(benefit.markdownText)
    }

    var body: some View {
        InsetSection(addDividers: false, horizontalPadding: 16) {
            InsetCell(verticalPadding: 12) {
                HStack(alignment: .center, spacing: 16) {
                    Image.airBundle(benefit.iconAssetName)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 30, height: 30)
                    Text(attributedText)
                        .font(.system(size: 16))
                        .foregroundStyle(Color(.label))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct MfaAccountSection: View {
    let user: AccountMfa.User?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(lang("My Telegram Account"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.air.secondaryLabel)
                .padding(.horizontal, 16)

            InsetSection(addDividers: false, horizontalPadding: 16) {
                InsetCell(verticalPadding: 10) {
                    HStack(spacing: 12) {
                        MfaUserAvatarView(user: user, size: 40)

                        VStack(alignment: .leading, spacing: 0) {
                            Text(displayName)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Color(.label))
                            Text(user?.username.flatMap { "@\($0)" } ?? lang("Without username"))
                                .font(.system(size: 14))
                                .foregroundStyle(Color.air.secondaryLabel)
                        }

                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private var displayName: String {
        user?.name.nilIfEmpty ?? lang("Telegram Account")
    }
}

struct MfaAccountAvatarView: View {
    let account: MAccount
    let size: CGFloat

    var body: some View {
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

struct MfaSettingsRowIcon: View {
    var body: some View {
        Image.airBundle("MfaSettingsIcon")
            .resizable()
            .interpolation(.high)
            .frame(width: 30, height: 30)
    }
}

#if DEBUG
@available(iOS 18, *)
#Preview("MFA Install") {
    MfaScreen(
        state: MfaScreenState(
            mfa: nil,
            canInstallMfa: true,
            isWalletSupported: true,
            hasInstallBalance: true,
            isRefreshingMfa: false,
            isWaitingForTelegramInstall: false,
            isWaitingForTelegramRemoval: false
        ),
        onPrimaryAction: {},
        onAddInGramWallet: {}
    )
}

@available(iOS 18, *)
#Preview("MFA Insufficient Fee") {
    MfaScreen(
        state: MfaScreenState(
            mfa: nil,
            canInstallMfa: true,
            isWalletSupported: true,
            hasInstallBalance: false,
            isRefreshingMfa: false,
            isWaitingForTelegramInstall: false,
            isWaitingForTelegramRemoval: false
        ),
        onPrimaryAction: {},
        onAddInGramWallet: {}
    )
}

@available(iOS 18, *)
#Preview("MFA Configured") {
    MfaScreen(
        state: MfaScreenState(
            mfa: AccountMfa(
                address: "0:demo",
                user: .init(id: "1", name: "Artemii Ledenev", username: "artemii")
            ),
            canInstallMfa: true,
            isWalletSupported: true,
            hasInstallBalance: true,
            isRefreshingMfa: false,
            isWaitingForTelegramInstall: false,
            isWaitingForTelegramRemoval: false
        ),
        onPrimaryAction: {},
        onAddInGramWallet: {}
    )
}
#endif
