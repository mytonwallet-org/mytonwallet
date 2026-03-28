//
//  ActivityDateCell.swift
//  MyTonWalletAir
//
//  Created by Sina on 11/8/24.
//

import UIKit
import WalletContext

public class ActivityDateCell: UICollectionReusableView {

    public let contentView = UIView()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { nil }
    
    private var locale: Locale { LocalizationSupport.shared.locale }
    private lazy var formatStyleCurrentYear = Date.FormatStyle.dateTime.month(.wide).day().locale(locale)
    private lazy var formatStyleWithYear = Date.FormatStyle.dateTime.year(.defaultDigits).month(.wide).day().locale(locale)
    
    public var skeletonView: DateSkeletonView? = nil
    private let dateLabel = UILabel()
    
    private func setupViews() {
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        contentView.isUserInteractionEnabled = true
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(dateLabel)
        dateLabel.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        
        NSLayoutConstraint.activate([
            dateLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            dateLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20).withPriority(.defaultHigh),
            dateLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 9),
            dateLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -9).withPriority(.defaultHigh),
        ])

        contentView.backgroundColor = .clear
        dateLabel.textColor = .air.secondaryLabel
    }
    
    public override func prepareForReuse() {
        super.prepareForReuse()
        contentView.alpha = 1
    }
    
    // MARK: - Configure using ApiActivity
    public func configure(with itemDate: Date) {
        skeletonView?.alpha = 0
        dateLabel.alpha = 1
        // MARK: Handle date header
        let now = Date()
        if now.isInSameDay(as: itemDate) {
            dateLabel.text = lang("Today")
        } else {
            let sameYear = now.isInSameYear(as: itemDate)
            if sameYear {
                dateLabel.text = itemDate.formatted(formatStyleCurrentYear)
            } else {
                dateLabel.text = itemDate.formatted(formatStyleWithYear)
            }
        }
    }

    public func configureSkeleton() {
        if skeletonView == nil {
            let skeletonView = DateSkeletonView()
            skeletonView.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(skeletonView)
            NSLayoutConstraint.activate([
                skeletonView.leadingAnchor.constraint(equalTo: dateLabel.leadingAnchor),
                skeletonView.centerYAnchor.constraint(equalTo: dateLabel.centerYAnchor),
            ])
            self.skeletonView = skeletonView
        } else {
            skeletonView?.alpha = 1
        }
        skeletonView?.configure()
        dateLabel.alpha = 0
        dateLabel.text = "AAAA"
        UIView.performWithoutAnimation {
            setNeedsLayout()
            layoutIfNeeded()
        }
    }

}


public class DateSkeletonView: UIView {

    init() {
        super.init(frame: .zero)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 8
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 140),
            heightAnchor.constraint(equalToConstant: 16),
        ])

        updateTheme()
    }

    private func updateTheme() {
         backgroundColor = .air.groupedItem
    }

    public func configure() {
        // Hiding this view from stack-view in cell will cause auto-layout constraint-break warnings.
    }
}
