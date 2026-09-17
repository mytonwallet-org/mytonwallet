import ContextMenuKit
import UIKit
import UIComponents
import WalletContext
import WalletCore

@available(iOS 26.0, *)
final class ActionMenuNavigationController: WNavigationController {
    private var actionTask: Task<Void, Never>?
    private var isReplacingMenu = false

    func perform(_ item: SplitHomeActionItem, accountContext: AccountContext) {
        guard actionTask == nil, !isReplacingMenu,
              topViewController is any ContextMenuSheetContent else { return }
        topViewController?.view.isUserInteractionEnabled = false
        actionTask = Task { [weak self] in
            defer {
                self?.actionTask = nil
                if self?.isReplacingMenu == false {
                    self?.topViewController?.view.isUserInteractionEnabled = true
                }
            }
            guard self?.isBeingDismissed == false, !Task.isCancelled else { return }
            if item == .swap {
                await AppActions.showSwap(
                    accountContext: accountContext,
                    defaultSellingToken: nil,
                    defaultBuyingToken: nil,
                    defaultSellingAmount: nil,
                    push: nil
                )
            } else {
                item.perform(accountContext: accountContext)
            }
        }
    }

    override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        guard let menu = topViewController as? any ContextMenuSheetContent,
              let targetNavigation = viewControllerToPresent as? WNavigationController,
              targetNavigation.viewControllers.count == 1,
              let target = targetNavigation.topViewController else {
            super.present(viewControllerToPresent, animated: flag, completion: completion)
            return
        }
        guard !isReplacingMenu, !isBeingDismissed else {
            completion?()
            return
        }
        isReplacingMenu = true
        let hidesBackButton = target.navigationItem.hidesBackButton

        let coordinator = ContentReplaceAnimationCoordinator()
        coordinator.replaceNavigationTop(with: target, in: self, prepareLayout: { [weak self] in
            menu.prepareForContentReplacement()
            targetNavigation.setViewControllers([], animated: false)
            target.navigationItem.hidesBackButton = true
            self?.setNavigationBarHidden((target as? WViewController)?.hideNavigationBar ?? false, animated: flag)
            self?.sheetPresentationController?.animateChanges {
                self?.sheetPresentationController?.detents = [.large()]
                self?.sheetPresentationController?.selectedDetentIdentifier = .large
            }
        }, isValid: { [weak self] in
            self?.isBeingDismissed == false
                && self?.viewIfLoaded?.window != nil
                && self?.topViewController === menu
        }, animateAlongside: {
            menu.animateContentReplacement()
        }) { [weak self] in
            self?.isReplacingMenu = false
            target.navigationItem.hidesBackButton = hidesBackButton
            if self?.topViewController === target {
                UIAccessibility.post(notification: .screenChanged, argument: nil)
            } else if self?.topViewController === menu {
                self?.topViewController?.view.isUserInteractionEnabled = true
            }
            completion?()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isBeingDismissed {
            actionTask?.cancel()
        }
    }
}
