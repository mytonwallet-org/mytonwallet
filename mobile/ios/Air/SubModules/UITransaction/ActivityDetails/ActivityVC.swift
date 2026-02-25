//
//  ActivityVC.swift
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
public class ActivityVC: WViewController, WSensitiveDataProtocol, WalletCoreData.EventsObserver {
    
    private var viewModel: ActivityDetailsViewModel
    private var shouldDisableDetailsCollapse: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
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
    
    private var hostingController: UIHostingController<ActivityView>?
    private var decryptedComment: String? = nil
    private var activity: ApiActivity { viewModel.activity }
    private var detentChange: Date = .distantPast
    private var scrollOffset: CGFloat = 0
    
    public override func loadView() {
        super.loadView()
        setupViews()
        WalletCoreData.add(eventObserver: self)
    }
        
    private func setupViews() {
        applyDetailsCollapsePolicy()

        if let p = sheetPresentationController {
            p.delegate = self
        }
        
        navigationItem.titleView = HostingView {
            ActivityNavigationHeader(viewModel: viewModel)
        }
        addCloseNavigationItemIfNeeded()
        if let sheet = sheetPresentationController {
            if IOS_26_MODE_ENABLED {
                sheet.prefersGrabberVisible = viewModel.detailsCollapseEnabled
            }
            if #available(iOS 26.1, *) {
                sheet.backgroundEffect = UIColorEffect(color: WTheme.sheetBackground)
            }
            if !viewModel.detailsCollapseEnabled {
                sheet.detents = makeDetents()
                sheet.selectedDetentIdentifier = .large
                viewModel.detailsExpanded = true
                updateScrollingDisabled(false)
            } else if let navigationController, navigationController.viewControllers.count > 1 {
                sheet.selectedDetentIdentifier = .large
                viewModel.detailsExpanded = true
                updateScrollingDisabled(false)
            }
        }
        
        self.hostingController = addHostingController(makeView(), constraints: .fill)
        hostingController?.view.clipsToBounds = false
        
        updateTheme()
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        let activity = self.activity
        if let accountId = AccountStore.accountId, activity.shouldLoadDetails == true {
            Task { [weak self] in
                do {
                    let tx = try await ActivityStore.fetchActivityDetails(accountId: accountId, activity: activity)
                    if let self {
                        self.viewModel.activity = tx
                    }
                } catch {
                }
            }
        }
    }

    public override func updateTheme() {
        view.backgroundColor = WTheme.sheetBackground
    }


    func makeView() -> ActivityView {
        ActivityView(
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
        
        if let p = sheetPresentationController {

            guard viewModel.detailsExpanded == false || p.selectedDetentIdentifier != .large else { return }

            if let sv = view.superview?.bounds.size, expandedHeight >= sv.height * 0.85 {
                updateScrollingDisabled(false)
            }
            
            p.animateChanges {
                p.detents = makeDetents()
            }
        }
    }
    
    func makeDetents() -> [UISheetPresentationController.Detent] {
        guard viewModel.detailsCollapseEnabled else {
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
        if viewModel.activity.transaction?.nft == nil && viewModel.expandedHeight < expandedHeightCutoff {
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
        guard viewModel.detailsCollapseEnabled else {
            if let sheet = sheetPresentationController {
                sheet.animateChanges {
                    sheet.detents = makeDetents()
                    sheet.selectedDetentIdentifier = .large
                }
            }
            return
        }

        if let sheet = sheetPresentationController {
            sheet.animateChanges {
                sheet.detents = makeDetents()
                sheet.selectedDetentIdentifier = .detailsCollapsed
                viewModel.detailsExpanded = false
            }
        }
    }
    
    public func onScroll(_ y: CGFloat) {
        self.scrollOffset = y
        updateNavigationBarProgressiveBlur(y)
    }
    
    func onDetailsExpandedChanged() {
        guard viewModel.detailsCollapseEnabled else { return }

        let detailsExpanded = viewModel.detailsExpanded
        
        if let p = sheetPresentationController {
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
            onDone: { [weak self] passcode in
                guard let self,
                      let accountId = AccountStore.accountId,
                      case .transaction(let tx) = self.activity else { return }
                Task {
                    do {
                        self.decryptedComment = try await Api.decryptComment(accountId: accountId, activity: tx, password: passcode)
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
        default:
            break
        }
    }
    
    func handleActivitiesChanged(accountId: String, updatedIds: [String], replacedIds: [String: String]) async {
        guard accountId == self.viewModel.accountContext.account.id else { return }
        let id = activity.id
        let hash = activity.parsedTxId.hash
        var newActivity: ApiActivity?
        
        if let replacementId = replacedIds[id], let replacementActivity = await ActivityStore.getActivity(accountId: accountId, activityId: replacementId) {
            newActivity = replacementActivity
        } else if updatedIds.contains(id), let updatedActivity = await ActivityStore.getActivity(accountId: accountId, activityId: id) {
            newActivity = updatedActivity
        } else if activity.isLocal, let replacementId = replacedIds.first(where: { getParsedTxId(id: $0.key).hash == hash })?.value, let updatedActivity = await ActivityStore.getActivity(accountId: accountId, activityId: replacementId) {
            newActivity = updatedActivity
        }
        
        // workaround for unstake request getting replaced by excess
        if activity.isLocal && activity.type == .unstakeRequest {
            for updatedId in updatedIds {
                if let replacementActivity = await ActivityStore.getActivity(accountId: accountId, activityId: updatedId), replacementActivity.type == .unstakeRequest {
                    newActivity = replacementActivity
                    break
                }
            }
            // unstake is an even better match than unstakeRequest
            for updatedId in updatedIds {
                if let replacementActivity = await ActivityStore.getActivity(accountId: accountId, activityId: updatedId), replacementActivity.type == .unstake {
                    newActivity = replacementActivity
                    break
                }
            }
        }

        if let newActivity {
            withAnimation {
                viewModel.activity = newActivity
            }
        }
    }

    private func applyDetailsCollapsePolicy() {
        let detailsCollapseEnabled = !shouldDisableDetailsCollapse
        guard viewModel.detailsCollapseEnabled != detailsCollapseEnabled else { return }

        viewModel.detailsCollapseEnabled = detailsCollapseEnabled
        if let sheet = sheetPresentationController, IOS_26_MODE_ENABLED {
            sheet.prefersGrabberVisible = detailsCollapseEnabled
        }
        if detailsCollapseEnabled {
            viewModel.progressiveRevealEnabled = true
            if let sheet = sheetPresentationController, view.window != nil {
                sheet.animateChanges {
                    sheet.detents = makeDetents()
                }
            }
        } else {
            viewModel.detailsExpanded = true
            viewModel.progressiveRevealEnabled = false
            viewModel.scrollingDisabled = false
            if let sheet = sheetPresentationController, view.window != nil {
                sheet.animateChanges {
                    sheet.detents = makeDetents()
                    sheet.selectedDetentIdentifier = .large
                }
            }
        }
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyDetailsCollapsePolicy()
    }
}


extension ActivityVC: UISheetPresentationControllerDelegate {

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
            detentChange = .now
            viewModel.detailsExpanded = true
        } else if sheetPresentationController.selectedDetentIdentifier == .detailsCollapsed {
            detentChange = .now
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
//    ActivityVC(
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
