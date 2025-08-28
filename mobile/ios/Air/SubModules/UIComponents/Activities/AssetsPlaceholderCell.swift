//
//  AssetsPlaceholderCell.swift
//  MyTonWalletAir
//
//  Created by Sina on 6/9/25.
//

import UIKit
import WalletContext

open class AssetsPlaceholderCell: UITableViewCell, WThemedView {
    
    public override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        setupViews()
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private lazy var makeWalletTokenSkeletonView: () -> UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(equalToConstant: 60)
        ])
        
        let iconSkeleton = UIView()
        iconSkeleton.translatesAutoresizingMaskIntoConstraints = false
        iconSkeleton.backgroundColor = WTheme.groupedBackground
        iconSkeleton.layer.cornerRadius = 20
        view.addSubview(iconSkeleton)
        NSLayoutConstraint.activate([
            iconSkeleton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            iconSkeleton.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            iconSkeleton.widthAnchor.constraint(equalToConstant: 40),
            iconSkeleton.heightAnchor.constraint(equalToConstant: 40)
        ])
        
        let tokenNameSkeleton = UIView()
        tokenNameSkeleton.translatesAutoresizingMaskIntoConstraints = false
        tokenNameSkeleton.backgroundColor = WTheme.groupedBackground
        tokenNameSkeleton.layer.cornerRadius = 8
        view.addSubview(tokenNameSkeleton)
        NSLayoutConstraint.activate([
            tokenNameSkeleton.leadingAnchor.constraint(equalTo: iconSkeleton.trailingAnchor, constant: 11),
            tokenNameSkeleton.topAnchor.constraint(equalTo: view.topAnchor, constant: 1.667),
            tokenNameSkeleton.widthAnchor.constraint(equalToConstant: 80),
            tokenNameSkeleton.heightAnchor.constraint(equalToConstant: 16)
        ])
        
        let tokenPriceSkeleton = UIView()
        tokenPriceSkeleton.translatesAutoresizingMaskIntoConstraints = false
        tokenPriceSkeleton.backgroundColor = WTheme.groupedBackground
        tokenPriceSkeleton.layer.cornerRadius = 7
        view.addSubview(tokenPriceSkeleton)
        NSLayoutConstraint.activate([
            tokenPriceSkeleton.leadingAnchor.constraint(equalTo: tokenNameSkeleton.leadingAnchor),
            tokenPriceSkeleton.topAnchor.constraint(equalTo: tokenNameSkeleton.bottomAnchor, constant: 1),
            tokenPriceSkeleton.widthAnchor.constraint(equalToConstant: 60),
            tokenPriceSkeleton.heightAnchor.constraint(equalToConstant: 14)
        ])
        
        let amountSkeleton = UIView()
        amountSkeleton.translatesAutoresizingMaskIntoConstraints = false
        amountSkeleton.backgroundColor = WTheme.groupedBackground
        amountSkeleton.layer.cornerRadius = 8
        view.addSubview(amountSkeleton)
        NSLayoutConstraint.activate([
            amountSkeleton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            amountSkeleton.firstBaselineAnchor.constraint(equalTo: tokenNameSkeleton.firstBaselineAnchor),
            amountSkeleton.widthAnchor.constraint(equalToConstant: 70),
            amountSkeleton.heightAnchor.constraint(equalToConstant: 16)
        ])
        
        let baseCurrencyAmountSkeleton = UIView()
        baseCurrencyAmountSkeleton.translatesAutoresizingMaskIntoConstraints = false
        baseCurrencyAmountSkeleton.backgroundColor = WTheme.groupedBackground
        baseCurrencyAmountSkeleton.layer.cornerRadius = 7
        view.addSubview(baseCurrencyAmountSkeleton)
        NSLayoutConstraint.activate([
            baseCurrencyAmountSkeleton.trailingAnchor.constraint(equalTo: amountSkeleton.trailingAnchor, constant: -16),
            baseCurrencyAmountSkeleton.firstBaselineAnchor.constraint(equalTo: tokenPriceSkeleton.firstBaselineAnchor),
            baseCurrencyAmountSkeleton.widthAnchor.constraint(equalToConstant: 50),
            baseCurrencyAmountSkeleton.heightAnchor.constraint(equalToConstant: 14)
        ])
        
        let separatorView = UIView()
        separatorView.translatesAutoresizingMaskIntoConstraints = false
        separatorView.backgroundColor = WTheme.separator
        view.addSubview(separatorView)
        NSLayoutConstraint.activate([
            separatorView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10.33),
            separatorView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            separatorView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 62),
            separatorView.heightAnchor.constraint(equalToConstant: 0.33)
        ])
        
        return view
    }

    public private(set) lazy var innerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 16
        
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        for i in 0..<4 {
            stackView.addArrangedSubview(makeWalletTokenSkeletonView())
        }
        
        view.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.topAnchor, constant: 56),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        return view
    }()

    private func setupViews() {
        selectionStyle = .none
        backgroundColor = .clear
        addSubview(innerView)
        NSLayoutConstraint.activate([
            innerView.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            innerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            innerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0),
            innerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 0)
        ])
    }
    
    public func configureSkeleton() {
        updateTheme()
    }
    
    public func updateTheme() {
        innerView.backgroundColor = WTheme.groupedItem
    }
}
