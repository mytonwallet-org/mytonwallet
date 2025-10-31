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

@MainActor
public class ActivityVC: WViewController, WSensitiveDataProtocol, WalletCoreData.EventsObserver {
    
    private var model: ActivityDetialsViewModel
    
    public init(activity: ApiActivity) {
        self.model = ActivityDetialsViewModel(activity: activity, detailsExpanded: false, scrollingDisabled: true)
        super.init(nibName: nil, bundle: nil)
        model.onHeightChange = { [weak self] in self?.onHeightChange() }
        model.onDetailsExpandedChanged = { [weak self] in self?.onDetailsExpandedChanged() }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private var hostingController: UIHostingController<ActivityView>?
    private var decryptedComment: String? = nil
    private var contentHeight: CGFloat? = nil
    private var activity: ApiActivity { model.activity }
    private var detentChange: Date = .distantPast
    private var scrollOffset: CGFloat = 0
    
    public override func loadView() {
        super.loadView()
        setupViews()
        WalletCoreData.add(eventObserver: self)
    }
        
    private func setupViews() {
        if let p = sheetPresentationController {
            p.delegate = self
        }
        
        let (title, titleIsRed) = makeTitle()
        let subtitle = activity.timestamp.dateTimeString
        
        addNavigationBar(
            navHeight: 60,
            centerYOffset: 0,
            title: title,
            subtitle: subtitle,
            titleColor: titleIsRed ? WTheme.error : nil,
            closeIcon: true)
        navigationBarProgressiveBlurDelta = 10
        if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
            let appearance = UINavigationBarAppearance()
            appearance.titleTextAttributes = [
                .font: UIFont.systemFont(ofSize: 17, weight: .semibold)
            ]
            let style = NSMutableParagraphStyle()
            style.minimumLineHeight = 19
            appearance.subtitleTextAttributes = [
                .font: UIFont.systemFont(ofSize: 13, weight: .regular),
                .paragraphStyle: style,
            ]
            navigationItem.standardAppearance = appearance
            if let sheet = sheetPresentationController {
                sheet.prefersGrabberVisible = true
            }
        }
        
        self.hostingController = addHostingController(makeView(), constraints: .fill)
        hostingController?.view.clipsToBounds = false
        
        bringNavigationBarToFront()

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
                        self.model.activity = tx
                    }
                } catch {
                }
            }
        }
    }

    func makeTitle() -> (String, Bool) {

        let title = activity.displayTitleResolved

        var titleIsRed: Bool = false

        switch activity {
        case .transaction:
            break
        case .swap(let swap):
            switch swap.status {
            case .pending, .pendingTrusted, .completed:
                break
            case .failed:
                titleIsRed = true
            case .expired:
                titleIsRed = true
            }
        }

        return (title, titleIsRed)
    }

    public override func updateTheme() {
        view.backgroundColor = WTheme.sheetBackground
    }


    func makeView() -> ActivityView {
        ActivityView(
            model: self.model,
            navigationBarInset: navigationBarHeight,
            onScroll: { [weak self] y in self?.updateNavigationBarProgressiveBlur(y) },
            onDecryptComment: decryptMessage,
            decryptedComment: decryptedComment,
            isSensitiveDataHidden: AppStorageHelper.isSensitiveDataHidden
        )
    }
    
    func onHeightChange() {
        
        guard model.collapsedHeight > 0 else { return }
        
        let collapsedHeight = model.collapsedHeight + 34
        let expandedHeight = model.expandedHeight + 34
        
        if let p = sheetPresentationController {

            guard model.detailsExpanded == false || p.selectedDetentIdentifier != .large else { return }

            if let sv = view.superview?.bounds.size, expandedHeight >= sv.height * 0.85 {
                updateScrollingDisabled(false)
            }
            if expandedHeight != self.contentHeight {
                p.animateChanges {
                    p.detents = makeDetents()
//
//                    if p.selectedDetentIdentifier == .detailsCollapsed || Date().timeIntervalSince(detentChange) > 0.5 {
//                        p.selectedDetentIdentifier = .detailsCollapsed
//                    } else if p.selectedDetentIdentifier == .detailsExpanded {
//                        p.selectedDetentIdentifier = .detailsExpanded
//                    }
                }
                self.contentHeight = expandedHeight
            }
        }
    }
    
    func makeDetents() -> [UISheetPresentationController.Detent] {
        let collapsedHeight = model.collapsedHeight + 34
        let expandedHeight = model.expandedHeight + 34
        
        var detents: [UISheetPresentationController.Detent] = []
        if model.activity.transaction?.nft == nil || !model.detailsExpanded {
            detents.append(.custom(identifier: .detailsCollapsed) { context in
                if collapsedHeight >= 0.95 * context.maximumDetentValue { // not worth it
                    return nil
                }
                return collapsedHeight
            })
        }
        if model.activity.transaction?.nft == nil {
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
    
    public func onScroll(_ y: CGFloat) {
        self.scrollOffset = y
        updateNavigationBarProgressiveBlur(y)
    }
    
    func onDetailsExpandedChanged() {
        let detailsExpanded = model.detailsExpanded
        
        if let p = sheetPresentationController {
            p.animateChanges {
                if detailsExpanded && model.activity.transaction?.nft != nil {
                    p.selectedDetentIdentifier = .large
                } else if detailsExpanded && (p.selectedDetentIdentifier == .detailsCollapsed || p.selectedDetentIdentifier == nil) && model.activity.transaction?.nft == nil {
                    p.selectedDetentIdentifier = .detailsExpanded
                } else if !detailsExpanded && p.selectedDetentIdentifier != .detailsCollapsed {
                    if model.activity.transaction?.nft != nil {
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
        let id = activity.id
        var newActivity: ApiActivity?
        if let replacementId = replacedIds[id], let replacementActivity = await ActivityStore.getActivity(accountId: accountId, activityId: replacementId) {
            newActivity = replacementActivity
        } else if updatedIds.contains(id), let updatedActivity = await ActivityStore.getActivity(accountId: accountId, activityId: id) {
            newActivity = updatedActivity
        }

        if let newActivity {
            withAnimation {
                model.activity = newActivity
                let (title, titleIsRed) = makeTitle()
                navigationBar?.set(title: title, titleColor: titleIsRed ? WTheme.error : .label)
                if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
                    navigationItem.title = title
                    navigationItem.subtitle = activity.timestamp.dateTimeString
                }
            }
        }
    }
}


extension ActivityVC: UISheetPresentationControllerDelegate {

    public func sheetPresentationControllerDidChangeSelectedDetentIdentifier(_ sheetPresentationController: UISheetPresentationController) {
        if sheetPresentationController.selectedDetentIdentifier == .detailsCollapsed || sheetPresentationController.selectedDetentIdentifier == .detailsExpanded {
            updateScrollingDisabled(true)
            model.progressiveRevealEnabled = true
        } else {
            updateScrollingDisabled(false)
            model.progressiveRevealEnabled = false
        }
        if sheetPresentationController.selectedDetentIdentifier == .large || sheetPresentationController.selectedDetentIdentifier == .detailsExpanded {
            detentChange = .now
            model.detailsExpanded = true
        } else if sheetPresentationController.selectedDetentIdentifier == .detailsCollapsed {
            detentChange = .now
            model.detailsExpanded = false
        }
        if sheetPresentationController.selectedDetentIdentifier == .large && activity.transaction?.nft != nil {
            sheetPresentationController.detents = makeDetents()
        }
    }
    
    func updateScrollingDisabled(_ scrollingDisabled: Bool) {
        DispatchQueue.main.async { [self] in
            if scrollingDisabled != model.scrollingDisabled {
                model.scrollingDisabled = scrollingDisabled
            }
        }
    }
}


// MARK: Activity info preview

#if DEBUG
//@available(iOS 18, *)
//#Preview {
//    let _ = UIFont.registerAirFonts()
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
