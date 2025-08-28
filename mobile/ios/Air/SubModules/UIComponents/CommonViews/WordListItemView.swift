//
//  WordListItemView.swift
//  UICreateWallet
//
//  Created by Sina on 4/14/23.
//

import UIKit
import WalletContext

public class WordListItemView: UILabel {

    public init(index: Int, word: String) {
        super.init(frame: CGRect.zero)
        setupView(index: index, word: word)
    }
    
    override init(frame: CGRect) {
        fatalError()
    }
    
    required init?(coder: NSCoder) {
        fatalError()
    }

    private func setupView(index: Int, word: String) {
        let attr = NSMutableAttributedString(string: "\(index < 9 ? " " : "")\(index + 1). ", attributes: [
            NSAttributedString.Key.foregroundColor: WTheme.secondaryLabel
        ])
        attr.append(NSAttributedString(string: word, attributes: [
            NSAttributedString.Key.font: UIFont.systemFont(ofSize: 17, weight: .semibold)
        ]))
        attributedText = attr
    }

}
