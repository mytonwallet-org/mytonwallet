//
//  DappCell.swift
//  UISettings
//
//  Created by Sina on 8/30/24.
//

import Foundation
import UIKit
import UIComponents
import WalletCore
import WalletContext

public class DappCell: UITableViewCell, WThemedView {

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private var isInModal = true

    private var containerView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    private var appImageView: UIImageView!
    private var titleLabel: UILabel!
    private var subtitleLabel: UILabel!
    private var separatorView: UIView!
    
    private func setupViews() {
        selectionStyle = .none
        contentView.isUserInteractionEnabled = true
        
        addSubview(containerView)
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.leftAnchor.constraint(equalTo: leftAnchor, constant: 0),
            containerView.rightAnchor.constraint(equalTo: rightAnchor, constant: 0),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            containerView.heightAnchor.constraint(equalToConstant: 56)
        ])
        
        appImageView = UIImageView()
        appImageView.translatesAutoresizingMaskIntoConstraints = false
        appImageView.layer.cornerRadius = 10
        appImageView.layer.masksToBounds = true
        containerView.addSubview(appImageView)
        NSLayoutConstraint.activate([
            appImageView.widthAnchor.constraint(equalToConstant: 40),
            appImageView.heightAnchor.constraint(equalToConstant: 40),
            appImageView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8),
            appImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16)
        ])
        
        titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 17)
        containerView.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 68),
            titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8)
        ])
        
        subtitleLabel = UILabel()
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 13)
        containerView.addSubview(subtitleLabel)
        NSLayoutConstraint.activate([
            subtitleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 68),
            subtitleLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -8)
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
        separatorView.backgroundColor = WTheme.separator
        titleLabel.textColor = WTheme.primaryLabel
        subtitleLabel.textColor = WTheme.secondaryLabel
    }
    
    public func configure(dapp: ApiDapp,
                          isFirst: Bool,
                          isLast: Bool,
                          isInModal: Bool) {
        if self.isInModal != isInModal {
            self.isInModal = isInModal
            updateTheme()
        }
        appImageView.kf.setImage(with: URL(string: dapp.iconUrl))
        titleLabel.text = dapp.name
        subtitleLabel.text = dapp.url
        separatorView.isHidden = isLast
    }
}
