//
//  WSuggestionsView.swift
//  MyTonWalletAir
//
//  Created by Sina on 11/25/24.
//

import UIKit
import WalletContext

public final class WSuggestionsView: UIView {
    public static let defaultHeight: CGFloat = 40

    public var presentationBounds: CGRect = .zero {
        didSet { updatePosition() }
    }

    private weak var activeInput: WWordInput?
    private var suggestions = [String]()
    private let suggestionsList = SuggestionsListView()
    private let glassBackground = WCapsuleGlassBackgroundView(style: .header, cornerRadius: 20)

    public init() {
        super.init(frame: .zero)
        isHidden = true
        semanticContentAttribute = .forceLeftToRight
        accessibilityIdentifier = "mnemonicSuggestions"
        addSubview(glassBackground)
        suggestionsList.layer.cornerRadius = 17
        suggestionsList.clipsToBounds = true
        addSubview(suggestionsList)
        NSLayoutConstraint.activate([
            suggestionsList.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            suggestionsList.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            suggestionsList.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            suggestionsList.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
        ])
        suggestionsList.didSelectSuggestion = { [weak self] suggestion in
            guard let self, self.suggestions.contains(suggestion), let activeInput = self.activeInput else { return }
            activeInput.setText(
                suggestion,
                notifyDelegate: true,
                goToNextInput: activeInput.advancesOnSuggestionSelection
            )
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        glassBackground.frame = bounds
    }

    public func config(activeInput: WWordInput?, suggestions: [String]) {
        self.activeInput = activeInput
        self.suggestions = suggestions
        suggestionsList.configure(suggestions: suggestions)
        updatePosition()
    }

    public func updatePosition() {
        guard let activeInput, activeInput.textField.isFirstResponder,
              !suggestions.isEmpty, let superview, !presentationBounds.isEmpty else {
            isHidden = true
            return
        }
        let inputFrame = activeInput.convert(activeInput.bounds, to: superview)
        guard presentationBounds.contains(CGPoint(x: inputFrame.midX, y: inputFrame.midY)) else {
            isHidden = true
            return
        }
        let font = WTypography.uiFont(.subheadlineBold)
        let contentWidth = suggestions.reduce(CGFloat(6)) { width, suggestion in
            width + ceil(suggestion.size(withAttributes: [.font: font]).width) + 32
        }
        let width = min(contentWidth, min(360, presentationBounds.width))
        let x = min(max(inputFrame.midX - width / 2, presentationBounds.minX), presentationBounds.maxX - width)
        let aboveY = inputFrame.minY - 12 - Self.defaultHeight
        let y = aboveY >= presentationBounds.minY ? aboveY : inputFrame.maxY + 12
        guard y + Self.defaultHeight <= presentationBounds.maxY else {
            isHidden = true
            return
        }
        frame = CGRect(x: x, y: y, width: width, height: Self.defaultHeight)
        isHidden = false
        superview.bringSubviewToFront(self)
    }
}

private final class SuggestionsListView: UIView {
    var didSelectSuggestion: ((String) -> Void)?

    private var suggestions = [String]()
    private let collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.register(SuggestionCell.self, forCellWithReuseIdentifier: SuggestionCell.identifier)
        collectionView.showsHorizontalScrollIndicator = false
        return collectionView
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        semanticContentAttribute = .forceLeftToRight
        collectionView.semanticContentAttribute = .forceLeftToRight
        collectionView.delegate = self
        collectionView.dataSource = self
        addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(suggestions: [String]) {
        self.suggestions = suggestions
        collectionView.collectionViewLayout.invalidateLayout()
        collectionView.reloadData()
    }
}

extension SuggestionsListView: UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    // MARK: - Collection View Data Source
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return suggestions.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard suggestions.indices.contains(indexPath.row),
              let cell = collectionView.dequeueReusableCell(withReuseIdentifier: SuggestionCell.identifier, for: indexPath) as? SuggestionCell else {
            return UICollectionViewCell()
        }
        cell.configure(with: suggestions[indexPath.row], isPreferred: indexPath.row == 0)
        return cell
    }
    
    // MARK: - Collection View Delegate Flow Layout
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        guard suggestions.indices.contains(indexPath.row) else {
            return .zero
        }
        let text = suggestions[indexPath.row]
        let font = WTypography.uiFont(.subheadlineBold)
        let width = text.size(withAttributes: [.font: font]).width + 32
        return CGSize(width: width, height: WSuggestionsView.defaultHeight - 6)
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard suggestions.indices.contains(indexPath.row) else { return }
        didSelectSuggestion?(suggestions[indexPath.row])
    }
}

private class SuggestionCell: UICollectionViewCell {
    static let identifier = "SuggestionCell"
    
    private let suggestionLabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.applyTextStyle(.subheadline)
        return label
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        contentView.addSubview(suggestionLabel)
        NSLayoutConstraint.activate([
            suggestionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            suggestionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            suggestionLabel.topAnchor.constraint(equalTo: contentView.topAnchor),
            suggestionLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
        contentView.layer.cornerRadius = 17
        contentView.layer.cornerCurve = .continuous
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configure(with text: String, isPreferred: Bool) {
        suggestionLabel.text = text
        suggestionLabel.applyTextStyle(isPreferred ? .subheadlineBold : .subheadlineEmphasized)
        suggestionLabel.textColor = isPreferred ? tintColor : .label
        contentView.backgroundColor = isPreferred ? .tertiarySystemFill : .clear
        isAccessibilityElement = true
        accessibilityLabel = text
        accessibilityTraits = .button
        accessibilityIdentifier = "mnemonicSuggestion.\(text)"
    }
    
}
