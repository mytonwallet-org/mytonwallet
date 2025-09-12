//
//  AppearanceOtherSettingsView.swift
//  UISettings
//
//  Created by Sina on 6/30/24.
//

import UIKit
import UIComponents
import WalletContext
import WalletCore

class AppearanceOtherSettingsView: UIStackView, WThemedView {
    
    init() {
        super.init(frame: .zero)
        setupViews()
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private var titleLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = .systemFont(ofSize: 13)
        lbl.textColor = WTheme.secondaryLabel
        lbl.text = lang("Other Settings").uppercased()
        return lbl
    }()

    private var separatorView: UIView = {
        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = WTheme.separator
        return separator
    }()
    
    private var animationsSwitch: UISwitch = {
        let switchControl = UISwitch()
        switchControl.translatesAutoresizingMaskIntoConstraints = false
        switchControl.isOn = AppStorageHelper.animations
        return switchControl
    }()
    
    private var soundsSwitch: UISwitch = {
        let switchControl = UISwitch()
        switchControl.translatesAutoresizingMaskIntoConstraints = false
        switchControl.isOn = AppStorageHelper.sounds
        return switchControl
    }()

    private lazy var otherSettingsView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 10
        let animationsLabel = UILabel()
        animationsLabel.translatesAutoresizingMaskIntoConstraints = false
        animationsLabel.text = lang("Animations")
        animationsLabel.font = .systemFont(ofSize: 17)
        view.addSubview(animationsLabel)
        view.addSubview(animationsSwitch)
        view.addSubview(separatorView)
        let soundsLabel = UILabel()
        soundsLabel.translatesAutoresizingMaskIntoConstraints = false
        soundsLabel.text = lang("Sounds")
        soundsLabel.font = .systemFont(ofSize: 17)
        view.addSubview(soundsLabel)
        view.addSubview(soundsSwitch)
        NSLayoutConstraint.activate([
            separatorView.topAnchor.constraint(equalTo: view.topAnchor, constant: 44),
            separatorView.heightAnchor.constraint(equalToConstant: 0.33),
            separatorView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -44),
            separatorView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            separatorView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            animationsLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 11),
            animationsLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            animationsSwitch.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            animationsSwitch.centerYAnchor.constraint(equalTo: animationsLabel.centerYAnchor),
            soundsLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -11),
            soundsLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            soundsSwitch.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            soundsSwitch.centerYAnchor.constraint(equalTo: soundsLabel.centerYAnchor),
        ])
        return view
    }()
    
    private func setupViews() {
        axis = .vertical
        distribution = .fill
        addArrangedSubview(titleLabel, margin: .init(top: 5, left: 32, bottom: 5, right: 32))
        addArrangedSubview(otherSettingsView, margin: .init(top: 0, left: 16, bottom: 0, right: 16))
        animationsSwitch.addTarget(self, action: #selector(animationsSwitched), for: .valueChanged)
        soundsSwitch.addTarget(self, action: #selector(soundsSwitched), for: .valueChanged)
        updateTheme()
    }

    public func updateTheme() {
        otherSettingsView.backgroundColor = WTheme.groupedItem
    }

    @objc private func animationsSwitched() {
        AppStorageHelper.animations = animationsSwitch.isOn
    }

    @objc private func soundsSwitched() {
        AppStorageHelper.sounds = soundsSwitch.isOn
    }
}
