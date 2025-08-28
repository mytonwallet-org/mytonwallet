//
//  AppearanceAppThemeModeView.swift
//  UISettings
//
//  Created by Sina on 7/9/24.
//

import UIKit
import UIComponents
import WalletContext
import WalletCore

class AppearanceAppThemeModeView: UIStackView, WThemedView {

    private let mode: NightMode
    var isSelected: Bool {
        didSet {
            updateTheme()
        }
    }
    private var onSelect: () -> Void
    init(mode: NightMode, isSelected: Bool, onSelect: @escaping () -> Void) {
        self.mode = mode
        self.isSelected = isSelected
        self.onSelect = onSelect
        super.init(frame: .zero)
        setupViews()
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private lazy var modeImageView: UIImageView = {
        let img = UIImageView(image: mode.image)
        img.translatesAutoresizingMaskIntoConstraints = false
        img.layer.cornerRadius = 10
        img.layer.borderWidth = 2
        NSLayoutConstraint.activate([
            img.widthAnchor.constraint(equalToConstant: 60),
            img.heightAnchor.constraint(equalToConstant: 120),
        ])
        return img
    }()
    
    private lazy var titleLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = .systemFont(ofSize: 16, weight: .medium)
        lbl.textColor = WTheme.secondaryLabel
        lbl.text = mode.text
        lbl.textAlignment = .center
        return lbl
    }()
    
    private func setupViews() {
        translatesAutoresizingMaskIntoConstraints = false
        axis = .vertical
        spacing = 15
        
        addArrangedSubview(modeImageView)
        addArrangedSubview(titleLabel)

        updateTheme()
        
        isUserInteractionEnabled = true
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(modeSelected)))
    }

    public func updateTheme() {
        backgroundColor = .clear
        titleLabel.textColor = isSelected ? WTheme.tint : WTheme.secondaryLabel
        modeImageView.layer.borderColor = isSelected ? WTheme.tint.cgColor : UIColor.clear.cgColor
    }
    
    @objc private func modeSelected() {
        AppStorageHelper.activeNightMode = mode
        if let window = UIApplication.shared.sceneKeyWindow {
            window.overrideUserInterfaceStyle = mode.userInterfaceStyle
            window.updateTheme()
        }
        onSelect()
    }
}
