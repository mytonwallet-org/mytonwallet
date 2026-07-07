import SwiftUI
import UIKit
import UIComponents
import WalletContext
import Perception

extension UISheetPresentationController.Detent.Identifier {
    static let actionSuccessContent = UISheetPresentationController.Detent.Identifier("actionSuccessContent")
}

@Perceptible @MainActor
private final class ActionSuccessViewModel {
    let variant: ActionSuccessVC.Variant
    var collapsedHeight: CGFloat = 0

    @PerceptionIgnored
    var onHeightChange: () -> () = { }

    init(variant: ActionSuccessVC.Variant) {
        self.variant = variant
    }
}

final class ActionSuccessVC: WViewController {

    enum Variant {
        case sendNft(SendModel)
    }

    private let viewModel: ActionSuccessViewModel

    init(variant: Variant) {
        self.viewModel = ActionSuccessViewModel(variant: variant)
        super.init(nibName: nil, bundle: nil)
        viewModel.onHeightChange = { [weak self] in self?.onHeightChange() }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = titleText
        addCloseNavigationItemIfNeeded()
        view.backgroundColor = .air.sheetBackground

        _ = addHostingController(ActionSuccessView(model: viewModel), constraints: .fill)
        setupSheet()
    }

    public func animateToCollapsed() {
        guard let sheet = sheetPresentationController else { return }
        sheet.animateChanges {
            sheet.detents = makeDetents()
            sheet.selectedDetentIdentifier = .actionSuccessContent
        }
    }

    private var titleText: String {
        switch viewModel.variant {
        case .sendNft(let model):
            switch model.mode {
            case .burnNft:
                lang("$nfts_burned", arg1: model.nfts.count)
            default:
                lang("Sent!")
            }
        }
    }

    private func setupSheet() {
        guard let sheet = sheetPresentationController else { return }
        sheet.detents = [.large()]
        sheet.selectedDetentIdentifier = .large
    }

    private func onHeightChange() {
        guard viewModel.collapsedHeight > 0 else { return }
        guard let sheet = sheetPresentationController else { return }

        sheet.animateChanges {
            sheet.detents = makeDetents()
        }
    }

    private func makeDetents() -> [UISheetPresentationController.Detent] {
        let collapsedHeight = viewModel.collapsedHeight + 34
        var detents: [UISheetPresentationController.Detent] = []
        detents.append(
            .custom(identifier: .actionSuccessContent) { context in
                if collapsedHeight >= 0.95 * context.maximumDetentValue {
                    return nil
                }
                return collapsedHeight
            }
        )
        detents.append(.large())
        return detents
    }

}

private struct ActionSuccessView: View {

    var model: ActionSuccessViewModel

    @Namespace private var ns

    var body: some View {
        WithPerceptionTracking {
            InsetList(spacing: 16) {
                VStack(spacing: 24) {
                    switch model.variant {
                    case .sendNft(let sendModel):
                        NftSection(model: sendModel)
                        if sendModel.mode == .sendNft {
                            ActionSuccessRecipientSection(model: sendModel)
                        }
                    }
                }
                .onGeometryChange(for: CGFloat.self, of: { [ns] in $0.frame(in: .named(ns)).height }, action: { height in
                    model.collapsedHeight = height + 24
                    model.onHeightChange()
                })

                Color.clear.frame(width: 0, height: 0)
                    .padding(.bottom, 34)
            }
            .environment(\.insetListContext, .elevated)
            .coordinateSpace(name: ns)
            .backportScrollClipDisabled()
        }
    }
}

private struct ActionSuccessRecipientSection: View {

    let model: SendModel

    var body: some View {
        WithPerceptionTracking {
            InsetSection {
                InsetCell {
                    TappableAddressFull(accountContext: model.$account, model: model.addressViewModel, compactAddressWithName: false, wrapsAddressWithName: true)
                }
            } header: {
                Text(lang("Recipient Address"))
            } footer: {}
        }
    }
}
