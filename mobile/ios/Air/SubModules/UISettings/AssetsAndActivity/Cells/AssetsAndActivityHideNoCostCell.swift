//
//  AssetsAndActivityHideNoCostCell.swift
//  UISettings
//
//  Created by Sina on 7/5/24.
//

import Foundation
import UIKit
import UIComponents
import WalletCore
import WalletContext

final class AssetsAndActivityHideNoCostCell: UITableViewCell {
    
    private var isInModal: Bool = true
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private var hideNoCostSwitch: UISwitch = {
        let switchControl = UISwitch()
        switchControl.translatesAutoresizingMaskIntoConstraints = false
        switchControl.isOn = AppStorageHelper.hideNoCostTokens
        return switchControl
    }()

    private lazy var optionsView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = S.insetSectionCornerRadius
        view.layer.masksToBounds = true
        let hideNoCostLabel = UILabel()
        hideNoCostLabel.translatesAutoresizingMaskIntoConstraints = false
        hideNoCostLabel.text = lang("Hide Tokens With No Cost")
        hideNoCostLabel.font = .systemFont(ofSize: 17)
        view.addSubview(hideNoCostLabel)
        view.addSubview(hideNoCostSwitch)
        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(equalToConstant: S.sectionItemHeight),
            hideNoCostLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            hideNoCostLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            hideNoCostSwitch.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            hideNoCostSwitch.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        return view
    }()
    
    private var hintLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.numberOfLines = 0
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2
        let attributes: [NSAttributedString.Key: Any] = [
            .paragraphStyle: paragraphStyle,
            .font: UIFont.systemFont(ofSize: 13)
        ]
        let attributedText = NSAttributedString(string: lang("Don’t show tokens on your account with value less than $0.01. You can also selectively enable and disable particular tokens using the list below."),
                                                attributes: attributes)
        lbl.attributedText = attributedText
        return lbl
    }()
    
    private func setupViews() {
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.distribution = .fill
        stackView.addArrangedSubview(optionsView, margin: .init(top: 13, left: 0, bottom: 0, right: 0))
        stackView.addArrangedSubview(hintLabel, margin: .init(top: 7, left: 16, bottom: 0, right: 16))
        hideNoCostSwitch.addTarget(self,
                                   action: #selector(hideNoCostSwitched),
                                   for: .valueChanged)
        contentView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leftAnchor.constraint(equalTo: contentView.leftAnchor),
            stackView.rightAnchor.constraint(equalTo: contentView.rightAnchor),
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        updateTheme()
    }

    public func updateTheme() {
        if isInModal {
            optionsView.backgroundColor = WTheme.groupedItem
        } else {
            optionsView.backgroundColor = WTheme.groupedItem
        }
        hintLabel.textColor = WTheme.secondaryLabel
    }

    @objc private func hideNoCostSwitched() {
        AppStorageHelper.hideNoCostTokens = hideNoCostSwitch.isOn
        onChangedHideNoCost?(hideNoCostSwitch.isOn)
    }
    
    private var onChangedHideNoCost: ((Bool) -> Void)? = nil
    func configure(isInModal: Bool, onChangedHideNoCost: @escaping (Bool) -> Void) {
        self.onChangedHideNoCost = onChangedHideNoCost
        if self.isInModal != isInModal {
            self.isInModal = isInModal
            updateTheme()
        }
    }
}
