import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext

private extension UISheetPresentationController.Detent.Identifier {
    static let walletConnectPayStatusContent = UISheetPresentationController.Detent.Identifier("walletConnectPayStatusContent")
}

private let estimatedPaymentStatusDetentHeight: CGFloat = 352

final class WalletConnectPayPaymentStatusVC: WViewController, UISheetPresentationControllerDelegate {
    private var processing: ApiUpdate.WalletConnectPayProcessing?
    private var complete: ApiUpdate.WalletConnectPayPaymentComplete?
    private var paymentContext: WalletConnectPayPaymentContext?
    private var onClose: (() -> Void)?
    private let navigationHeaderModel: WalletConnectPayStatusNavigationHeaderModel
    private let statusModel: WalletConnectPayPaymentStatusModel
    private var hostingController: UIHostingController<WalletConnectPayPaymentStatusView>?
    private var contentHeight: CGFloat = 0
    private var shouldConfigureInitialSheetHeightOnLoad = true
    private var shouldSelectContentHeightWhenAvailable = false
    private var shouldDeferSheetHeightUpdatesUntilSelection = false

    @AccountContext var account: MAccount

    var isComplete: Bool {
        complete != nil
    }

    init(
        processing: ApiUpdate.WalletConnectPayProcessing,
        paymentContext: WalletConnectPayPaymentContext?,
        onClose: @escaping () -> Void
    ) {
        self.processing = processing
        self.paymentContext = paymentContext
        self.onClose = onClose
        self.navigationHeaderModel = WalletConnectPayStatusNavigationHeaderModel(isComplete: false)
        self.statusModel = WalletConnectPayPaymentStatusModel(
            processing: processing,
            complete: nil,
            paymentContext: paymentContext
        )
        self._account = AccountContext(accountId: processing.accountId)
        super.init(nibName: nil, bundle: nil)
    }

    init(
        complete: ApiUpdate.WalletConnectPayPaymentComplete,
        paymentContext: WalletConnectPayPaymentContext?,
        onClose: @escaping () -> Void
    ) {
        self.processing = nil
        self.complete = complete
        self.paymentContext = paymentContext
        self.onClose = onClose
        self.navigationHeaderModel = WalletConnectPayStatusNavigationHeaderModel(isComplete: true)
        self.statusModel = WalletConnectPayPaymentStatusModel(
            processing: nil,
            complete: complete,
            paymentContext: paymentContext
        )
        self._account = AccountContext(accountId: complete.accountId)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        animateToContentHeight()
    }

    func update(
        complete: ApiUpdate.WalletConnectPayPaymentComplete,
        paymentContext: WalletConnectPayPaymentContext?
    ) {
        self.complete = complete
        if let paymentContext {
            self.paymentContext = paymentContext
        }
        withAnimation(.smooth(duration: 0.28)) {
            navigationHeaderModel.isComplete = true
            statusModel.update(complete: complete, paymentContext: paymentContext)
        }
        navigationController?.isModalInPresentation = false
        isModalInPresentation = false
        Haptics.play(.success)
    }

    func prepareForReplacementTransition() {
        shouldConfigureInitialSheetHeightOnLoad = false
        contentHeight = estimatedPaymentStatusDetentHeight
        shouldSelectContentHeightWhenAvailable = true
        shouldDeferSheetHeightUpdatesUntilSelection = true
    }

    private func setupViews() {
        configureNavigationItem()
        navigationController?.isModalInPresentation = false
        isModalInPresentation = false
        hostingController = addHostingController(makeView(), constraints: .fill)
        configureOpaqueSheetBackground()
        setupSheet()
        currentSheetPresentationController?.delegate = self
    }

    private func makeView() -> WalletConnectPayPaymentStatusView {
        WalletConnectPayPaymentStatusView(
            model: statusModel,
            accountContext: _account,
            onHeightChange: { [weak self] height in
                self?.onHeightChange(height)
            }
        )
    }

    func animateToContentHeight() {
        shouldDeferSheetHeightUpdatesUntilSelection = false
        guard contentHeight > 0 else {
            shouldSelectContentHeightWhenAvailable = true
            return
        }
        shouldSelectContentHeightWhenAvailable = false
        updateSheetHeight(animated: true, selectContentHeight: true)
    }

    private func configureNavigationItem() {
        navigationItem.hidesBackButton = true
        navigationItem.title = nil
        if navigationItem.titleView == nil {
            navigationItem.titleView = HostingView {
                WalletConnectPayStatusNavigationHeader(model: navigationHeaderModel)
            }
        }
        addCloseNavigationItem()
    }

    private func configureOpaqueSheetBackground() {
        configureSheetWithOpaqueBackground(color: .air.sheetBackground)
        navigationController?.configureSheetWithOpaqueBackground(color: .air.sheetBackground)
    }

