//
//  WSuggestionsView.swift
//  MyTonWalletAir
//
//  Created by Sina on 11/25/24.
//

import UIKit
import WalletContext

public class WSuggestionsView: UIInputView {
    public static let defaultHeight = CGFloat(50)
    
    public init() {
        super.init(frame: .zero, inputViewStyle: .keyboard)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private var activeInput: WWordInput?
    private var suggestions = [String]()
    private var heightConstraint: NSLayoutConstraint!
    
    private let collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.backgroundColor = .clear
        cv.register(SuggestionCell.self, forCellWithReuseIdentifier: SuggestionCell.identifier)
        cv.showsHorizontalScrollIndicator = false
        return cv
    }()
    
    private func setupViews() {
        translatesAutoresizingMaskIntoConstraints = false

        collectionView.delegate = self
        collectionView.dataSource = self
        addSubview(collectionView)
        
        heightConstraint = heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            heightConstraint,
            collectionView.leftAnchor.constraint(equalTo: leftAnchor),
            collectionView.rightAnchor.constraint(equalTo: rightAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
            collectionView.heightAnchor.constraint(equalToConstant: WSuggestionsView.defaultHeight),
        ])
    }
    
    public func config(activeInput: WWordInput?, suggestions: [String]) {
        self.activeInput = activeInput
        guard activeInput != nil else {
            self.suggestions = []
            heightConstraint.constant = 0
            collectionView.reloadData()
            return
        }
        
        // load suggestions
        self.suggestions = suggestions
        heightConstraint.constant = suggestions.isEmpty ? 0 : WSuggestionsView.defaultHeight
        
        collectionView.reloadData()
    }
}

extension WSuggestionsView: UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    // MARK: - Collection View Data Source
    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return suggestions.count
    }
    
    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: SuggestionCell.identifier, for: indexPath) as? SuggestionCell else {
            return UICollectionViewCell()
        }
        cell.configure(with: suggestions[indexPath.row])
        return cell
    }
    
    // MARK: - Collection View Delegate Flow Layout
    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let text = suggestions[indexPath.row]
        let width = text.size(withAttributes: [NSAttributedString.Key.font: UIFont.systemFont(ofSize: 17)]).width + 32
        return CGSize(width: width, height: WSuggestionsView.defaultHeight)
    }
    
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        activeInput?.textField.text = suggestions[indexPath.row]
        _ = activeInput?.textFieldShouldReturn(activeInput!.textField)
    }
}

fileprivate class SuggestionCell: UICollectionViewCell, WThemedView {
    static let identifier = "SuggestionCell"
    
    private let suggestionLabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.font = UIFont.systemFont(ofSize: 17)
        return label
    }()
    
    private let separator: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        contentView.addSubview(suggestionLabel)
        contentView.addSubview(separator)
        NSLayoutConstraint.activate([
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separator.widthAnchor.constraint(equalToConstant: 0.33),
            separator.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            separator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            suggestionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            suggestionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            suggestionLabel.topAnchor.constraint(equalTo: contentView.topAnchor),
            suggestionLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
        updateTheme()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configure(with text: String) {
        suggestionLabel.text = text
    }
    
    func updateTheme() {
        suggestionLabel.textColor = WTheme.primaryLabel
        separator.backgroundColor = WTheme.primaryLabel.withAlphaComponent(0.1)
    }
}
