//
//  AppearanceColorThemeView.swift
//  UISettings
//
//  Created by Sina on 6/29/24.
//

import UIKit
import UIComponents
import WalletContext

class AppearanceColorThemeView: UIStackView, WThemedView {
    
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
        lbl.text = lang("Palette")
        return lbl
    }()
    
    private var colorsView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 13
        
        var rowStackViews = [UIStackView]()
        let colors = WAppearanceThemeColors
        let rowItemsCount = 7
        let rowsCount = Int(floor(Double(colors.count) / Double(rowItemsCount)))
        for i in 0 ..< rowsCount {
            let rowStackView = UIStackView()
            rowStackView.axis = .horizontal
            rowStackView.distribution = .equalSpacing
            rowStackView.alignment = .center
            rowStackViews.append(rowStackView)
            stackView.addArrangedSubview(rowStackView)
        }
        
//        let activeColorThemeId = AppStorageHelper.activeThemeColorId
        for (index, color) in colors.enumerated() {
            let colorView = UIButton()
            colorView.translatesAutoresizingMaskIntoConstraints = false
            colorView.backgroundColor = color.primary
            colorView.layer.cornerRadius = 15
            NSLayoutConstraint.activate([
                colorView.widthAnchor.constraint(equalToConstant: 30),
                colorView.heightAnchor.constraint(equalToConstant: 30)
            ])
            
            let innerSelectionView = UIView()
            innerSelectionView.translatesAutoresizingMaskIntoConstraints = false
            innerSelectionView.backgroundColor = colorView.backgroundColor
            innerSelectionView.layer.borderWidth = 2
            innerSelectionView.tag = index + 1
            innerSelectionView.layer.borderColor = WTheme.groupedItem.cgColor
            innerSelectionView.layer.cornerRadius = 13
//            innerSelectionView.isHidden = color.id != activeColorThemeId
            colorView.addSubview(innerSelectionView)
            
            NSLayoutConstraint.activate([
                innerSelectionView.topAnchor.constraint(equalTo: colorView.topAnchor, constant: 2),
                innerSelectionView.leftAnchor.constraint(equalTo: colorView.leftAnchor, constant: 2),
                innerSelectionView.rightAnchor.constraint(equalTo: colorView.rightAnchor, constant: -2),
                innerSelectionView.bottomAnchor.constraint(equalTo: colorView.bottomAnchor, constant: -2),
            ])
            
            rowStackViews[Int(floor(Double(index) / Double(rowItemsCount)))].addArrangedSubview(colorView)
        }
        
        return stackView
    }()
    
    private lazy var schemaView: UIView = {
        let view = UIStackView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 10
        view.layer.masksToBounds = true
        view.addSubview(colorsView)
        NSLayoutConstraint.activate([
            colorsView.topAnchor.constraint(equalTo: view.topAnchor, constant: 13),

            colorsView.leftAnchor.constraint(equalTo: view.leftAnchor, constant: 17),
            colorsView.rightAnchor.constraint(equalTo: view.rightAnchor, constant: -17),

            colorsView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -17),
            colorsView.heightAnchor.constraint(equalToConstant: 81),
        ])
        return view
    }()
    
    private func setupViews() {
        axis = .vertical
        distribution = .fill
        addArrangedSubview(titleLabel, margin: .init(top: 5, left: 32, bottom: 5, right: 32))
        addArrangedSubview(schemaView, margin: .init(top: 0, left: 16, bottom: 0, right: 16))
        for colorViewRow in colorsView.arrangedSubviews {
            for colorView in colorViewRow.subviews {
                if let colorView = colorView as? UIButton {
                    colorView.addTarget(self, action: #selector(colorSelected), for: .touchUpInside)
                }
            }
        }
        
        updateTheme()
    }
    
    public func updateTheme() {
        schemaView.backgroundColor = WTheme.groupedItem
        for i in 1 ... WAppearanceThemeColors.count {
            colorsView.viewWithTag(i)?.layer.borderColor = WTheme.groupedItem.cgColor
        }
    }
    
    @objc func colorSelected(sender: UIButton) {
        for (i, colorView) in colorsView.arrangedSubviews.reduce([], { partialResult, v in
            return partialResult + v.subviews
        }).enumerated() {
            if sender == colorView {
                changeThemeColors(to: i)
                UIApplication.shared.sceneKeyWindow?.updateTheme()
                colorView.subviews[0].isHidden = false
            } else {
                colorView.subviews[0].isHidden = true
            }
        }
    }
    
}
