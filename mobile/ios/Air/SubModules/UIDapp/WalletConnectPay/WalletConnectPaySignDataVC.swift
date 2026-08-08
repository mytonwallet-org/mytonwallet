import SwiftUI
import UIKit
import ProtectedAction
import UIComponents
import WalletCore
import WalletContext

final class WalletConnectPaySignDataVC: WViewController, UISheetPresentationControllerDelegate {
    private let update: ApiUpdate.WalletConnectPaySignData
    private let onSubmit: (ApiUpdate.WalletConnectPaySignData, EnclaveToken?) async throws -> ApiMfaProtectedResult
    private var onCancel: (() -> Void)?
    private var isWaitingForNextStep = false
    private var hostingController: UIHostingController<WalletConnectPaySignDataView>?

    @AccountContext var account: MAccount

    init(
        update: ApiUpdate.WalletConnectPaySignData,
        onSubmit: @escaping (ApiUpdate.WalletConnectPaySignData, EnclaveToken?) async throws -> ApiMfaProtectedResult,
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
        let protectedAction = ProtectedAction.walletConnectPaySignData(
            account: account,
            accountContext: _account,
            update: update,
            submit: onSubmit,
            onCommitted: { [weak self] in
                self?.finishConfirm()
            }
        )
        Task {
            _ = await ProtectedActionExecutor.execute(protectedAction, on: self)
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
                    .textStyle(.body, scaling: .dynamic)
                    .lineSpacing(1)
                    .frame(minHeight: 22)
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
                    .textStyle(
                        .body,
                        content: .technical,
                        scaling: .dynamic
                    )
                    .lineSpacing(1)
                    .frame(minHeight: 22)
            }
        } header: {
            Text(lang("Cell Schema"))
        }
        InsetSection {
            InsetCell {
                Text(verbatim: payload.cell)
                    .textStyle(
                        .body,
                        content: .technical,
                        scaling: .dynamic
                    )
                    .lineSpacing(1)
                    .frame(minHeight: 22)
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
                        .textStyle(.supportingStrong)
                        .foregroundStyle(Color.air.secondaryLabel)
                    Text(verbatim: payload.primaryType)
                        .textStyle(
                            .body,
                            content: .technical,
                            scaling: .dynamic
                        )
                        .lineSpacing(1)
                        .frame(minHeight: 22)
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
