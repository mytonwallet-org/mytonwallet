//
//  AppearanceAppIconView.swift
//  UISettings
//
//  Created by Sina on 6/30/24.
//

import UIKit
import UIComponents
import WalletContext

fileprivate let appIcons = ["AppIcon2", "AppIcon"]
fileprivate let primaryIcon = "AppIcon"

class AppearanceAppIconView: UIStackView, WThemedView {
    
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
        lbl.text = lang("APP ICON")
        return lbl
    }()
    
    private var appIconsView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.distribution = .fill
        stackView.alignment = .center
        stackView.spacing = 24
        stackView.layer.cornerRadius = 10
        stackView.layoutMargins = .init(top: 0, left: 23, bottom: 0, right: 23)
        stackView.isLayoutMarginsRelativeArrangement = true
        let v1 = UIView()
        v1.translatesAutoresizingMaskIntoConstraints = false
        let v2 = UIView()
        v2.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(v1)
        for (i, icon) in appIcons.enumerated() {
            let img = UIImageView(image: UIImage(named: icon))
            img.translatesAutoresizingMaskIntoConstraints = false
            img.layer.cornerRadius = 14
            img.layer.masksToBounds = true
            img.layer.borderWidth = 0.5
            img.tag = i
            img.isUserInteractionEnabled = true
            NSLayoutConstraint.activate([
                img.widthAnchor.constraint(equalToConstant: 60),
                img.heightAnchor.constraint(equalToConstant: 60)
            ])
            stackView.addArrangedSubview(img)
        }
        stackView.addArrangedSubview(v2)
        NSLayoutConstraint.activate([
            stackView.heightAnchor.constraint(equalToConstant: 92),
            v1.heightAnchor.constraint(equalToConstant: 1),
            v2.heightAnchor.constraint(equalToConstant: 1),
            v1.widthAnchor.constraint(equalTo: v2.widthAnchor)
        ])
        return stackView
    }()
    
    private func setupViews() {
        axis = .vertical
        distribution = .fill
        addArrangedSubview(titleLabel, margin: .init(top: 5, left: 32, bottom: 5, right: 32))
        addArrangedSubview(appIconsView, margin: .init(top: 0, left: 16, bottom: 0, right: 16))
        for iconView in appIconsView.arrangedSubviews.filter({ v in
            v is UIImageView
        }) {
            iconView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(iconPressed)))
        }
        updateTheme()
    }

    public func updateTheme() {
        appIconsView.backgroundColor = WTheme.groupedItem
        for (i, iconView) in appIconsView.arrangedSubviews.filter({ v in
            v is UIImageView
        }).enumerated() {
            let isActive = appIcons[i] == UIApplication.shared.alternateIconName ?? primaryIcon
            iconView.layer.borderColor = isActive ? (WTheme.tint == .label ? WTheme.secondaryLabel.cgColor : WTheme.tint.cgColor) : WTheme.separator.cgColor
            iconView.layer.borderWidth = isActive ? 2 : 0.5
        }
    }
    
    @objc private func iconPressed(sender: UITapGestureRecognizer) {
        let selectedIcon = appIcons[sender.view?.tag ?? 0]
        UIApplication.shared.setAlternateIconName(selectedIcon == primaryIcon ? nil : selectedIcon)
        updateTheme()
    }

}
