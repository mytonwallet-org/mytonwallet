//
//  WNavigationBar.swift
//  UIComponents
//
//  Created by Sina on 4/29/23.
//

import UIKit
import WalletContext

public final class WNavigationBar: WTouchPassView {

    public let titleLabel = UILabel()
    public let subtitleLabel = UILabel()
    public let leadingButton: WNavigationBarButton
    public let backButton = UIButton(type: .system)
    private let trailingButtons: [WNavigationBarButton]

    private let onBackPressed: () -> Void
    private let blurView = WBlurView()
    private let separatorView = UIView()
    private let contentView = UIView()
    private let titleStackView = UIStackView()
    private let titleButton = UIButton(type: .system)
    private var titleMenu: UIMenu? {
        didSet {
            updateTitleMenu()
        }
    }

    public init(
        leadingButton: WNavigationBarButton,
        trailingButton: WNavigationBarButton,
        onBackPressed: @escaping () -> Void
    ) {
        self.leadingButton = leadingButton
        self.trailingButtons = [trailingButton]
        self.onBackPressed = onBackPressed
        super.init(frame: .zero)
        shouldPassTouches = false
        setupViews(trailingButtons: self.trailingButtons)
    }

    public init(
        leadingButton: WNavigationBarButton,
        trailingButtons: [WNavigationBarButton],
        onBackPressed: @escaping () -> Void
    ) {
        self.leadingButton = leadingButton
        self.trailingButtons = trailingButtons
        self.onBackPressed = onBackPressed
        super.init(frame: .zero)
        shouldPassTouches = false
        setupViews(trailingButtons: self.trailingButtons)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews(trailingButtons: [WNavigationBarButton]) {
        translatesAutoresizingMaskIntoConstraints = false

        backgroundColor = .clear
        blurView.alpha = 1
        addSubview(blurView)

        NSLayoutConstraint.activate([
            blurView.leftAnchor.constraint(equalTo: leftAnchor),
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.rightAnchor.constraint(equalTo: rightAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        separatorView.translatesAutoresizingMaskIntoConstraints = false
        separatorView.backgroundColor = .air.separator
        separatorView.alpha = 1
        addSubview(separatorView)
        NSLayoutConstraint.activate([
            separatorView.bottomAnchor.constraint(equalTo: bottomAnchor),
            separatorView.leftAnchor.constraint(equalTo: leftAnchor),
            separatorView.rightAnchor.constraint(equalTo: rightAnchor),
            separatorView.heightAnchor.constraint(equalToConstant: 0.33),
        ])

        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.backgroundColor = .clear
        addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.leftAnchor.constraint(equalTo: leftAnchor),
            contentView.rightAnchor.constraint(equalTo: rightAnchor),
            contentView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor).withPriority(.init(999)),
            contentView.heightAnchor.constraint(equalToConstant: 60)
        ])

        titleStackView.translatesAutoresizingMaskIntoConstraints = false
        titleStackView.axis = .vertical
        titleStackView.alignment = .center
        titleStackView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleStackView.isUserInteractionEnabled = false
        titleStackView.spacing = 2

        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleStackView.addArrangedSubview(titleLabel)

        subtitleLabel.textColor = .air.secondaryLabel
        subtitleLabel.font = .systemFont(ofSize: 13, weight: .regular)
        titleStackView.addArrangedSubview(subtitleLabel)

        titleButton.translatesAutoresizingMaskIntoConstraints = false
        titleButton.backgroundColor = .clear
        titleButton.showsMenuAsPrimaryAction = true
        titleButton.isUserInteractionEnabled = false
        titleButton.addSubview(titleStackView)
        contentView.addSubview(titleButton)

        NSLayoutConstraint.activate([
            titleButton.centerXAnchor.constraint(equalTo: contentView.layoutMarginsGuide.centerXAnchor),
            titleButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            titleStackView.leadingAnchor.constraint(equalTo: titleButton.leadingAnchor),
            titleStackView.trailingAnchor.constraint(equalTo: titleButton.trailingAnchor),
            titleStackView.topAnchor.constraint(equalTo: titleButton.topAnchor),
            titleStackView.bottomAnchor.constraint(equalTo: titleButton.bottomAnchor)
        ])

        contentView.addSubview(leadingButton.view)
        NSLayoutConstraint.activate([
            leadingButton.view.leadingAnchor.constraint(equalTo: leadingAnchor, constant: IOS_26_MODE_ENABLED ? 12 : 16),
            leadingButton.view.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            leadingButton.view.widthAnchor.constraint(greaterThanOrEqualTo: leadingButton.view.heightAnchor),
        ])
        if IOS_26_MODE_ENABLED {
            NSLayoutConstraint.activate([
                leadingButton.view.widthAnchor.constraint(equalToConstant: 44),
                leadingButton.view.heightAnchor.constraint(equalToConstant: 44),
            ])
        }
        leadingButton.view.setContentCompressionResistancePriority(.required, for: .horizontal)

        setupTrailingButtons(trailingButtons)

        let attributedString = NSMutableAttributedString()
        let backArrowImage = UIImage(systemName: "chevron.backward")!
        let imageAttachment = NSTextAttachment(image: backArrowImage)
        let imageAttachmentString = NSMutableAttributedString(attachment: imageAttachment)
        imageAttachmentString.addAttributes([
            .font: UIFont.systemFont(ofSize: 23, weight: .medium),
        ], range: NSRange(location: 0, length: imageAttachmentString.length))
        attributedString.append(imageAttachmentString)
        let titleString = NSAttributedString(string: " \(lang("Back"))", attributes: [
            .font: UIFont.systemFont(ofSize: 17, weight: .regular),
            .baselineOffset: 2
        ])
        attributedString.append(titleString)
        backButton.setAttributedTitle(attributedString, for: .normal)
        backButton.tintColor = .tintColor
        backButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        backButton.contentHorizontalAlignment = .leading
        backButton.addTarget(self, action: #selector(backButtonPressed), for: .touchUpInside)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(backButton)
        NSLayoutConstraint.activate([
            backButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            backButton.topAnchor.constraint(equalTo: contentView.topAnchor),
            backButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            backButton.trailingAnchor.constraint(lessThanOrEqualTo: titleStackView.leadingAnchor, constant: -4),
        ])

        updateTitleMenu()
    }

    private func setupTrailingButtons(_ trailingButtons: [WNavigationBarButton]) {
        guard !trailingButtons.isEmpty else { return }
        let trailingButtonsStackView = UIStackView()
        trailingButtonsStackView.translatesAutoresizingMaskIntoConstraints = false
        trailingButtonsStackView.axis = .horizontal
        trailingButtonsStackView.alignment = .center
        trailingButtonsStackView.spacing = IOS_26_MODE_ENABLED ? 8 : 0
        contentView.addSubview(trailingButtonsStackView)
        for trailingButton in trailingButtons {
            trailingButtonsStackView.addArrangedSubview(trailingButton.view)
            trailingButton.view.widthAnchor.constraint(greaterThanOrEqualTo: trailingButton.view.heightAnchor).isActive = true
            if IOS_26_MODE_ENABLED {
                NSLayoutConstraint.activate([
                    trailingButton.view.widthAnchor.constraint(equalToConstant: 44),
                    trailingButton.view.heightAnchor.constraint(equalToConstant: 44),
                ])
            }
            trailingButton.view.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        NSLayoutConstraint.activate([
            trailingButtonsStackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: IOS_26_MODE_ENABLED ? -12 : -8),
            trailingButtonsStackView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            trailingButtonsStackView.leadingAnchor.constraint(greaterThanOrEqualTo: titleStackView.trailingAnchor, constant: 4),
        ])
        trailingButtonsStackView.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    @objc private func backButtonPressed() {
        onBackPressed()
    }

    public func setTitleMenu(_ menu: UIMenu?) {
        titleMenu = menu
    }

    private func updateTitleMenu() {
        titleButton.menu = titleMenu
        titleButton.showsMenuAsPrimaryAction = titleMenu != nil
        titleButton.isUserInteractionEnabled = titleMenu != nil
    }
}
