
import UIKit
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
        lbl.font = .systemFont(ofSize: 17, weight: .regular)
        return lbl
    }()
    
    private func setupViews() {
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
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
