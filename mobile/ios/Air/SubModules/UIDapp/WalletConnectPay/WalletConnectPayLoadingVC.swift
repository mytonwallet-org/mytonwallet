import UIKit
import UIComponents
import WalletCore
import WalletContext

final class WalletConnectPayLoadingVC: WViewController {
    private var onCancel: (() -> Void)?

    private lazy var activityIndicator = {
        let indicator = WActivityIndicator()
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    private lazy var titleLabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = lang("Payment")
        label.textColor = .label
        label.font = .systemFont(ofSize: 20, weight: .semibold)
        label.textAlignment = .center
        return label
    }()

    private lazy var subtitleLabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = lang("Please wait")
        label.textColor = .air.secondaryLabel
        label.font = .systemFont(ofSize: 16, weight: .regular)
        label.textAlignment = .center
        return label
    }()

    init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
    }

    private func setupViews() {
        navigationItem.title = lang("Payment")
        addCloseNavigationItemIfNeeded()
        if navigationItem.rightBarButtonItem != nil {
            navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in
                self?.cancel()
            })
        }
        view.backgroundColor = .air.sheetBackground

        view.addSubview(activityIndicator)
        view.addSubview(titleLabel)
        view.addSubview(subtitleLabel)
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -48),
            titleLabel.topAnchor.constraint(equalTo: activityIndicator.bottomAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            subtitleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        ])
        activityIndicator.startAnimating(animated: false)
    }

    private func cancel() {
        onCancel?()
        onCancel = nil
    }
}