    private func addCloseNavigationItem() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in
            self?.close()
        })
    }

    private func close() {
        guard let onClose else { return }
        self.onClose = nil
        onClose()
    }

    private var currentSheetPresentationController: UISheetPresentationController? {
        navigationController?.sheetPresentationController ?? sheetPresentationController
    }

    private func setupSheet() {
        guard shouldConfigureInitialSheetHeightOnLoad else { return }
        guard let sheet = currentSheetPresentationController else { return }
        sheet.detents = makeDetents(contentHeight: estimatedPaymentStatusDetentHeight)
        sheet.selectedDetentIdentifier = .walletConnectPayStatusContent
    }

    private func onHeightChange(_ height: CGFloat) {
        guard height > 0 else { return }
        guard abs(contentHeight - height) > 0.5 else { return }
        contentHeight = height
        guard !shouldDeferSheetHeightUpdatesUntilSelection else { return }
        updateSheetHeight(animated: true, selectContentHeight: shouldSelectContentHeightWhenAvailable)
    }

    private func updateSheetHeight(animated: Bool, selectContentHeight: Bool) {
        guard contentHeight > 0, let sheet = currentSheetPresentationController else { return }

        let contentHeight = self.contentHeight
        let apply = {
            sheet.detents = self.makeDetents(contentHeight: contentHeight)
            if selectContentHeight {
                sheet.selectedDetentIdentifier = .walletConnectPayStatusContent
            }
        }

        if animated, view.window != nil {
            sheet.animateChanges {
                apply()
            }
        } else {
            apply()
        }
    }

    private func makeDetents(contentHeight: CGFloat) -> [UISheetPresentationController.Detent] {
        [
            .custom(identifier: .walletConnectPayStatusContent) { context in
                min(contentHeight, 0.95 * context.maximumDetentValue)
            }
        ]
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        close()
    }
}

@MainActor
private final class WalletConnectPayStatusNavigationHeaderModel: ObservableObject {
    @Published var isComplete: Bool

    init(isComplete: Bool) {
        self.isComplete = isComplete
    }
}

private struct WalletConnectPayStatusNavigationHeader: View {
    @ObservedObject var model: WalletConnectPayStatusNavigationHeaderModel

    var body: some View {
        NavigationHeader {
            Text(model.isComplete ? lang("Paid!") : lang("Processing Payment"))
        } subtitle: {
            if !model.isComplete {
                Text(lang("It may take a few seconds"))
                    .transition(.opacity.combined(with: .scale(scale: 0.5)))
            }
        }
        .animation(.smooth(duration: 0.28), value: model.isComplete)
    }
}

@MainActor
private final class WalletConnectPayPaymentStatusModel: ObservableObject {
    @Published private(set) var processing: ApiUpdate.WalletConnectPayProcessing?
    @Published private(set) var complete: ApiUpdate.WalletConnectPayPaymentComplete?
    @Published private(set) var paymentContext: WalletConnectPayPaymentContext?

    init(
        processing: ApiUpdate.WalletConnectPayProcessing?,
        complete: ApiUpdate.WalletConnectPayPaymentComplete?,
        paymentContext: WalletConnectPayPaymentContext?
    ) {
        self.processing = processing
        self.complete = complete
        self.paymentContext = paymentContext
    }

    func update(
        complete: ApiUpdate.WalletConnectPayPaymentComplete,
        paymentContext: WalletConnectPayPaymentContext?
    ) {
        self.complete = complete
        if let paymentContext {
            self.paymentContext = paymentContext
        }
    }
}

private struct WalletConnectPayPaymentStatusView: View {
    @ObservedObject var model: WalletConnectPayPaymentStatusModel
    var accountContext: AccountContext
    var onHeightChange: (CGFloat) -> Void

    @Namespace private var ns

    var body: some View {
        ScrollView {
            content
        }
        .coordinateSpace(name: ns)
        .scrollDisabled(true)
        .scrollIndicators(.hidden)
        .backportScrollClipDisabled()
    }

    private var content: some View {
        VStack(spacing: 12) {
            WalletConnectPayStatusArtwork(
                isComplete: model.complete != nil
            )
            .frame(width: 160, height: 160)

            if let amount {
                WalletConnectPayAmountLine(amount: amount)
            }

            WalletConnectPayMerchantLine(prefix: lang("to"), merchant: merchant)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.bottom, 48)
        .onGeometryChange(for: CGFloat.self, of: { [ns] in $0.frame(in: .named(ns)).height }) { height in
            onHeightChange(height + 58)
        }
    }

    private var merchant: WcPayMerchant {
        model.complete?.merchant ?? model.processing?.merchant ?? WcPayMerchant(name: "WalletConnect Pay", iconUrl: nil)
    }

    private var amount: WalletConnectPaySelectedPaymentAmount? {
        if let complete = model.complete {
            return walletConnectPayCompletedPaymentAmount(
                complete: complete,
                paymentContext: model.paymentContext,
                accountContext: accountContext
            )
        }

        guard let paymentContext = model.paymentContext else {
            return nil
        }

        return walletConnectPaySelectedPaymentAmount(
            paymentContext: paymentContext,
            accountContext: accountContext
        )
    }
}

private struct WalletConnectPayStatusArtwork: View {
    var isComplete: Bool

    var body: some View {
        if isComplete {
            WUIAnimatedSticker("duck_thumb", size: 160, loop: false)
        } else {
            WUIAnimatedSticker("duck_wait", size: 160, loop: true)
        }
    }
}

#if DEBUG
@available(iOS 18, *)
#Preview("WC Pay Status - Processing") {
    previewSheet(
        WalletConnectPayPaymentStatusVC(
            processing: WalletConnectPayPreviewData.processing,
            paymentContext: WalletConnectPayPreviewData.paymentContext,
            onClose: {}
        )
    )
}

@available(iOS 18, *)
#Preview("WC Pay Status - Success") {
    previewSheet(
        WalletConnectPayPaymentStatusVC(
            complete: WalletConnectPayPreviewData.complete,
            paymentContext: WalletConnectPayPreviewData.paymentContext,
            onClose: {}
        )
    )
}
#endif
