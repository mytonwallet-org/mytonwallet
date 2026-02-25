//
//  WalletSeeAllCell.swift
//  MyTonWalletAir
//
//  Created by Sina on 10/24/24.
//

import UIKit
import UIComponents
import WalletContext

final class WalletSeeAllCell: UITableViewCell, WThemedView {
    public static let defaultHeight = CGFloat(44)
    private static let regular17Font = UIFont.systemFont(ofSize: 17, weight: .regular)

    private var onTap: (() -> Void)?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }
    
    func configure(onTap: @escaping () -> Void) {
        self.onTap = onTap
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
        
    private let seeAllLabel = configured(object: UILabel()) {
        $0.translatesAutoresizingMaskIntoConstraints = false
        $0.font = WalletSeeAllCell.regular17Font
        $0.text = lang("Show All Assets")
    }
        
    private lazy var highlightView = configured(object: WHighlightView()) {
        $0.translatesAutoresizingMaskIntoConstraints = false
        $0.addSubview(seeAllLabel)
        NSLayoutConstraint.activate([
            seeAllLabel.leadingAnchor.constraint(equalTo: $0.leadingAnchor, constant: 16),
            seeAllLabel.centerYAnchor.constraint(equalTo: $0.centerYAnchor)
        ])
    }
    
    private func setupViews() {
        selectionStyle = .none
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(cellSelected))
        tapGestureRecognizer.cancelsTouchesInView = false
        highlightView.addGestureRecognizer(tapGestureRecognizer)
        
        contentView.addStretchedToBounds(subview: highlightView)
        updateTheme()
    }
    
    func updateTheme() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        highlightView.backgroundColor = .clear
        highlightView.highlightBackgroundColor = WTheme.highlight
        seeAllLabel.textColor = WTheme.tint
    }
    
    @objc private func cellSelected() { onTap?() }
}
