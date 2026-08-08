import Perception
import SwiftUI
import UIComponents
import UIKit
import WalletContext
import WalletCore

extension UISheetPresentationController.Detent.Identifier {
    static let nftSendSuccessContent =
        UISheetPresentationController.Detent.Identifier(
            "nftSendSuccessContent"
        )
}

@Perceptible @MainActor
private final class NftSendSuccessModel {
    let confirmed: ConfirmedNftSend
    var collapsedHeight: CGFloat = 0

    @PerceptionIgnored
    var onHeightChange: () -> Void = {}

    init(confirmed: ConfirmedNftSend) {
        self.confirmed = confirmed
    }
}

final class NftSendSuccessViewController: WViewController {
    private let model: NftSendSuccessModel

    init(confirmed: ConfirmedNftSend) {
        self.model = NftSendSuccessModel(confirmed: confirmed)
        super.init(nibName: nil, bundle: nil)
        model.onHeightChange = { [weak self] in
            self?.updateSheetHeight()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = model.confirmed.mode == .burn
            ? lang("$nfts_burned", arg1: model.confirmed.nfts.count)
            : lang("Sent")
        addCloseNavigationItemIfNeeded()
        view.backgroundColor = .air.sheetBackground

        _ = addHostingController(
            NftSendSuccessView(model: model),
            constraints: .fill
        )
        sheetPresentationController?.detents = [.large()]
        sheetPresentationController?.selectedDetentIdentifier = .large
    }

    func animateToCollapsed() {
        guard let sheetPresentationController else { return }
        sheetPresentationController.animateChanges {
            sheetPresentationController.detents = makeDetents()
            sheetPresentationController.selectedDetentIdentifier =
                .nftSendSuccessContent
        }
    }

    private func updateSheetHeight() {
        guard model.collapsedHeight > 0,
              let sheetPresentationController else {
            return
        }
        sheetPresentationController.animateChanges {
            sheetPresentationController.detents = makeDetents()
        }
    }

    private func makeDetents()
        -> [UISheetPresentationController.Detent] {
        let collapsedHeight = model.collapsedHeight + 34
        return [
            .custom(identifier: .nftSendSuccessContent) { context in
                collapsedHeight
                    < 0.95 * context.maximumDetentValue
                    ? collapsedHeight
                    : nil
            },
            .large(),
        ]
    }
}

private struct NftSendSuccessView: View {
    let model: NftSendSuccessModel

    var body: some View {
        WithPerceptionTracking {
            InsetList(spacing: 16) {
                VStack(spacing: 24) {
                    WUIAnimatedSticker(
                        "duck_thumb",
                        size: 160,
                        loop: false
                    )
                    .frame(width: 160, height: 160)

                    NftPreviewSection(nfts: model.confirmed.nfts)
                    if model.confirmed.mode == .send {
                        TappableAddressLine(
                            title: lang("Sent to"),
                            account: AccountContext(
                                source: .accountId(
                                    model.confirmed.account.id
                                )
                            ),
                            model: model.confirmed.addressViewModel
                        )
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 48)
                .onGeometryChange(
                    for: CGFloat.self,
                    of: \.size.height,
                    action: updateHeight
                )
            }
            .environment(\.insetListContext, .elevated)
            .backportScrollClipDisabled()
        }
    }

    private func updateHeight(_ height: CGFloat) {
        model.collapsedHeight = height + 24
        model.onHeightChange()
    }
}
