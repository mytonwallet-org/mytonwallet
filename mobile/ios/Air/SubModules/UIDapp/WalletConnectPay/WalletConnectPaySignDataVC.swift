import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext

final class WalletConnectPaySignDataVC: WViewController, UISheetPresentationControllerDelegate {
    private let update: ApiUpdate.WalletConnectPaySignData
    private let onSubmit: (ApiUpdate.WalletConnectPaySignData, String?) async throws -> ApiMfaProtectedResult
    private var onCancel: (() -> Void)?
    private var isWaitingForNextStep = false
    private var hostingController: UIHostingController<WalletConnectPaySignDataView>?

    @AccountContext var account: MAccount

    init(
        update: ApiUpdate.WalletConnectPaySignData,
        onSubmit: @escaping (ApiUpdate.WalletConnectPaySignData, String?) async throws -> ApiMfaProtectedResult,
        onCancel: @escaping () -> Void
    ) {
        self.update = update
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        self._account = AccountContext(accountId: update.accountId)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
    }

    private func setupViews() {
        navigationItem.title = update.merchant.name
        addCloseNavigationItemIfNeeded()
        
        if navigationItem.rightBarButtonItem != nil {
            navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in
                self?.onCancelPressed()
            })
        }
        hostingController = addHostingController(makeView(), constraints: .fill)
        
        addCustomNavigationBarBackground(color: .air.sheetBackground)

        view.backgroundColor = .air.sheetBackground
        (navigationController?.sheetPresentationController ?? sheetPresentationController)?.delegate = self
    }

    private func onConfirm() {
        guard !isWaitingForNextStep else { return }
        Task {
            do {
                _ = try await AppActions.authorizeProtectedAction(
                    on: self,
                    account: account,
                    title: lang("Confirm Sending"),
                    headerView: WalletConnectPayAuthHeaderView(
                        merchant: update.merchant,
                        paymentContext: WalletConnectPayPaymentContext(
                            paymentInfo: update.paymentInfo,
                            paymentOption: update.paymentOption
                        ),
                        accountContext: _account
                    ),
                    passwordAction: { password in
                        try await self.onSubmit(self.update, password)
                    },
                    completionBehavior: .keepAuthForReplacement,
                    prefersNavigationTitleWithCustomHeader: true,
                    mfaTitle: lang("Confirm Sending")
                )
                finishConfirm()
            } catch is CancellationError {
            } catch {
                showAlert(error: error)
            }
        }
    }

    private func makeView() -> WalletConnectPaySignDataView {
        WalletConnectPaySignDataView(
            update: update,
            accountContext: _account,
            isWaitingForNextStep: isWaitingForNextStep,
            onConfirm: { [weak self] in self?.onConfirm() },
            onCancel: { [weak self] in self?.onCancelPressed() },
            onShowTransferInfo: { [weak self] in self?.showTransferInfo() }
        )
    }

    private func render() {
        hostingController?.rootView = makeView()
    }

    private func finishConfirm() {
        onCancel = nil
        isWaitingForNextStep = true
        isModalInPresentation = true
        navigationController?.isModalInPresentation = true
        navigationItem.rightBarButtonItem?.isEnabled = false
        render()
    }

    private func onCancelPressed() {
        onCancel?()
        onCancel = nil
    }

    private func showTransferInfo() {
        navigationController?.pushViewController(
            WalletConnectPaySignDataInfoVC(update: update),
            animated: true
        )
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        onCancelPressed()
    }
}

private struct WalletConnectPaySignDataView: View {
    var update: ApiUpdate.WalletConnectPaySignData
    var accountContext: AccountContext
    var isWaitingForNextStep: Bool
    var onConfirm: () -> Void
    var onCancel: () -> Void
    var onShowTransferInfo: () -> Void

