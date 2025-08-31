//
//  WordListView.swift
//  UICreateWallet
//
//  Created by Sina on 4/14/23.
//

import UIKit
import WalletContext
import WalletCore

public class WordListView: UIView {

    private var words: [String]
    
    public init(words: [String]) {
        self.words = words
        super.init(frame: CGRect.zero)
        setupView()
    }
    
    override init(frame: CGRect) {
        fatalError()
    }
    
    required init?(coder: NSCoder) {
        fatalError()
    }

    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false

        // prepare stack views
        let rowsCount = Int(ceil(Double(words.count) / 2))
        let leftStackView = UIStackView()
        leftStackView.axis = .vertical
        leftStackView.spacing = 12
        let rightStackView = UIStackView()
        rightStackView.axis = .vertical
        rightStackView.spacing = 12
        
        // fill stack views with word items
        for (index, word) in words.enumerated() {
            let wordItemView = WordListItemView(index: index, word: word)
            if index < rowsCount {
                leftStackView.addArrangedSubview(wordItemView)
            } else {
                rightStackView.addArrangedSubview(wordItemView)
            }
        }
        
        // left side stackView
        leftStackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(leftStackView)
        NSLayoutConstraint.activate([
            leftStackView.leftAnchor.constraint(equalTo: leftAnchor, constant: 16),
            leftStackView.topAnchor.constraint(equalTo: topAnchor),
            leftStackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        rightStackView.translatesAutoresizingMaskIntoConstraints = false
        
        // right side stackView
        addSubview(rightStackView)
        NSLayoutConstraint.activate([
            rightStackView.rightAnchor.constraint(lessThanOrEqualTo: rightAnchor, constant: -8),
            rightStackView.rightAnchor.constraint(equalTo: rightAnchor, constant: -16).withPriority(.defaultHigh),
            rightStackView.leftAnchor.constraint(greaterThanOrEqualTo: leftStackView.rightAnchor),
            rightStackView.topAnchor.constraint(equalTo: topAnchor),
            rightStackView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])
        
        let longTap = UILongPressGestureRecognizer(target: self, action: #selector(onLongTap))
        longTap.minimumPressDuration = 0.25
        addGestureRecognizer(longTap)
    }

    @objc func onLongTap(_ gesture: UIGestureRecognizer) {
        if gesture.state == .began {
            AppActions.copyString(words.joined(separator: " "), toastMessage: "Secret phrase was copied to clipboard")
        }
    }
}
