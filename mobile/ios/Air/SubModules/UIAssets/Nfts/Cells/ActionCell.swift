
import UIKit
import WalletCore
import WalletContext
import UIComponents


class ActionCell: WHighlightCollectionViewCell, WThemedView {
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private var label: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = .systemFont(ofSize: 16, weight: .regular)
        return lbl
    }()
    
    private func setupViews() {
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
        ])
        updateTheme()
    }
    
    func updateTheme() {
        backgroundColor = .clear
        label.textColor = WTheme.tint
    }
    
    func configure(with title: String) {
        self.label.text = title
    }
}
