//
//  WSearchBar.swift
//  UIComponents
//
//  Created by Sina on 6/25/24.
//

import UIKit
import WalletContext

public class WSearchBar: UISearchBar, UISearchBarDelegate, WThemedView {

    public var onChange: ((String) -> Void)?
    public var onSubmit: ((String) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        UITextField.appearance(whenContainedInInstancesOf: [WSearchBar.self]).defaultTextAttributes = [
            NSAttributedString.Key.font: UIFont.systemFont(ofSize: 16)
        ]

        // Setup the search bar properties
        delegate = self
        searchBarStyle = .minimal
        autocorrectionType = .no
        autocapitalizationType = .none
        spellCheckingType = .no
        keyboardType = .webSearch
        returnKeyType = .go

        layer.shadowOffset = CGSize(width: 0, height: 1.333)
        layer.shadowRadius = 5
        layer.shadowPath = CGPath(roundedRect: bounds, cornerWidth: 10, cornerHeight: 10, transform: nil)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.05

        layer.cornerRadius = 10

        isTranslucent = false
        setSearchFieldBackgroundImage(UIImage(), for: .normal)
        updateTheme()
    }

    public func updateTheme() {
        backgroundColor = WTheme.background
    }
    
    public override var intrinsicContentSize: CGSize {
        .init(width: super.intrinsicContentSize.width, height: 40)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = CGPath(roundedRect: bounds, cornerWidth: 10, cornerHeight: 10, transform: nil)
    }
    
    // UISearchBarDelegate methods

    public func searchBarShouldBeginEditing(_ searchBar: UISearchBar) -> Bool {
        setPositionAdjustment(.init(horizontal: 8, vertical: 0), for: .search)
        return true
    }
    
    public func searchBarShouldEndEditing(_ searchBar: UISearchBar) -> Bool {
        guard text?.isEmpty != false else {
            return true
        }
        setCenteredPlaceholder()
        return true
    }

    public func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        onChange?(searchText)
    }

    public func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
        onSubmit?(searchBar.text ?? "")
    }
}
