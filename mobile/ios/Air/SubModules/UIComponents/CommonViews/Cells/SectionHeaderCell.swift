//
//  SectionHeaderCell.swift
//  UIComponents
//
//  Created by Sina on 4/20/24.
//

import Foundation
import UIKit
import WalletContext

public class SectionHeaderCell: UITableViewCell, WThemedView {

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private var topConstraint: NSLayoutConstraint!
    private var lbl: UILabel!
    private func setupViews() {
        backgroundColor = .clear
        selectionStyle = .none
        
        lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = .systemFont(ofSize: 13, weight: .regular)
        lbl.numberOfLines = 0
        addSubview(lbl)
        topConstraint = lbl.topAnchor.constraint(equalTo: topAnchor, constant: 23)
        NSLayoutConstraint.activate([
            lbl.leftAnchor.constraint(equalTo: leftAnchor, constant: 32),
            topConstraint,
            lbl.rightAnchor.constraint(equalTo: rightAnchor),
            lbl.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])

        updateTheme()
    }
    
    public func configure(title: String, spacing: CGFloat = 0) {
        lbl.text = title
        topConstraint.constant = 23 + spacing
    }
    
    public func updateTheme() {
        lbl.textColor = WTheme.secondaryLabel
    }
    
}
