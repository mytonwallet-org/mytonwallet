import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext

enum MfaConfirmationCancellationReason: Equatable {
    case dismissed
    case cancelButton
    case closeButton
}

enum MfaConfirmationEvent {
    case confirmed(ApiMfaRequest)
    case failed(any Error)
    case cancelled(MfaConfirmationCancellationReason)
}

enum MfaConfirmationCloseBehavior: Equatable {
    case cancel
    case dismissInBackground
    case ignore
}

struct MfaConfirmationPresentationState {
    private enum Phase {
        case awaitingConfirmation
        case submissionInFlight
        case submissionResolved
    }

    private var phase = Phase.awaitingConfirmation

    var closeBehavior: MfaConfirmationCloseBehavior {
        switch phase {
        case .awaitingConfirmation:
            .cancel
        case .submissionInFlight:
            .dismissInBackground
        case .submissionResolved:
            .ignore
        }
    }

    var shouldShowBackgroundToastAfterDismissal: Bool {
        phase == .submissionInFlight
    }

    mutating func beginSubmission() {
        guard phase == .awaitingConfirmation else { return }
        phase = .submissionInFlight
    }

    mutating func resolveSubmission() {
        phase = .submissionResolved
    }
}

@MainActor
public final class MfaConfirmationVC: WViewController {
    private let account: MAccount
    private let model: MfaConfirmationModel
    private let titleText: String
    private let compactRepresentation: AnyView
    private let prefersNavigationTitleWithCustomHeader: Bool
    private var presentationState = MfaConfirmationPresentationState()
    private var didEmitCancellation = false
    private var isLeaving = false
    private weak var completionNavigationController: UINavigationController?
    private var wasModalInPresentation = false
    private var wasBackSwipeToDismissAllowed = true

    var onEvent: ((MfaConfirmationEvent) -> Void)?

    init(
        account: MAccount,
        model: MfaConfirmationModel,
        title: String,
        compactRepresentation: AnyView,
        prefersNavigationTitleWithCustomHeader: Bool
    ) {
        self.account = account
        self.model = model
        self.titleText = title
        self.compactRepresentation = compactRepresentation
        self.prefersNavigationTitleWithCustomHeader = prefersNavigationTitleWithCustomHeader
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = CGSize(width: 580, height: 520)
        model.onEvent = { [weak self] event in
            self?.handleModelEvent(event)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = showsNavigationTitle ? titleText : nil
        view.backgroundColor = .air.groupedBackground
        if isPresentationModal {
            navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in
                self?.cancel(reason: .closeButton)
            })
        }
        _ = addHostingController(
            MfaConfirmationView(
                account: account,
                user: account.getChainInfo(chain: .ton)?.mfa?.user,
                compactRepresentation: compactRepresentation,
                showsNavigationTitle: showsNavigationTitle,
                onOpenTelegram: { [weak self] in self?.openTelegram() },
                onCancel: { [weak self] in self?.cancel(reason: .cancelButton) }
            ),
            constraints: .fill
        )
        model.start()
    }

    private var showsNavigationTitle: Bool {
        !IOS_26_MODE_ENABLED || prefersNavigationTitleWithCustomHeader
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isLeaving = false
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if presentationState.closeBehavior != .ignore {
            isLeaving = true
        }
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if let completionNavigationController {
            completionNavigationController.allowBackSwipeToDismiss(wasBackSwipeToDismissAllowed)
            completionNavigationController.isModalInPresentation = wasModalInPresentation
            self.completionNavigationController = nil
        }
        if presentationState.closeBehavior != .ignore, !didEmitCancellation {
            if presentationState.closeBehavior == .cancel {
                presentationState.resolveSubmission()
                model.cancel()
            }
            emitCancellation(.dismissed)
        }
    }

    private func handleModelEvent(_ event: MfaConfirmationModelEvent) {
        guard presentationState.closeBehavior == .cancel, !isLeaving else { return }
        switch event {
        case .confirmed(let request):
            presentationState.beginSubmission()
            lockInteractiveDismissalForSubmission()
            Haptics.play(.success)
            onEvent?(.confirmed(request))

        case .failed(let error):
            presentationState.resolveSubmission()
            lockInteractiveDismissalForSubmission()
            navigationItem.rightBarButtonItem?.isEnabled = false
            if let onEvent {
                onEvent(.failed(error))
            } else {
                showAlert(error: error)
            }
        }
    }

    private func openTelegram() {
        guard let url = model.confirmationURL else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    private func lockInteractiveDismissalForSubmission() {
        completionNavigationController = navigationController
        wasModalInPresentation = navigationController?.isModalInPresentation ?? false
        wasBackSwipeToDismissAllowed = navigationController?.isBackSwipeToDismissAllowed ?? true
        completionNavigationController?.allowBackSwipeToDismiss(false)
        completionNavigationController?.isModalInPresentation = true
    }

    @discardableResult
    func submissionDidResolve() -> Bool {
        guard presentationState.closeBehavior == .dismissInBackground else { return false }
        presentationState.resolveSubmission()
        navigationItem.rightBarButtonItem?.isEnabled = false
        return !didEmitCancellation && !isLeaving
    }

    private func cancel(
        reason: MfaConfirmationCancellationReason,
        dismissIfNeeded: Bool = true
    ) {
        let closeBehavior = presentationState.closeBehavior
        switch closeBehavior {
        case .cancel:
            presentationState.resolveSubmission()
            model.cancel()
        case .dismissInBackground:
            guard reason == .closeButton else { return }
        case .ignore:
            return
        }
        emitCancellation(reason)
        if dismissIfNeeded {
            switch reason {
            case .closeButton:
                let completion = { [self] in
                    guard presentationState.shouldShowBackgroundToastAfterDismissal else {
                        return
                    }
                    AppActions.showToast(message: lang("$action_will_continue_in_background"))
                }
                if let navigationController {
                    navigationController.dismiss(animated: true, completion: completion)
                } else {
                    dismiss(animated: true, completion: completion)
                }
            case .dismissed, .cancelButton:
                if canGoBack {
                    navigationController?.popViewController(animated: true)
                } else {
                    dismiss(animated: true)
                }
            }
        }
    }

    private func emitCancellation(_ reason: MfaConfirmationCancellationReason) {
        guard !didEmitCancellation else { return }
        didEmitCancellation = true
        onEvent?(.cancelled(reason))
    }
}

