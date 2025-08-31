//
//  ImageTitleSubtitleSelectableCell.swift
//  UIComponents
//
//  Created by Sina on 8/31/24.
//

import Foundation
import UIKit
import WalletContext
import Kingfisher

fileprivate var checkmarkImage = UIImage(systemName: "checkmark")

public class ImageTitleSubtitleSelectableCell: UITableViewCell, WThemedView {
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private var isInModal = true

    private var containerView: WHighlightView!
    public private(set) var img: IconView!
    private var titleLabel: UILabel!
    private var subtitleLabel: UILabel!
    private var valueLabel: UILabel!
    private var rightImageView: UIImageView!
    private var separatorView: UIView!
    
    private var subtitleColor = WTheme.secondaryLabel
    private var imageTintColor = WTheme.tint

    private func setupViews() {
        selectionStyle = .none
        contentView.isUserInteractionEnabled = true
        
        containerView = WHighlightView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.layer.cornerRadius = 10
        containerView.layer.masksToBounds = true
        containerView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(itemSelected)))
        addSubview(containerView)
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.leftAnchor.constraint(equalTo: leftAnchor, constant: 16),
            containerView.rightAnchor.constraint(equalTo: rightAnchor, constant: -16),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            containerView.heightAnchor.constraint(equalToConstant: 56)
        ])
        
        img = IconView(size: 40)
        containerView.addSubview(img)
        NSLayoutConstraint.activate([
            img.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8),
            img.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16)
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
        
        rightImageView = UIImageView(image: checkmarkImage)
        rightImageView.translatesAutoresizingMaskIntoConstraints = false
        rightImageView.tintColor = WTheme.tint
        containerView.addSubview(rightImageView)
        NSLayoutConstraint.activate([
            rightImageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            rightImageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor)
        ])
        
        // value label
        valueLabel = UILabel()
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.font = .systemFont(ofSize: 17, weight: .regular)
        containerView.addSubview(valueLabel)
        NSLayoutConstraint.activate([
            valueLabel.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            valueLabel.trailingAnchor.constraint(equalTo: rightImageView.leadingAnchor, constant: -8)
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
        containerView.highlightBackgroundColor = WTheme.highlight
        separatorView.backgroundColor = WTheme.separator
        titleLabel.textColor = WTheme.primaryLabel
        subtitleLabel.textColor = subtitleColor
        valueLabel.textColor = WTheme.secondaryLabel
        rightImageView.tintColor = imageTintColor
    }
    
    private var onSelect: (() -> Void)? = nil
    public func configure(title: String,
                          subtitle: String,
                          isSelected: Bool,
                          isFirst: Bool,
                          isLast: Bool,
                          isInModal: Bool,
                          value: String? = nil, // Value will be shown next to the right image
                          rightIcon: UIImage? = nil, // If rightIcon is passed, it will replace checkmark icon whenever item is not selected.
                          selectedRightIcon: UIImage? = nil, // If rightIcon is passed, it will replace checkmark icon whenever item is selected.
                          subtitleColor: UIColor? = nil, // To force subtile have a specific color instead of primaryLabel
                          onSelect: @escaping () -> Void) {
        if self.isInModal != isInModal {
            self.isInModal = isInModal
            updateTheme()
        }
        if let subtitleColor {
            self.subtitleColor = subtitleColor
            subtitleLabel.textColor = subtitleColor
        }
        self.onSelect = onSelect
        titleLabel.text = title
        subtitleLabel.text = subtitle
        valueLabel.text = value

        if let rightIcon {
            rightImageView.isHidden = false
            if !isSelected {
                rightImageView.image = rightIcon
                imageTintColor = WTheme.tint
            } else {
                rightImageView.image = checkmarkImage
                imageTintColor = WTheme.secondaryLabel
            }
            rightImageView.tintColor = imageTintColor
        } else {
            rightImageView.isHidden = !isSelected
        }
        if let selectedRightIcon, isSelected {
            rightImageView.image = selectedRightIcon
        }

        separatorView.isHidden = isLast
        var maskedCorners: CACornerMask = []
        if isFirst {
            maskedCorners.formUnion([.layerMinXMinYCorner, .layerMaxXMinYCorner])
        }
        if isLast {
            maskedCorners.formUnion([.layerMinXMaxYCorner, .layerMaxXMaxYCorner])
        }
        containerView.layer.maskedCorners = maskedCorners
    }
    
    @objc func itemSelected() {
        onSelect?()
    }
    
}
