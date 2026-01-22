//
//  WalletCreatedView.swift
//  UIWalletHome
//
//  Created by Sina on 4/21/23.
//

import UIKit
import WalletContext

public class WalletCreatedView: WTouchPassView {

    public init() {
        super.init(frame: CGRect.zero)
        setupView()
    }

    override public init(frame: CGRect) {
        fatalError()
    }
    
    required public init?(coder: NSCoder) {
        fatalError()
    }

    var titleLabel: UILabel!
    var subtitleLabel: UILabel!

    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 17, weight: .medium)
        titleLabel.textAlignment = .center
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 38),
            titleLabel.leftAnchor.constraint(equalTo: leftAnchor),
            titleLabel.rightAnchor.constraint(equalTo: rightAnchor)
        ])

        subtitleLabel = UILabel()
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 14)
        subtitleLabel.numberOfLines = 2
        subtitleLabel.textAlignment = .center
        addSubview(subtitleLabel)
        NSLayoutConstraint.activate([
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            subtitleLabel.leftAnchor.constraint(equalTo: leftAnchor),
            subtitleLabel.rightAnchor.constraint(equalTo: rightAnchor),
            subtitleLabel.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        
        titleLabel.attributedText = NSAttributedString(
            string: lang("No Activity"),
            attributes: [
                .kern: -0.26,
                .font: titleLabel.font!,
                .foregroundColor: WTheme.primaryLabel
            ]
        )
        subtitleLabel.attributedText = NSAttributedString(
            string: lang("There is no activity history for this wallet yet."),
            attributes: [
                .kern: -0.09,
                .font: subtitleLabel.font!,
                .foregroundColor: WTheme.secondaryLabel
            ]
        )
    }
}
