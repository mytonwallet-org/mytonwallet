//
//  TokenHeaderCell.swift
//  UIComponents
//
//  Created by Sina on 7/15/24.
//

import Foundation
import UIKit

class TokenHeaderCell: UITableViewCell {
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private var lbl: UILabel!
    private func setupViews() {
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = .systemFont(ofSize: 20, weight: .bold)
        addSubview(lbl)
        NSLayoutConstraint.activate([
            lbl.topAnchor.constraint(equalTo: topAnchor, constant: 24),
            lbl.leftAnchor.constraint(equalTo: leftAnchor, constant: 16),
            lbl.rightAnchor.constraint(equalTo: rightAnchor, constant: -16),
            lbl.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
    }
    
    func configure(title: String) {
        lbl.text = title
    }
    
}
