//
//  AppearanceAppThemeView.swift
//  UISettings
//
//  Created by Sina on 7/9/24.
//

import UIKit
import UIComponents
import WalletContext
import WalletCore

class AppearanceAppThemeView: UIStackView, WThemedView {
    
    static let modes: [NightMode] = [.system, .light, .dark]
    var activeMode = AppStorageHelper.activeNightMode

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
        lbl.text = lang("APP THEME")
        return lbl
    }()
    
    private lazy var systemModeView = AppearanceAppThemeModeView(mode: .system, isSelected: activeMode == .system, onSelect: { [weak self] in
        self?.nightModeChanged()
    })
    private lazy var lightModeView = AppearanceAppThemeModeView(mode: .light, isSelected: activeMode == .light, onSelect: { [weak self] in
        self?.nightModeChanged()
    })
    private lazy var darkModeView = AppearanceAppThemeModeView(mode: .dark, isSelected: activeMode == .dark, onSelect: { [weak self] in
        self?.nightModeChanged()
    })
    
    private lazy var nightModeView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.spacing = 44
        stackView.addArrangedSubview(lightModeView)
        stackView.addArrangedSubview(systemModeView)
        stackView.addArrangedSubview(darkModeView)
        return stackView
    }()
    
    private lazy var schemaView: UIView = {
        let view = UIStackView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 10
        view.layer.masksToBounds = true
        view.addSubview(nightModeView)
        NSLayoutConstraint.activate([
            nightModeView.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            nightModeView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            nightModeView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16)
        ])
        return view
    }()
    
    private func setupViews() {
        axis = .vertical
        distribution = .fill
        addArrangedSubview(titleLabel, margin: .init(top: 5, left: 32, bottom: 5, right: 32))
        addArrangedSubview(schemaView, margin: .init(top: 0, left: 16, bottom: 0, right: 16))
        
        updateTheme()
    }

    public func updateTheme() {
        schemaView.backgroundColor = WTheme.groupedItem
    }
    
    private func nightModeChanged() {
        activeMode = AppStorageHelper.activeNightMode
        systemModeView.isSelected = activeMode == .system
        lightModeView.isSelected = activeMode == .light
        darkModeView.isSelected = activeMode == .dark
    }
}
