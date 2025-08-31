//
//  UIStackViewUtils.swift
//  UIComponents
//
//  Created by Sina on 4/18/24.
//

import UIKit

public extension UIStackView {

    func addArrangedSubview(_ v: UIView, margin: UIEdgeInsets) {
        let containerForMargin = UIView()
        containerForMargin.addSubview(v)
        v.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: containerForMargin.topAnchor, constant: margin.top),
            v.bottomAnchor.constraint(equalTo: containerForMargin.bottomAnchor, constant: -margin.bottom),
            v.leftAnchor.constraint(equalTo: containerForMargin.leftAnchor, constant: margin.left),
            v.rightAnchor.constraint(equalTo: containerForMargin.rightAnchor, constant: -margin.right)
        ])

        addArrangedSubview(containerForMargin)
    }
    
    func addArrangedSubview(_ v: UIView, spacing: CGFloat) {
        if let lastView = arrangedSubviews.last {
            setCustomSpacing(spacing, after: lastView)
            addArrangedSubview(v)
        } else {
            if axis == .vertical {
                addArrangedSubview(v, margin: .init(top: spacing, left: 0, bottom: 0, right: 0))
            } else {
                // to support both rtl and ltr
                let spacer = UIView()
                spacer.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    spacer.widthAnchor.constraint(equalToConstant: spacing),
                ])
                spacer.backgroundColor = .clear
                addArrangedSubview(spacer)
                addArrangedSubview(v)
            }
        }
    }
    
}

