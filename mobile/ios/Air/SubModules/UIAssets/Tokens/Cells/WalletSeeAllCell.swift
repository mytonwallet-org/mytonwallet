//
//  WalletSeeAllCell.swift
//  MyTonWalletAir
//
//  Created by Sina on 10/24/24.
//

import UIKit
import UIComponents
import WalletContext

class WalletSeeAllCell: UITableViewCell, WThemedView {
    public static let defaultHeight = CGFloat(44)
    private static let regular17Font = UIFont.systemFont(ofSize: 16, weight: .regular)

    @MainActor protocol Delegate: AnyObject {
        func didSelectSeeAll()
    }
    private weak var delegate: Delegate? = nil
    private var slug: String? = nil
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private var seeAllLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = WalletSeeAllCell.regular17Font
        lbl.text = lang("Show All Assets")
        return lbl
    }()
    
    private lazy var highlightView: WHighlightView = {
        let v = WHighlightView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(seeAllLabel)
        NSLayoutConstraint.activate([
            seeAllLabel.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 16),
            seeAllLabel.centerYAnchor.constraint(equalTo: v.centerYAnchor)
        ])
        return v
    }()
    
    private func setupViews() {
        selectionStyle = .none
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(cellSelected))
        tapGestureRecognizer.cancelsTouchesInView = false
        
        contentView.addSubview(highlightView)
        highlightView.addGestureRecognizer(tapGestureRecognizer)
        NSLayoutConstraint.activate([
            highlightView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            highlightView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            highlightView.topAnchor.constraint(equalTo: contentView.topAnchor),
            highlightView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
        
        updateTheme()
    }
    
    func updateTheme() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        highlightView.backgroundColor = .clear
        highlightView.highlightBackgroundColor = WTheme.highlight
        seeAllLabel.textColor = WTheme.tint
    }
    
    @objc private func cellSelected() {
        delegate?.didSelectSeeAll()
    }
    
    func configure(delegate: Delegate) {
        self.delegate = delegate
    }
}
