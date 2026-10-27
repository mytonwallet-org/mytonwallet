//
//  ActivityDetailsVC.swift
//  WalletContext
//
//  Created by Sina on 3/25/24.
//

import SwiftUI
import UIKit
import UIComponents
import WalletContext
import WalletCore
import UIPasscode

private let expandedHeightCutoff: CGFloat = 650

@MainActor
public final class ActivityDetailsVC: WViewController, WSensitiveDataProtocol, WalletCoreData.EventsObserver, Sendable {
    
    static let floatingSheetSize = CGSize(width: 580, height: 720)

    let viewModel: ActivityDetailsViewModel
    private var presentationMode: SheetPresentationMode?
    private var detailsSheet: UISheetPresentationController? {
        (navigationController ?? self).sheetPresentationController
    }
    
    public init(activity: ApiActivity, accountSource: AccountSource, context: ActivityDetailsContext) {
        self.viewModel = ActivityDetailsViewModel(activity: activity, accountSource: accountSource, detailsExpanded: false, scrollingDisabled: true, context: context)
        super.init(nibName: nil, bundle: nil)
        viewModel.onHeightChange = { [weak self] in self?.onHeightChange() }
        viewModel.onDetailsExpandedChanged = { [weak self] in self?.onDetailsExpandedChanged() }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private var hostingController: UIHostingController<ActivityDetailsView>?
    private var decryptedComment: String? = nil
    private var activity: ApiActivity { viewModel.activity }
    
    public override func loadView() {
        super.loadView()
        setupViews()
        WalletCoreData.add(eventObserver: self)
    }
        
    private func setupViews() {
        updatePresentationPolicy()

        if let p = detailsSheet {
            p.delegate = self
        }
        
        navigationItem.titleView = HostingView {
            ActivityDetailsNavigationHeader(viewModel: viewModel)
        }
        addCloseNavigationItemIfNeeded()
        if let sheet = detailsSheet {
            if IOS_26_MODE_ENABLED {
                sheet.prefersGrabberVisible = viewModel.detailsCollapseEnabled
            }
            if #available(iOS 26.1, *) {
                sheet.backgroundEffect = UIColorEffect(color: .air.sheetBackground)
            }
        }
        
        self.hostingController = addHostingController(makeView(), constraints: .fill)
        hostingController?.view.clipsToBounds = false
        
        updateTheme()
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        viewModel.fetchDetailsIfNeeded()
    }

    private func updateTheme() {
        view.backgroundColor = .air.sheetBackground
    }


    func makeView() -> ActivityDetailsView {
        ActivityDetailsView(
            model: self.viewModel,
            onDecryptComment: decryptMessage,
            onTokenTapped: { [weak self] token in
                guard let self else { return }
                dismiss(animated: true) { [accountSource = viewModel.accountContext.source] in
                    AppActions.showToken(accountSource: accountSource, token: token, isInModal: false)
                }
            },
            decryptedComment: decryptedComment,
            isSensitiveDataHidden: AppStorageHelper.isSensitiveDataHidden
        )
    }
    
    func onHeightChange() {
        
        guard viewModel.collapsedHeight > 0 else { return }
        guard viewModel.detailsCollapseEnabled else { return }
        
        let expandedHeight = viewModel.expandedHeight + 34
        
        if let p = detailsSheet {

            guard viewModel.detailsExpanded == false || p.selectedDetentIdentifier != .large else { return }

            if let sv = view.superview?.bounds.size, expandedHeight >= sv.height * 0.85 {
                updateScrollingDisabled(false)
            }
            
            let updateDetents = {
                p.detents = self.makeDetents()
            }
            let host = navigationController ?? self
            if view.window != nil, !host.isBeingPresented {
                p.animateChanges(updateDetents)
            } else {
                updateDetents()
            }
        }
    }
    
    func makeDetents() -> [UISheetPresentationController.Detent] {
        guard viewModel.detailsCollapseEnabled, viewModel.collapsedHeight > 0 else {
            return [.large()]
        }

        let collapsedHeight = viewModel.collapsedHeight + 34
        let expandedHeight = viewModel.expandedHeight + 34
        
        var detents: [UISheetPresentationController.Detent] = []
        if (viewModel.activity.transaction?.nft == nil || !viewModel.detailsExpanded) {
            detents.append(.custom(identifier: .detailsCollapsed) { context in
                if collapsedHeight >= 0.95 * context.maximumDetentValue { // not worth it
                    return nil
                }
                return collapsedHeight
            })
        }
        if viewModel.activity.transaction?.nft == nil && viewModel.expandedHeight > viewModel.collapsedHeight && viewModel.expandedHeight < expandedHeightCutoff {
            detents.append(.custom(identifier: .detailsExpanded) { context in
                if expandedHeight >= 0.95 * context.maximumDetentValue { // not worth it
                    return nil
                }
                return expandedHeight
            })
        }
        detents.append(.large())
        return detents
    }
    
