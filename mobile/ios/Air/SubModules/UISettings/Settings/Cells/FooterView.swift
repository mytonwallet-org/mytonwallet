
import UIKit
import WalletContext

final class FooterView: UICollectionReusableView {
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setupViews() {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "???"
        let bundleVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let versionLabel = UILabel()
        versionLabel.translatesAutoresizingMaskIntoConstraints = false
        versionLabel.text = "MyTonWallet Air v\(appVersion) (\(bundleVersion))"
        versionLabel.textColor = WTheme.secondaryLabel
        versionLabel.font = .systemFont(ofSize: 14)
        addSubview(versionLabel)
        NSLayoutConstraint.activate([
            versionLabel.topAnchor.constraint(equalTo: topAnchor),
            versionLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            versionLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ])
        backgroundColor = UIColor.clear
    }
}
