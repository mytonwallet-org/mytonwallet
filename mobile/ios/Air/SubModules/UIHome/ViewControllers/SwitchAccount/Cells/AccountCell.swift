//
//  AccountCell.swift
//  UIHome
//
//  Created by Sina on 5/8/24.
//

import Foundation
import UIKit
import UIComponents
import WalletCore
import WalletContext

class AccountCell: UITableViewCell, WThemedView {

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private var onSelect: (() -> Void)? = nil
    private var stackView: WHighlightStackView!
    private var img: IconView!
    private var lbl: UILabel!
    
    private var badge: BadgeView = BadgeView()

    private lazy var titleAndBadge: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(lbl)
        view.addSubview(badge)
        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: lbl.trailingAnchor, constant: 6),
            badge.centerYAnchor.constraint(equalTo: lbl.centerYAnchor, constant: 1),
            lbl.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            lbl.topAnchor.constraint(equalTo: view.topAnchor),
            lbl.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            badge.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor),
        ])
        return view
    }()
    
    private var separator: UIView!
    private func setupViews() {
        selectionStyle = .none

        stackView = WHighlightStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.backgroundColor = .clear
        stackView.axis = .horizontal
        stackView.distribution = .fillProportionally
        stackView.alignment = .center
        stackView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(accountSelected)))
        stackView.highlightingTime = 0
        stackView.unhighlightingTime = 0
        contentView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        
        lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = .systemFont(ofSize: 17, weight: .regular)
        stackView.addArrangedSubview(titleAndBadge, spacing: 16)
        
        img = IconView(size: 30)
        stackView.addArrangedSubview(img, margin: .init(top: 0, left: 5, bottom: 0, right: 12))

        separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)
        NSLayoutConstraint.activate([
            separator.heightAnchor.constraint(equalToConstant: 0.333),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        
        updateTheme()
    }
    
    func configure(account: MAccount?, hideSeparator: Bool, onSelect: @escaping () -> Void) {
        self.onSelect = onSelect
        img.config(with: account, showIcon: true)
        if let account {
            lbl.text = account.displayName
            badge.configureWithAccountType(account.type)
        } else {
            lbl.text = lang("Add Account")
            badge.configureHidden()
        }
        separator.isHidden = hideSeparator
    }
    
    public func updateTheme() {
        stackView.highlightBackgroundColor = .airBundle("AltHighlightColor")
        separator.backgroundColor = .airBundle("MenuSeparator")
    }
    
    @objc private func accountSelected() {
        onSelect?()
    }
    
    override var isHighlighted: Bool {
        set {
            stackView?.isHighlighted = newValue
        }
        get {
            stackView?.isHighlighted ?? false
        }
    }
}
