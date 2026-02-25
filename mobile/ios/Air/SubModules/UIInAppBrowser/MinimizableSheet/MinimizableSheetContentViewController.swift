import UIComponents
import UIKit
import WalletContext

public final class MinimizableSheetContentViewController: WViewController {

    private(set) weak var browser: InAppBrowserVC?
    private var sheetObservation: MinimizableSheetObservation?
    private weak var observedSheetController: MinimizableSheetController?
    private let stateTransitionAnimationDuration: TimeInterval = 0.2

    private var blurView: WBlurView!
    private var contentView: InAppBrowserMinimizedView!

    public init() {
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        observeSheetControllerIfNeeded()
        applyState(minimizableSheetController?.state ?? .hidden)
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        observeSheetControllerIfNeeded()
    }

    private func setupViews() {
        view.backgroundColor = WTheme.browserOpaqueBar
        blurView = WBlurView()
        view.addSubview(blurView)
        blurView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: view.topAnchor),
            blurView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            blurView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        contentView = InAppBrowserMinimizedView(
            title: browser?.displayTitle,
            iconUrl: nil,
            titleTapAction: { [weak self] in
                self?.expandTouchTargetPressed()
            },
            closeAction: { [weak self] in
                self?.closeButtonPressed()
            }
        )
        view.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: view.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentView.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    func setBrowser(_ browser: InAppBrowserVC?) {
        if self.browser === browser {
            if let browser {
                inAppBrowserTitleChanged(browser)
            }
            return
        }

        if let previousBrowser = self.browser {
            previousBrowser.delegate = nil
            previousBrowser.view.layer.removeAllAnimations()
            previousBrowser.view.alpha = 1
            previousBrowser.willMove(toParent: nil)
            previousBrowser.view.removeFromSuperview()
            previousBrowser.removeFromParent()
        }

        self.browser = browser

        if let browser {
            if let existingParent = browser.parent, existingParent !== self {
                browser.view.layer.removeAllAnimations()
                browser.view.alpha = 1
                browser.willMove(toParent: nil)
                browser.view.removeFromSuperview()
                browser.removeFromParent()
            }
            browser.delegate = self
            addChild(browser)
            view.addSubview(browser.view)
            browser.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                browser.view.topAnchor.constraint(equalTo: view.topAnchor),
                browser.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                browser.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                browser.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            ])
            view.sendSubviewToBack(browser.view)
            browser.didMove(toParent: self)
            inAppBrowserTitleChanged(browser)
        } else {
            contentView.update(title: nil, iconUrl: nil)
        }
        applyState(minimizableSheetController?.state ?? .hidden)
    }

    private func expand() {
        minimizableSheetController?.expand(animated: true)
    }

    @objc
    private func closeButtonPressed() {
        minimizableSheetController?.close(animated: true)
    }

    @objc
    private func expandTouchTargetPressed() {
        expand()
    }

    private func observeSheetControllerIfNeeded() {
        guard let controller = minimizableSheetController else { return }
        guard observedSheetController !== controller else { return }

        sheetObservation?.invalidate()
        observedSheetController = controller
        sheetObservation = controller.addObserver(options: [.stateWillChanges, .stateChanges]) { [weak self] event in
            guard let self else { return }
            switch event {
            case .stateWillChange(let change):
                self.animateStateTransition(to: change.toState)
            case .stateDidChange(let change):
                self.applyState(change.toState)
            case .interactiveTransition:
                break
            }
        }

        applyState(controller.state)
    }

    private func animateStateTransition(to state: MinimizableSheetState) {
        let isMinimized = state == .minimized

        blurView.layer.removeAllAnimations()
        contentView.layer.removeAllAnimations()
        browser?.view.layer.removeAllAnimations()

        if isMinimized {
            blurView.isHidden = false
            contentView.isHidden = false
        }

        UIView.animate(
            withDuration: stateTransitionAnimationDuration,
            delay: 0,
            options: [.beginFromCurrentState, .curveEaseInOut, .allowUserInteraction]
        ) {
            self.blurView.alpha = isMinimized ? 1 : 0
            self.contentView.alpha = isMinimized ? 1 : 0
            self.browser?.view.alpha = isMinimized ? 0 : 1
        } completion: { _ in
            if !isMinimized {
                self.blurView.isHidden = true
                self.contentView.isHidden = true
            }
        }
    }

    private func applyState(_ state: MinimizableSheetState) {
        let isMinimized = state == .minimized
        blurView.alpha = isMinimized ? 1 : 0
        contentView.alpha = isMinimized ? 1 : 0
        blurView.isHidden = !isMinimized
        contentView.isHidden = !isMinimized
        browser?.view.alpha = isMinimized ? 0 : 1
    }
}

extension MinimizableSheetContentViewController: InAppBrowserDelegate {
    func inAppBrowserTitleChanged(_ browserContainer: InAppBrowserVC) {
        let dappInfo = browserContainer.dappInfo
        contentView.update(title: dappInfo?.shortTitle ?? browserContainer.displayTitle, iconUrl: dappInfo?.iconUrl)
    }
}
