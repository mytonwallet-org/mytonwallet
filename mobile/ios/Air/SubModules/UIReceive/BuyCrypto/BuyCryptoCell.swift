//
//  BuyCryptoCell.swift
//  UIHome
//
//  Created by Sina on 4/18/24.
//

import Foundation
import UIKit
import UIComponents
import WalletContext

class BuyCryptoCell: UITableViewCell, WThemedView {

    enum ItemPosition {
        case top
        case middle
        case bottom
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private var containerView: WHighlightView!
    private var img: UIImageView!
    private var lbl: UILabel!
    private var separator: UIView!
    private var action: (() -> Void)? = nil
    private func setupViews() {
        backgroundColor = .clear
        selectionStyle = .none
        contentView.isUserInteractionEnabled = true

        containerView = WHighlightView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(itemPressed)))
        addSubview(containerView)
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.leftAnchor.constraint(equalTo: leftAnchor, constant: 16),
            containerView.rightAnchor.constraint(equalTo: rightAnchor, constant: -16),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.backgroundColor = .clear
        stackView.axis = .horizontal
        stackView.layoutMargins = .init(top: 7, left: 16, bottom: 7, right: 16)
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.distribution = .fillProportionally
        stackView.alignment = .center
        containerView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: containerView.topAnchor),
            stackView.leftAnchor.constraint(equalTo: containerView.leftAnchor),
            stackView.rightAnchor.constraint(equalTo: containerView.rightAnchor),
            stackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        img = UIImageView(frame: .zero)
        img.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            img.widthAnchor.constraint(equalToConstant: 30),
            img.heightAnchor.constraint(equalToConstant: 30)
        ])
        stackView.addArrangedSubview(img)
        
        lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = .systemFont(ofSize: 17, weight: .regular)
        stackView.addArrangedSubview(lbl, spacing: 12)
        
        let arrowImageView = UIImageView(image: UIImage(systemName: "chevron.right",
                                                        withConfiguration: UIImage.SymbolConfiguration(pointSize: 10,
                                                                                        weight: .semibold))!
                                            .withRenderingMode(.alwaysTemplate))
        arrowImageView.tintColor = WTheme.secondaryLabel
        arrowImageView.translatesAutoresizingMaskIntoConstraints = false
        arrowImageView.contentMode = .center
        NSLayoutConstraint.activate([
            arrowImageView.widthAnchor.constraint(equalToConstant: 12)
        ])
        stackView.addArrangedSubview(arrowImageView)
        
        separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)
        NSLayoutConstraint.activate([
            separator.heightAnchor.constraint(equalToConstant: 0.33),
            separator.trailingAnchor.constraint(equalTo: stackView.trailingAnchor),
            separator.leadingAnchor.constraint(equalTo: lbl.leadingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        
        updateTheme()
    }
    
    func configure(position: ItemPosition,
                   image: UIImage, title: String, action: @escaping () -> Void) {
        self.img.image = image
        self.lbl.text = title
        if position != .middle {
            containerView.layer.cornerRadius = 10
            if position == .top {
                containerView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            } else {
                containerView.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            }
        }
        separator.isHidden = position == .bottom
        self.action = action
    }
    
    public func updateTheme() {
        containerView.backgroundColor = WTheme.groupedItem
        containerView.highlightBackgroundColor = WTheme.highlight
        separator.backgroundColor = WTheme.separator
    }
    
    @objc private func itemPressed() {
        action?()
    }
}