private struct MfaConfirmationView: View {
    let account: MAccount
    let user: AccountMfa.User?
    let compactRepresentation: AnyView
    let showsNavigationTitle: Bool
    let onOpenTelegram: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                HStack(spacing: -28) {
                    MfaAccountAvatarView(account: account, size: 80)
                    MfaUserAvatarView(user: user, size: 80, showsOuterStroke: true)
                }

                VStack(spacing: 19) {
                    (
                        Text(lang("Confirm with")) +
                        Text(" ") +
                        Text(Image.airBundle("inline.telegram")) +
                        Text("\u{00A0}Telegram")
                    )
                    .textStyle(.screenTitle)
                    .imageScale(.small)
                    .foregroundStyle(Color.air.primaryLabel)
                    .multilineTextAlignment(.center)

                    compactRepresentation
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 24)

                InsetSection(addDividers: false, horizontalPadding: 16) {
                    InsetCell(horizontalPadding: 16, verticalPadding: 12) {
                        HStack(spacing: 16) {
                            Image.airBundle("MfaBenefitShieldIcon")
                                .resizable()
                                .frame(width: 30, height: 30)
                            Text(lang("An extra security layer requires confirming actions in Telegram after signing."))
                                .textStyle(.callout)
                                .lineSpacing(3)
                                .foregroundStyle(Color.air.primaryLabel)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 40)
            }
            .padding(.top, showsNavigationTitle ? 20 : 0)
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

}

#if DEBUG
@available(iOS 18, *)
#Preview {
    MfaConfirmationView(
        account: .sampleMnemonic,
        user: AccountMfa.User(id: "1", name: "Artemii Ledenev", username: "artemii"),
        compactRepresentation: AnyView(
            CompactActionSummary {
                Image(systemName: "paperplane.fill")
            } label: {
                Text("10.5 TON to UQk3lS···5Fa4fK")
            }
        ),
        showsNavigationTitle: false,
        onOpenTelegram: {},
        onCancel: {}
    )
}
#endif
