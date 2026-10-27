//
//  ActivityDateCell.swift
//  MyTonWalletAir
//
//  Created by Sina on 11/8/24.
//

import UIKit
import WalletContext

public enum ActivityTimestampDisplayMode: Equatable, Sendable {
    case timeOnly
    case dateWhenOlderThanTwelveHours
}

public enum ActivityDateFormatting {
    private static let dateThreshold: TimeInterval = 12 * 60 * 60

    public static func shouldShowDate(
        for date: Date,
        relativeTo now: Date,
        calendar: Calendar = LocalizationSupport.shared.calendar
    ) -> Bool {
        !calendar.isDate(date, inSameDayAs: now)
            && now.timeIntervalSince(date) > dateThreshold
    }

    public static func dateText(
        for date: Date,
        relativeTo now: Date,
        calendar: Calendar = LocalizationSupport.shared.calendar,
        locale: Locale = LocalizationSupport.shared.locale
    ) -> String {
        let format = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        return if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            date.formatted(format.month(.wide).day())
        } else {
            date.formatted(format.year(.defaultDigits).month(.wide).day())
        }
    }

    public static func shortDateText(
        for date: Date,
        relativeTo now: Date,
        calendar: Calendar = LocalizationSupport.shared.calendar,
        locale: Locale = LocalizationSupport.shared.locale
    ) -> String {
        let format = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        return if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            date.formatted(format.month(.abbreviated).day())
        } else {
            date.formatted(format.year(.defaultDigits).month(.abbreviated).day())
        }
    }

    public static func headerText(
        for date: Date,
        relativeTo now: Date = .now,
        calendar: Calendar = LocalizationSupport.shared.calendar,
        locale: Locale = LocalizationSupport.shared.locale
    ) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            lang("Today")
        } else {
            dateText(for: date, relativeTo: now, calendar: calendar, locale: locale)
        }
    }

    public static func timestampText(
        for date: Date,
        mode: ActivityTimestampDisplayMode,
        relativeTo now: Date = .now,
        calendar: Calendar = LocalizationSupport.shared.calendar,
        locale: Locale = LocalizationSupport.shared.locale
    ) -> String {
        if mode == .dateWhenOlderThanTwelveHours,
           shouldShowDate(for: date, relativeTo: now, calendar: calendar) {
            return shortDateText(for: date, relativeTo: now, calendar: calendar, locale: locale)
        }
        return stringForTimestamp(timestamp: Int32(clamping: Int64(date.timeIntervalSince1970)))
    }
}

public class ActivityDateCell: UICollectionReusableView {

    public let contentView = UIView()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { nil }
    
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
        dateLabel.applyTextStyle(.bodyStrong)
        
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
        dateLabel.text = ActivityDateFormatting.headerText(for: itemDate)
    }

    public func configure(title: String) {
        skeletonView?.alpha = 0
        dateLabel.alpha = 1
        dateLabel.text = title
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
