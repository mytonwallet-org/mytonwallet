//
//  WalletSeeAllCell.swift
//  MyTonWalletAir
//
//  Created by Sina on 10/24/24.
//

import UIKit
import UIComponents
import WalletContext

final class WalletSeeAllCell: WHighlightCollectionViewCell {
    nonisolated public static let defaultHeight = CGFloat(44)
    private static let regular17Font = UIFont.systemFont(ofSize: 17, weight: .regular)
    private static let menuButtonConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .regular)
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { nil }
        
    private let seeAllLabel = configured(object: UILabel()) {
        $0.translatesAutoresizingMaskIntoConstraints = false
        $0.font = WalletSeeAllCell.regular17Font
        $0.text = lang("Show All Assets")
    }

    private let badge = BadgeView()

    private let menuButton = configured(object: UIButton(type: .system)) {
        $0.translatesAutoresizingMaskIntoConstraints = false
        $0.showsMenuAsPrimaryAction = true
        $0.setImage(UIImage(systemName: "ellipsis", withConfiguration: WalletSeeAllCell.menuButtonConfig), for: .normal)
        $0.isHidden = true
    }
    
    private func setupViews() {
        contentView.backgroundColor = .clear
        contentView.heightAnchor.constraint(equalToConstant: Self.defaultHeight).isActive = true
        contentView.addSubview(seeAllLabel)
        contentView.addSubview(badge)
        contentView.addSubview(menuButton)
        badge.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            seeAllLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            badge.centerYAnchor.constraint(equalTo: seeAllLabel.centerYAnchor, constant: 0.667),
            badge.leadingAnchor.constraint(equalTo: seeAllLabel.trailingAnchor, constant: 5),
            badge.trailingAnchor.constraint(lessThanOrEqualTo: menuButton.leadingAnchor, constant: -12),
            seeAllLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            seeAllLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            menuButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            menuButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            menuButton.widthAnchor.constraint(equalToConstant: 36),
            menuButton.heightAnchor.constraint(equalToConstant: 36),
        ])
        updateTheme()
    }

    func configure(tokensCount: Int, menu: UIMenu?) {
        badge.configure(
            text: "\(tokensCount)",
            foregroundColor: .tintColor,
            backgroundColor: .tintColor.withAlphaComponent(0.12)
        )
        menuButton.menu = menu
        menuButton.isHidden = menu == nil
    }
    
    private func updateTheme() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        highlightBackgroundColor = .air.highlight
        seeAllLabel.textColor = .tintColor
        menuButton.tintColor = .tintColor
    }
}
