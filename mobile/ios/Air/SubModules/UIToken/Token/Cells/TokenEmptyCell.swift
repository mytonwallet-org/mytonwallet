//
//  TokenEmptyCell.swift
//  MyTonWalletAir
//
//  Created by Sina on 11/22/24.
//

import UIKit
import UIComponents
import WalletContext

class TokenEmptyCell: UITableViewCell {
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private let emptyLabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = .systemFont(ofSize: 17, weight: .medium)
        return lbl
    }()
    
    private func setupViews() {
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        
        addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.topAnchor.constraint(equalTo: topAnchor, constant: 60),
            emptyLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16)
        ])
        
        updateTheme()
    }

    func updateTheme() {
        emptyLabel.attributedText = NSAttributedString(string: lang("No transactions yet."),
                                                       attributes: [
                                                            .kern: -0.09,
                                                            .font: emptyLabel.font!,
                                                            .foregroundColor: WTheme.secondaryLabel
                                                        ])
    }

}
