//
//  WalletVersionsHintCell.swift
//  UISettings
//
//  Created by Sina on 7/14/24.
//

import Foundation
import UIKit
import UIComponents
import WalletCore
import WalletContext

class WalletVersionsHintCell: UITableViewCell, WThemedView {

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var footerLabel: UILabel!

    private func setupViews() {
        selectionStyle = .none
        isUserInteractionEnabled = true
        contentView.isUserInteractionEnabled = true

        footerLabel = UILabel()
        footerLabel.numberOfLines = 0
        footerLabel.translatesAutoresizingMaskIntoConstraints = false
        footerLabel.isUserInteractionEnabled = true
        footerLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openTonOrgPressed)))
        addSubview(footerLabel)
        NSLayoutConstraint.activate([
            footerLabel.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            footerLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
            footerLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32),
            footerLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -32),
        ])

        updateTheme()
    }
    
    public func updateTheme() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        var hintText = lang("You have tokens on other versions of your wallet. You can import them from here.")
        if Language.current == .en {
            hintText += "\n\nRead more about types of wallet contracts on ton.org"
        }
        let hintAttributedString = NSMutableAttributedString(string: hintText, attributes: [
            .font: UIFont.systemFont(ofSize: 13),
            .foregroundColor: WTheme.secondaryLabel
        ])
        let tonOrgRange = (hintText as NSString).range(of: "ton.org")
        hintAttributedString.addAttribute(.foregroundColor, value: WTheme.tint, range: tonOrgRange)
        hintAttributedString.addAttribute(.link, value: "https://ton.org", range: tonOrgRange)
        footerLabel.attributedText = hintAttributedString
    }
    
    @objc func openTonOrgPressed() {
        let url = URL(string: "https://ton.org")!
        AppActions.openInBrowser(url, title: nil, injectTonConnect: false)
    }
}
