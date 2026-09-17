import UIKit
import UIComponents
import UIUniversalSearch
import UniversalSearchFeature

@MainActor
final class TopTabsSearchViewController: WViewController {
    let screen = UniversalSearchScreenViewController()
    lazy var session = UniversalSearchFeatureSession(screen: screen)
    var fieldConfiguration: UniversalSearchFieldConfiguration
    var restoresKeyboard = true
    var returnDeadline: ContinuousClock.Instant?
    var expirationTask: Task<Void, Never>?
    var onAppear: (() -> Void)?

    init(configuration: UniversalSearchFieldConfiguration) {
        fieldConfiguration = configuration
        super.init(nibName: nil, bundle: nil)
        // Keep the bar in the transition so result items animate with UIKit's push.
        navigationItem.hidesBackButton = true
        navigationItem.backButtonDisplayMode = .minimal
        navigationItem.largeTitleDisplayMode = .never
        configureNavigationItemWithTransparentBackground()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(screen)
        screen.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(screen.view)
        NSLayoutConstraint.activate([
            screen.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            screen.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            screen.view.topAnchor.constraint(equalTo: view.topAnchor),
            screen.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        screen.didMove(toParent: self)
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        updateTopInset()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateTopInset()
    }

    private func updateTopInset() {
        // The empty bar must not add space above the search results.
        let topInset = -(navigationController?.navigationBar.bounds.height ?? 0)
        if additionalSafeAreaInsets.top != topInset {
            additionalSafeAreaInsets.top = topInset
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        onAppear?()
    }

    func stop() {
        expirationTask?.cancel()
        expirationTask = nil
        session.stop()
    }

    deinit {
        expirationTask?.cancel()
    }
}
