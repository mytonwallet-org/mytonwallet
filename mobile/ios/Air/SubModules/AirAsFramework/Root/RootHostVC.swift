import UIKit
import UIComponents
import WalletCore

@MainActor
final class RootHostVC: UIViewController, VisibleContentProviding {
    private(set) var contentViewController: UIViewController?
    private(set) var baseRootState: AppRootState?
    private(set) var currentRootState: AppRootState?
    
    var visibleContentProviderViewController: UIViewController {
        contentViewController ?? self
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
    }
    
    func setContentViewController(_ newContentViewController: UIViewController, rootState: AppRootState, animationDuration: Double?) {
        if contentViewController === newContentViewController {
            baseRootState = rootState
            if currentRootState != .unlock {
                currentRootState = rootState
            }
            return
        }

        baseRootState = rootState
        if currentRootState != .unlock {
            currentRootState = rootState
        }
        
        if let currentContentViewController = contentViewController {
            currentContentViewController.willMove(toParent: nil)
            addChild(newContentViewController)
            newContentViewController.view.frame = view.bounds
            newContentViewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            
            if let animationDuration {
                transition(from: currentContentViewController, to: newContentViewController, duration: animationDuration, options: [.transitionCrossDissolve], animations: nil) { _ in
                    currentContentViewController.removeFromParent()
                    newContentViewController.didMove(toParent: self)
                }
            } else {
                currentContentViewController.view.removeFromSuperview()
                currentContentViewController.removeFromParent()
                view.addSubview(newContentViewController.view)
                newContentViewController.didMove(toParent: self)
            }
        } else {
            addChild(newContentViewController)
            newContentViewController.view.frame = view.bounds
            newContentViewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(newContentViewController.view)
            newContentViewController.didMove(toParent: self)
        }
        
        contentViewController = newContentViewController
    }

    func setUnlockPresented(_ isPresented: Bool) {
        currentRootState = isPresented ? .unlock : baseRootState
    }

    func reset() {
        presentedViewController?.dismiss(animated: false)
        if let currentContentViewController = contentViewController {
            currentContentViewController.willMove(toParent: nil)
            currentContentViewController.view.removeFromSuperview()
            currentContentViewController.removeFromParent()
        }
        contentViewController = nil
        baseRootState = nil
        currentRootState = nil
    }
}
