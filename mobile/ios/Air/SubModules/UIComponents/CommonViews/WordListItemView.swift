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
        semanticContentAttribute = .forceLeftToRight
        textAlignment = .left
        let attr = NSMutableAttributedString(string: "\(index < 9 ? " " : "")\(localizedIntegerString(index + 1)). ", attributes: [
            .font: WTypography.uiFont(.body, content: .technical),
            .foregroundColor: UIColor.air.secondaryLabel,
        ])
        attr.append(NSAttributedString(string: word, attributes: [
            .font: WTypography.uiFont(.bodyStrong, content: .technical),
        ]))
        attributedText = attr
    }

}
