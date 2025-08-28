//
//  TitleValueRowView.swift
//  UIComponents
//
//  Created by Sina on 4/27/23.
//

import Foundation
import UIKit
import WalletContext


public class TitleValueRowView: UIView, WThemedView {

    public init(title: String, value: String?, valueIcon: UIImage? = nil, separator: Bool = true) {
        super.init(frame: .zero)
        setupViews(title: title, value: value.flatMap(NSAttributedString.init(string:)) , valueIcon: valueIcon, separator: separator)
    }
    
    public init(title: String, attributedValue: NSAttributedString, valueIcon: UIImage? = nil, separator: Bool = true) {
        super.init(frame: .zero)
        setupViews(title: title, value: attributedValue, valueIcon: valueIcon, separator: separator)
    }
    
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private var valueLabel: UILabel!
    private var valueIconView: UIImageView? = nil
    private var activityIndicatorView: UIActivityIndicatorView? = nil
    
    private func setupViews(title: String, value: NSAttributedString?, valueIcon: UIImage?, separator: Bool) {
        translatesAutoresizingMaskIntoConstraints = false

        // height
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 44)
        ])
        // title
        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 17, weight: .regular)
        titleLabel.text = title
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 11),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16)
        ])
        // value
        valueLabel = UILabel()
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.font = .systemFont(ofSize: 17, weight: .regular)
        addSubview(valueLabel)
        NSLayoutConstraint.activate([
            valueLabel.topAnchor.constraint(equalTo: topAnchor, constant: 11),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16)
        ])
        // value icon
        if let valueIcon {
            valueIconView = UIImageView(image: valueIcon)
            valueIconView!.translatesAutoresizingMaskIntoConstraints = false
            valueIconView!.contentMode = .scaleAspectFit
            addSubview(valueIconView!)
            NSLayoutConstraint.activate([
                valueIconView!.widthAnchor.constraint(equalToConstant: 16),
                valueIconView!.heightAnchor.constraint(equalToConstant: 16),
                valueIconView!.centerYAnchor.constraint(equalTo: centerYAnchor),
                valueIconView!.trailingAnchor.constraint(equalTo: valueLabel.leadingAnchor, constant: -4)
            ])
        }
        setValueText(value)
        // separator
        if separator {
            let separatorView = UIView()
            separatorView.translatesAutoresizingMaskIntoConstraints = false
            separatorView.backgroundColor = WTheme.separator
            addSubview(separatorView)
            NSLayoutConstraint.activate([
                separatorView.heightAnchor.constraint(equalToConstant: 0.33),
                separatorView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
                separatorView.trailingAnchor.constraint(equalTo: trailingAnchor),
                separatorView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
        
        updateTheme()
    }
    
    public func setValueText(_ text: NSAttributedString?) {
        valueLabel.attributedText = text
        valueIconView?.isHidden = text == nil
        if text == nil {
            // add activity indicator view if not exists
            if activityIndicatorView == nil {
                activityIndicatorView = UIActivityIndicatorView()
                activityIndicatorView?.translatesAutoresizingMaskIntoConstraints = false
                activityIndicatorView?.hidesWhenStopped = true
                addSubview(activityIndicatorView!)
                NSLayoutConstraint.activate([
                    activityIndicatorView!.trailingAnchor.constraint(equalTo: valueLabel.trailingAnchor),
                    activityIndicatorView!.centerYAnchor.constraint(equalTo: centerYAnchor)
                ])
            }
            activityIndicatorView?.startAnimating()
        } else {
            activityIndicatorView?.stopAnimating()
        }
    }
    
    public func updateTheme() {
        backgroundColor = WTheme.groupedItem
    }
    
    public func setValueTextColor(_ color: UIColor) {
        valueLabel.textColor = color
    }
}
