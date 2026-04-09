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
    nonisolated public static let defaultHeight = CGFloat(48)
    private static let regular17Font = UIFont.systemFont(ofSize: 17, weight: .regular)
    private static let leadingIconConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
    private static let menuButtonConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .regular)
    private static let leadingIconToTextSpacing = CGFloat(18)
    private static let verticalOffset = CGFloat(-2)
    private static let menuButtonSideLength = CGFloat(36)
    private static let menuButtonTrailingInset = CGFloat(8)
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { nil }

    private let leadingIconView = configured(object: UIImageView(
        image: UIImage(systemName: "circle.grid.2x2", withConfiguration: WalletSeeAllCell.leadingIconConfig)
    )) {
        $0.translatesAutoresizingMaskIntoConstraints = false
        $0.contentMode = .scaleAspectFit
    }
        
    private let seeAllLabel = configured(object: UILabel()) {
        $0.translatesAutoresizingMaskIntoConstraints = false
        $0.font = WalletSeeAllCell.regular17Font
        $0.text = lang("Show All Assets")
    }

    private let badge = BadgeView()
    private var menuButtonWidthConstraint: NSLayoutConstraint!
    private var menuButtonHeightConstraint: NSLayoutConstraint!
    private var menuButtonTrailingConstraint: NSLayoutConstraint!

    private let menuButton = configured(object: UIButton(type: .system)) {
        $0.translatesAutoresizingMaskIntoConstraints = false
        $0.showsMenuAsPrimaryAction = true
        $0.setImage(UIImage(systemName: "ellipsis", withConfiguration: WalletSeeAllCell.menuButtonConfig), for: .normal)
        $0.isHidden = true
    }
    
    private func setupViews() {
        contentView.backgroundColor = .clear
        contentView.heightAnchor.constraint(equalToConstant: Self.defaultHeight).isActive = true
        contentView.addSubview(leadingIconView)
        contentView.addSubview(seeAllLabel)
        contentView.addSubview(badge)
        contentView.addSubview(menuButton)
        badge.translatesAutoresizingMaskIntoConstraints = false
        menuButtonWidthConstraint = menuButton.widthAnchor.constraint(equalToConstant: Self.menuButtonSideLength)
        menuButtonHeightConstraint = menuButton.heightAnchor.constraint(equalToConstant: Self.menuButtonSideLength)
        menuButtonTrailingConstraint = menuButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Self.menuButtonTrailingInset)
        NSLayoutConstraint.activate([
            leadingIconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            leadingIconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: Self.verticalOffset),
            leadingIconView.widthAnchor.constraint(equalToConstant: 24),
            leadingIconView.heightAnchor.constraint(equalToConstant: 24),
            seeAllLabel.leadingAnchor.constraint(equalTo: leadingIconView.trailingAnchor, constant: Self.leadingIconToTextSpacing),
            seeAllLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: Self.verticalOffset),
            badge.centerYAnchor.constraint(equalTo: seeAllLabel.centerYAnchor, constant: 0.667),
            badge.leadingAnchor.constraint(equalTo: seeAllLabel.trailingAnchor, constant: 4),
            badge.trailingAnchor.constraint(lessThanOrEqualTo: menuButton.leadingAnchor, constant: -12),
            menuButtonTrailingConstraint,
            menuButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: Self.verticalOffset),
            menuButtonWidthConstraint,
            menuButtonHeightConstraint,
        ])
        updateTheme()
    }

    func configure(tokensCount: Int, menu: UIMenu?) {
        configure(
            title: lang("Show All Assets"),
            count: tokensCount,
            leadingIconSystemName: "circle.grid.2x2",
            menu: menu
        )
    }

    func configureCollectibles(title: String, collectiblesCount: Int) {
        configure(
            title: title,
            count: collectiblesCount,
            leadingIconSystemName: "square.grid.2x2",
            menu: nil
        )
    }

    private func configure(title: String, count: Int, leadingIconSystemName: String, menu: UIMenu?) {
        seeAllLabel.text = title
        leadingIconView.image = UIImage(systemName: leadingIconSystemName, withConfiguration: Self.leadingIconConfig)
        badge.configure(
            text: "\(count)",
            foregroundColor: .tintColor,
            backgroundColor: .tintColor.withAlphaComponent(0.12)
        )

        let isMenuVisible = menu != nil
        menuButton.menu = menu
        menuButton.isHidden = !isMenuVisible
        menuButtonWidthConstraint.constant = isMenuVisible ? Self.menuButtonSideLength : 0
        menuButtonHeightConstraint.constant = isMenuVisible ? Self.menuButtonSideLength : 0
        menuButtonTrailingConstraint.constant = isMenuVisible ? -Self.menuButtonTrailingInset : 0
    }
    
    private func updateTheme() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        highlightBackgroundColor = .air.highlight
        leadingIconView.tintColor = .tintColor
        seeAllLabel.textColor = .tintColor
        menuButton.tintColor = .tintColor
    }
}