    public func animateToCollapsed() {
        updatePresentationPolicy()
        guard viewModel.detailsCollapseEnabled else {
            if let sheet = detailsSheet {
                sheet.animateChanges {
                    sheet.detents = makeDetents()
                    sheet.selectedDetentIdentifier = .large
                }
            }
            return
        }

        if let sheet = detailsSheet {
            sheet.animateChanges {
                sheet.detents = makeDetents()
                sheet.selectedDetentIdentifier = .detailsCollapsed
                viewModel.detailsExpanded = false
            }
        }
    }
    
    public func onScroll(_ y: CGFloat) {
    }
    
    func onDetailsExpandedChanged() {
        guard viewModel.detailsCollapseEnabled else { return }

        let detailsExpanded = viewModel.detailsExpanded
        
        if let p = detailsSheet {
            p.animateChanges {
                if detailsExpanded && (viewModel.activity.transaction?.nft != nil || viewModel.expandedHeight >= expandedHeightCutoff) {
                    p.selectedDetentIdentifier = .large
                } else if detailsExpanded && (p.selectedDetentIdentifier == .detailsCollapsed || p.selectedDetentIdentifier == nil) && viewModel.activity.transaction?.nft == nil {
                    p.detents = makeDetents()
                    p.selectedDetentIdentifier = .detailsExpanded
                } else if !detailsExpanded && p.selectedDetentIdentifier != .detailsCollapsed {
                    if viewModel.activity.transaction?.nft != nil {
                        p.detents = makeDetents()
                    }
                    p.selectedDetentIdentifier = .detailsCollapsed
                }
            }
        }
    }
    
    @objc func decryptMessage() {
        UnlockVC.presentAuth(
            on: self,
            onDone: { [weak self] enclaveToken in
                guard let self,
                      case .transaction(let tx) = self.activity else { return }
                Task {
                    do {
                        let accountId = self.viewModel.accountContext.accountId
                        self.decryptedComment = try await Api.decryptComment(accountId: accountId, activity: tx, enclaveToken: enclaveToken)
                        self.hostingController?.rootView = self.makeView()
                    } catch {
                        self.showAlert(error: error) {
                            self.dismiss(animated: true)
                        }
                    }
                }
            },
            cancellable: true)
    }
    
    public func updateSensitiveData() {
        hostingController?.rootView = makeView()
    }
    
    public func walletCore(event: WalletCoreData.Event) {
        switch event {
        case let .activitiesChanged(accountId, updatedIds, replacedIds):
            Task {
                await handleActivitiesChanged(accountId: accountId, updatedIds: updatedIds, replacedIds: replacedIds)
            }
        case .nftsChanged(let accountId):
            handleNftsChanged(accountId: accountId)
        default:
            break
        }
    }

    private func handleNftsChanged(accountId: String) {
        guard accountId == viewModel.accountContext.accountId else {
            return
        }
        viewModel.refreshWearableNft()
        guard let nft = activity.transaction?.nft,
              nft.metadata?.lottie?.nilIfEmpty == nil else {
            return
        }
        let resolvedNft = NftStore.nftWithStoredTelegramGiftLottie(accountId: accountId, nft: nft)
        guard resolvedNft.metadata?.lottie?.nilIfEmpty != nil else {
            return
        }
        hostingController?.rootView = makeView()
    }
    
    func handleActivitiesChanged(accountId: String, updatedIds: [String], replacedIds: [String: String]) async {
        guard accountId == self.viewModel.accountContext.account.id else { return }
        let id = activity.id
        let hash = activity.parsedTxId.hash
        var newActivity: ApiActivity?
        
        if let replacementId = replacedIds[id],
           let replacementActivity = await ActivityStore.getActivity(accountId: accountId, activityId: replacementId),
           canReplaceDisplayedActivity(with: replacementActivity) {
            newActivity = replacementActivity
        } else if updatedIds.contains(id), let updatedActivity = await ActivityStore.getActivity(accountId: accountId, activityId: id) {
            newActivity = updatedActivity
        } else if activity.isLocal {
            for (oldId, replacementId) in replacedIds where getParsedTxId(id: oldId).hash == hash {
                if let replacementActivity = await ActivityStore.getActivity(accountId: accountId, activityId: replacementId),
                   canReplaceDisplayedActivity(with: replacementActivity) {
                    newActivity = replacementActivity
                    break
                }
            }
        }
        
        // workaround for unstake request getting replaced by excess
        if activity.isLocal && activity.type == .unstakeRequest {
            for updatedId in updatedIds {
                if let replacementActivity = await ActivityStore.getActivity(accountId: accountId, activityId: updatedId),
                   canReplaceDisplayedActivity(with: replacementActivity),
                   replacementActivity.type == .unstakeRequest {
                    newActivity = replacementActivity
                    break
                }
            }
            // unstake is an even better match than unstakeRequest
            for updatedId in updatedIds {
                if let replacementActivity = await ActivityStore.getActivity(accountId: accountId, activityId: updatedId),
                   canReplaceDisplayedActivity(with: replacementActivity),
                   replacementActivity.type == .unstake {
                    newActivity = replacementActivity
                    break
                }
            }
        }

        if let newActivity {
            withAnimation {
                _ = viewModel.updateActivity(newActivity)
            }
        }
    }

