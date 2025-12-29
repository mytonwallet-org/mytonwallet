//
//  ActivityDateCell.swift
//  MyTonWalletAir
//
//  Created by Sina on 11/8/24.
//

import UIKit
import WalletContext

public class ActivityDateCell: UITableViewHeaderFooterView {

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private var locale: Locale { LocalizationSupport.shared.locale }
    private lazy var formatStyleCurrentYear = Date.FormatStyle.dateTime.month(.wide).day().locale(locale)
    private lazy var formatStyleWithYear = Date.FormatStyle.dateTime.year(.defaultDigits).month(.wide).day().locale(locale)
    
    public var skeletonView: DateSkeletonView? = nil
    private let dateLabel = UILabel()
    
    private var dateLabelTopConstraint: NSLayoutConstraint!
    private var dateLabelBottomConstraint: NSLayoutConstraint!

    private func setupViews() {
        
        contentView.isUserInteractionEnabled = true
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(dateLabel)
        dateLabel.font = UIFont.boldSystemFont(ofSize: 20)
        
        dateLabelTopConstraint = dateLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24)
        dateLabelBottomConstraint = dateLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6).withPriority(.defaultHigh)
        NSLayoutConstraint.activate([
            dateLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            dateLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20).withPriority(.defaultHigh),
            dateLabelTopConstraint,
            dateLabelBottomConstraint
        ])

        updateTheme()
    }

    func updateTheme() {
        contentView.backgroundColor = .clear
    }
    
    public override func prepareForReuse() {
        super.prepareForReuse()
        contentView.alpha = 1
    }
    
    // MARK: - Configure using ApiActivity
    public func configure(with itemDate: Date, shouldFadeOutSkeleton: Bool) {
        if shouldFadeOutSkeleton {
            fadeOutSkeleton()
        } else {
            skeletonView?.alpha = 0
            dateLabel.alpha = 1
        }
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
            addSubview(skeletonView)
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

    private func fadeOutSkeleton() {
        layoutIfNeeded()
        UIView.animate(withDuration: 0.3) { [self] in
            skeletonView?.alpha = 0
            dateLabel.alpha = 1
        }
    }
}


public class DateSkeletonView: UIView, WThemedView {

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

    public func updateTheme() {
         backgroundColor = WTheme.groupedItem
    }

    public func configure() {
        // Hiding this view from stack-view in cell will cause auto-layout constraint-break warnings.
    }
}
