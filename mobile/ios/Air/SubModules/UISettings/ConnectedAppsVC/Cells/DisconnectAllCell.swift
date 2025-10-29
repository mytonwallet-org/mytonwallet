//
//  DisconnectAllCell.swift
//  UISettings
//
//  Created by Sina on 8/30/24.
//

import Foundation
import UIKit
import UIComponents
import WalletCore
import WalletContext

public class DisconnectAllCell: UITableViewCell, WThemedView {

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private var isInModal = true

    private var containerView: WHighlightView!
    private var iconView: UIImageView!
    private var titleLabel: UILabel!
    private var separatorView: UIView!
    
    private func setupViews() {
        selectionStyle = .none
        contentView.isUserInteractionEnabled = true
        
        containerView = WHighlightView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.layer.cornerRadius = S.insetSectionCornerRadius
        containerView.layer.masksToBounds = true
        containerView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        containerView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(itemPressed)))

        contentView.addSubview(containerView)
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            containerView.leftAnchor.constraint(equalTo: contentView.leftAnchor, constant: 0),
            containerView.rightAnchor.constraint(equalTo: contentView.rightAnchor, constant: 0),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            containerView.heightAnchor.constraint(equalToConstant: 44)
        ])
        
        iconView = UIImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.layer.cornerRadius = 10
        iconView.image = UIImage(systemName: "hand.raised")
        containerView.addSubview(iconView)
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22),
            iconView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            iconView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 25)
        ])
        
        titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 17)
        titleLabel.text = lang("Disconnect All")
        containerView.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 68),
            titleLabel.centerYAnchor.constraint(equalTo: containerView.centerYAnchor)
        ])

        separatorView = UIView()
        separatorView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(separatorView)
        NSLayoutConstraint.activate([
            separatorView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            separatorView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            separatorView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 68),
            separatorView.heightAnchor.constraint(equalToConstant: 0.33)
        ])

        updateTheme()
    }
    
    public func updateTheme() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        containerView.backgroundColor = isInModal ? WTheme.groupedItem : WTheme.groupedItem
        containerView.highlightBackgroundColor = WTheme.highlight
        iconView.tintColor = WTheme.error
        titleLabel.textColor = WTheme.error
        separatorView.backgroundColor = WTheme.separator
    }
    
    private var onTap: (() -> Void)? = nil
    public func configure(isInModal: Bool, onTap: @escaping () -> Void) {
        if self.isInModal != isInModal {
            self.isInModal = isInModal
            updateTheme()
        }
        self.onTap = onTap
    }
    
    @objc func itemPressed() {
        onTap?()
    }
}
