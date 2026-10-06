import UIKit
import WalletContext

/// Universal Search content shown underneath a host-owned search toolbar.
///
/// Search data is supplied by the host. The host keeps ownership of the toolbar
/// so the same glass views can remain alive across the Home/Search transition.
@MainActor
public final class UniversalSearchScreenViewController: UIViewController {
    private enum Metrics {
        static let searchFieldHeight: CGFloat = 48
        static let searchFieldToKeyboardSpacing: CGFloat = 10

        static var resultsBottomSafeArea: CGFloat {
            searchFieldHeight + searchFieldToKeyboardSpacing
        }
    }

    public var onSelect: UniversalSearchViewController.SelectionHandler? {
        get { resultsViewController.onSelect }
        set { resultsViewController.onSelect = newValue }
    }

    public var onHeaderAccessoryTap: UniversalSearchViewController.HeaderAccessoryHandler? {
        get { resultsViewController.onHeaderAccessoryTap }
        set { resultsViewController.onHeaderAccessoryTap = newValue }
    }

    public var onClose: (() -> Void)?

    private let resultsViewController: UniversalSearchViewController
    private var keyboardOverlap: CGFloat = 0

    public init(
        sections: [UniversalSearchSection] = [],
        preselectedItemID: String? = nil
    ) {
        resultsViewController = UniversalSearchViewController(
            sections: sections,
            preselectedItemID: preselectedItemID
        )
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .air.background
        configureResults()
        observeKeyboard()
    }

    public override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateResultsBottomInset()
    }

    public override func accessibilityPerformEscape() -> Bool {
        onClose?()
        return true
    }

    public func setSections(
        _ sections: [UniversalSearchSection],
        animated: Bool = true,
        completion: (() -> Void)? = nil
    ) {
        resultsViewController.setSections(
            sections,
            animated: animated,
            completion: completion
        )
    }

    public func setSections(
        _ sections: [UniversalSearchSection],
        preselectedItemID: String?,
        animated: Bool = true,
        completion: (() -> Void)? = nil
    ) {
        resultsViewController.setSections(
            sections,
            preselectedItemID: preselectedItemID,
            animated: animated,
            completion: completion
        )
    }

    public func setPreselectedItemID(_ itemID: String?) {
        resultsViewController.setPreselectedItemID(itemID)
    }

    @discardableResult
    public func selectPreselectedItem() -> Bool {
        resultsViewController.selectPreselectedItem()
    }

    private func configureResults() {
        addChild(resultsViewController)
        resultsViewController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(resultsViewController.view)
        NSLayoutConstraint.activate([
            resultsViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            resultsViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            resultsViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            resultsViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        resultsViewController.didMove(toParent: self)
    }

    private func observeKeyboard() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey]
            as? CGRect,
              let window = view.window
        else { return }

        let frameInWindow = window.convert(keyboardFrame, from: window.screen.coordinateSpace)
        let isDocked = frameInWindow.maxY >= window.bounds.maxY
            && frameInWindow.width >= window.bounds.width - 1
        let frameInView = view.convert(frameInWindow, from: window)
        keyboardOverlap = isDocked ? max(0, view.bounds.maxY - frameInView.minY) : 0
        animateResultsBottomInset(with: notification)
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        keyboardOverlap = 0
        animateResultsBottomInset(with: notification)
    }

    private func animateResultsBottomInset(with notification: Notification) {
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey]
            as? TimeInterval ?? 0.25
        let curve = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey]
            as? UInt ?? UInt(UIView.AnimationCurve.easeInOut.rawValue)
        let options = UIView.AnimationOptions(rawValue: curve << 16)

        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [options, .beginFromCurrentState, .allowUserInteraction]
        ) { [weak self] in
            self?.updateResultsBottomInset()
        }
    }

    private func updateResultsBottomInset() {
        let keyboardInset = max(0, keyboardOverlap - view.safeAreaInsets.bottom)
        resultsViewController.setBottomContentInset(
            Metrics.resultsBottomSafeArea + keyboardInset
        )
    }
}
