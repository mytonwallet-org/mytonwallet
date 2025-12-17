//
//  AssetsAndActivityBaseCurrencyCell.swift
//  UISettings
//
//  Created by Sina on 7/4/24.
//

import Foundation
import UIKit
import UIComponents
import WalletCore
import WalletContext

class AssetsAndActivityBaseCurrencyCell: UITableViewCell {
    
    private var isInModal: Bool = true
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private var separatorView: UIView = {
        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = WTheme.separator
        return separator
    }()
    
    private var baseCurrencyValueLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = .systemFont(ofSize: 17)
        lbl.text = TokenStore.baseCurrency.rawValue
        return lbl
    }()

    private var rightArrow: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "RightArrowIcon", in: AirBundle, compatibleWith: nil)!.withRenderingMode(.alwaysTemplate))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var baseCurrencyValueView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.alignment = .center
        stackView.spacing = 6
        stackView.addArrangedSubview(baseCurrencyValueLabel)
        stackView.addArrangedSubview(rightArrow)
        return stackView
    }()
    
    private lazy var baseCurrencyView: WHighlightView = {
        let v = WHighlightView()
        v.translatesAutoresizingMaskIntoConstraints = false
        let baseCurrencyLabel = UILabel()
        baseCurrencyLabel.translatesAutoresizingMaskIntoConstraints = false
        baseCurrencyLabel.text = lang("Base Currency")
        baseCurrencyLabel.font = .systemFont(ofSize: 17)
        v.addSubview(baseCurrencyLabel)
        v.addSubview(baseCurrencyValueView)
        v.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(baseCurrencyTapped)))
        NSLayoutConstraint.activate([
            v.heightAnchor.constraint(equalToConstant: S.sectionItemHeight),
            baseCurrencyLabel.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 16),
            baseCurrencyLabel.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            baseCurrencyValueView.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -20),
            baseCurrencyValueView.centerYAnchor.constraint(equalTo: v.centerYAnchor)
        ])
        return v
    }()
    
    private var hideTinyTransfersSwitch: UISwitch = {
        let switchControl = UISwitch()
        switchControl.translatesAutoresizingMaskIntoConstraints = false
        switchControl.isOn = AppStorageHelper.hideTinyTransfers
        return switchControl
    }()

    private lazy var optionsView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = S.insetSectionCornerRadius
        view.layer.masksToBounds = true
        view.addSubview(baseCurrencyView)
        view.addSubview(separatorView)
        let hideTinyTransfersLabel = UILabel()
        hideTinyTransfersLabel.translatesAutoresizingMaskIntoConstraints = false
        hideTinyTransfersLabel.text = lang("Hide Tiny Transfers")
        hideTinyTransfersLabel.font = .systemFont(ofSize: 17)
        view.addSubview(hideTinyTransfersLabel)
        view.addSubview(hideTinyTransfersSwitch)
        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(equalToConstant: 2 * S.sectionItemHeight),
            separatorView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            separatorView.heightAnchor.constraint(equalToConstant: 0.33),
            separatorView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            separatorView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            baseCurrencyView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            baseCurrencyView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            baseCurrencyView.topAnchor.constraint(equalTo: view.topAnchor),
            hideTinyTransfersLabel.heightAnchor.constraint(equalToConstant: S.sectionItemHeight),
            hideTinyTransfersLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hideTinyTransfersLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            hideTinyTransfersSwitch.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            hideTinyTransfersSwitch.centerYAnchor.constraint(equalTo: hideTinyTransfersLabel.centerYAnchor),
        ])
        return view
    }()
    
    private var hintLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.numberOfLines = 0
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        let attributes: [NSAttributedString.Key: Any] = [
            .paragraphStyle: paragraphStyle,
            .font: UIFont.systemFont(ofSize: 13)
        ]
        let attributedText = NSAttributedString(string: lang("Don’t show transactions of less than $0.01. Such small transactions are often used for spam and scam."),
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
        stackView.addArrangedSubview(optionsView, margin: .init(top: 0, left: 0, bottom: 0, right: 0))
        stackView.addArrangedSubview(hintLabel, margin: .init(top: 5, left: 16, bottom: 0, right: 16))
        hideTinyTransfersSwitch.addTarget(self,
                                          action: #selector(hideTinyTransfersSwitched),
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
        baseCurrencyValueLabel.textColor = WTheme.secondaryLabel
        rightArrow.tintColor = WTheme.secondaryLabel
        baseCurrencyView.highlightBackgroundColor = WTheme.highlight
        baseCurrencyView.backgroundColor = optionsView.backgroundColor
    }

    @objc private func hideTinyTransfersSwitched() {
        AppStorageHelper.hideTinyTransfers = hideTinyTransfersSwitch.isOn
        WalletCoreData.notify(event: .hideTinyTransfersChanged)
    }
    
    @objc private func baseCurrencyTapped() {
        onBaseCurrencyTap?()
    }
    
    private var onBaseCurrencyTap: (() -> Void)? = nil
    func configure(isInModal: Bool, baseCurrency: MBaseCurrency?, onBaseCurrencyTap: @escaping () -> Void) {
        self.onBaseCurrencyTap = onBaseCurrencyTap
        if self.isInModal != isInModal {
            self.isInModal = isInModal
            updateTheme()
        }
        baseCurrencyValueLabel.text = baseCurrency?.symbol
    }
}
