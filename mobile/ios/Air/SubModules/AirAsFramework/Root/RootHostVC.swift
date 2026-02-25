import UIKit
import UIComponents

@MainActor
final class RootHostVC: UIViewController, VisibleContentProviding {
    private(set) var contentViewController: UIViewController?
    
    var visibleContentProviderViewController: UIViewController {
        contentViewController ?? self
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
    }
    
    func setContentViewController(_ newContentViewController: UIViewController, animationDuration: Double?) {
        if contentViewController === newContentViewController {
            return
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
}