    private func canReplaceDisplayedActivity(with replacementActivity: ApiActivity) -> Bool {
        guard replacementActivity.shouldHide != true else {
            return false
        }

        switch (activity, replacementActivity) {
        case (.transaction(let transaction), .transaction(let replacementTransaction)):
            return transaction.type == replacementTransaction.type
        case (.swap(let swap), .swap(let replacementSwap)):
            return isSwapFromAmountCloseEnough(swap.fromAmount, replacementSwap.fromAmount)
        default:
            return false
        }
    }

    private func isSwapFromAmountCloseEnough(_ originalAmount: MDouble, _ replacementAmount: MDouble) -> Bool {
        if originalAmount.value == 0 {
            return replacementAmount.value == 0
        }

        let difference = abs(replacementAmount.value - originalAmount.value)
        return difference <= abs(originalAmount.value) * 0.1
    }

    public func prepareForPresentation(from presenter: UIViewController) {
        updatePresentationPolicy(mode: sheetPresentationMode(presentingFrom: presenter))
    }

    private func updatePresentationPolicy() {
        updatePresentationPolicy(mode: sheetPresentationMode)
    }

    private func updatePresentationPolicy(mode: SheetPresentationMode?) {
        guard let mode, mode != presentationMode else { return }
        let isInitialPresentation = presentationMode == nil
        presentationMode = mode

        let canCollapse = mode == .bottomAttached
        let startsExpanded = !canCollapse || (isInitialPresentation && (navigationController?.viewControllers.count ?? 1) > 1)
        viewModel.detailsCollapseEnabled = canCollapse
        viewModel.detailsExpanded = startsExpanded
        viewModel.progressiveRevealEnabled = !startsExpanded
        viewModel.scrollingDisabled = !startsExpanded

        let size = mode == .floating ? Self.floatingSheetSize : .zero
        (navigationController ?? self).preferredContentSize = size

        if let sheet = detailsSheet {
            if IOS_26_MODE_ENABLED {
                sheet.prefersGrabberVisible = canCollapse
            }
            // The first SwiftUI measurement supplies the compact detents. Do not install zero-height ones.
            sheet.detents = canCollapse && viewModel.collapsedHeight > 0 ? makeDetents() : [.large()]
            sheet.selectedDetentIdentifier = startsExpanded ? .large
                : viewModel.collapsedHeight > 0 ? .detailsCollapsed : nil
        }
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updatePresentationPolicy()
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updatePresentationPolicy()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updatePresentationPolicy()
    }
}


extension ActivityDetailsVC: UISheetPresentationControllerDelegate {

    public func sheetPresentationControllerDidChangeSelectedDetentIdentifier(_ sheetPresentationController: UISheetPresentationController) {
        if !viewModel.detailsCollapseEnabled {
            updateScrollingDisabled(false)
            viewModel.progressiveRevealEnabled = false
            viewModel.detailsExpanded = true
            return
        }

        if sheetPresentationController.selectedDetentIdentifier == .detailsCollapsed || sheetPresentationController.selectedDetentIdentifier == .detailsExpanded {
            updateScrollingDisabled(true)
            viewModel.progressiveRevealEnabled = true
        } else {
            updateScrollingDisabled(false)
            viewModel.progressiveRevealEnabled = false
        }
        if sheetPresentationController.selectedDetentIdentifier == .large || sheetPresentationController.selectedDetentIdentifier == .detailsExpanded {
            viewModel.detailsExpanded = true
        } else if sheetPresentationController.selectedDetentIdentifier == .detailsCollapsed {
            viewModel.detailsExpanded = false
        }
        if sheetPresentationController.selectedDetentIdentifier == .large && activity.transaction?.nft != nil {
            sheetPresentationController.detents = makeDetents()
        }
    }
    
    func updateScrollingDisabled(_ scrollingDisabled: Bool) {
        DispatchQueue.main.async { [self] in
            if scrollingDisabled != viewModel.scrollingDisabled {
                viewModel.scrollingDisabled = scrollingDisabled
            }
        }
    }

}


// MARK: Activity info preview

#if DEBUG
//@available(iOS 18, *)
//#Preview {
//    ActivityDetailsVC(
//        activity: .transaction(
//            .init(
//                id: "tU90ta421vOf4Hn0",
//                kind: "transaction",
//                timestamp: 1_800_000_000_000,
//                amount: -100_000_000,
//                fromAddress: "from",
//                toAddress: "to",
//                comment: "comment",
//                encryptedComment: nil,
//                fee: 45234678,
//                slug: TON_USDT_SLUG,
//                isIncoming: false,
//                normalizedAddress: nil,
//                externalMsgHashNorm: nil,
//                shouldHide: nil,
//                type: nil,
//                metadata: nil,
//                nft: nil,
//                isPending: true,
//            )
//        )
//    )
//}
#endif

extension UISheetPresentationController.Detent.Identifier {
    static let detailsCollapsed = UISheetPresentationController.Detent.Identifier("detailsCollapsed")
    static let detailsExpanded = UISheetPresentationController.Detent.Identifier("detailsExpanded")
}