    var body: some View {
        InsetList(topPadding: 24) {
            WalletConnectPayPaymentHeaderView(
                merchant: update.merchant,
                paymentInfo: update.paymentInfo
            )
            .padding(.horizontal, 16)

            WalletConnectPayConfirmationSummarySections(
                accountContext: accountContext,
                paymentOption: update.paymentOption
            )

            WalletConnectPayTransferInfoRow(action: onShowTransferInfo)
        }
        .safeAreaInset(edge: .bottom) {
            buttons
        }
    }

    private var buttons: some View {
        HStack(spacing: 16) {
            Button(action: onCancel) {
                Text(lang("Cancel"))
            }
            .buttonStyle(.airSecondary)
            .disabled(isWaitingForNextStep)
            Button(action: onConfirm) {
                Text(lang("Sign"))
            }
            .buttonStyle(.airPrimary)
            .environment(\.isLoading, isWaitingForNextStep)
            .disabled(isWaitingForNextStep)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }
}

private final class WalletConnectPaySignDataInfoVC: WViewController {
    private let update: ApiUpdate.WalletConnectPaySignData
    private var hostingController: UIHostingController<WalletConnectPaySignDataInfoView>?

    init(update: ApiUpdate.WalletConnectPaySignData) {
        self.update = update
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = lang("Transfer Info")
        hostingController = addHostingController(makeView(), constraints: .fill)
        addCustomNavigationBarBackground(color: .air.sheetBackground)
        view.backgroundColor = .air.sheetBackground
    }

    private func makeView() -> WalletConnectPaySignDataInfoView {
        WalletConnectPaySignDataInfoView(payloadToSign: update.payloadToSign)
    }
}

private struct WalletConnectPaySignDataInfoView: View {
    var payloadToSign: SignDataPayload

    var body: some View {
        InsetList(topPadding: 16) {
            switch payloadToSign {
            case .text(let text):
                makeText(payload: text)
            case .binary(let binary):
                makeBinary(payload: binary)
            case .cell(let cell):
                makeCell(payload: cell)
            case .eip712(let eip712):
                makeEip712(payload: eip712)
            }
        }
    }

    @ViewBuilder
    private func makeText(payload: SignDataPayloadText) -> some View {
        InsetSection {
            InsetCell {
                Text(verbatim: payload.text)
                    .font17h22()
            }
        } header: {
            Text(lang("Message"))
        }
    }

    @ViewBuilder
    private func makeBinary(payload: SignDataPayloadBinary) -> some View {
        InsetSection {
            InsetExpandableCell(content: payload.bytes)
        } header: {
            Text(lang("Binary Data"))
        }
    }

    @ViewBuilder
    private func makeCell(payload: SignDataPayloadCell) -> some View {
        InsetSection {
            InsetCell {
                Text(verbatim: payload.schema)
                    .font17h22()
            }
        } header: {
            Text(lang("Cell Schema"))
        }
        InsetSection {
            InsetCell {
                Text(verbatim: payload.cell)
                    .font17h22()
            }
        } header: {
            Text(lang("Cell Data"))
        }
    }

    @ViewBuilder
    private func makeEip712(payload: SignDataPayloadEip712) -> some View {
        InsetSection {
            InsetCell {
                VStack(alignment: .leading, spacing: 4) {
                    Text(lang("Primary type"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.air.secondaryLabel)
                    Text(verbatim: payload.primaryType)
                        .font17h22()
                }
            }
        } header: {
            Text(lang("EIP-712 typed data"))
        }
        InsetSection {
            InsetCell(verticalPadding: 14) {
                Eip712ObjectView(
                    object: payload.domain,
                    typeName: "EIP712Domain",
                    types: payload.types
                )
            }
        } header: {
            Text(lang("EIP-712 domain"))
        }
        InsetSection {
            InsetCell(verticalPadding: 14) {
                Eip712ObjectView(
                    object: payload.message,
                    typeName: payload.primaryType,
                    types: payload.types
                )
            }
        } header: {
            Text(lang("Message"))
        }
    }
}
