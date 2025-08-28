//
//  DateUtils.swift
//  WalletContext
//
//  Created by Sina on 5/18/23.
//

import Foundation

extension Date {
    
    public init(unixMs: Int) {
        self = Date(timeIntervalSince1970: Double(unixMs) / 1000.0)
    }
    
    func isEqual(to date: Date, toGranularity component: Calendar.Component, in calendar: Calendar = .current) -> Bool {
        calendar.isDate(self, equalTo: date, toGranularity: component)
    }

    public func isInSameDay(as date: Date) -> Bool { Calendar.current.isDate(self, inSameDayAs: date) }

    public func isInSameYear(as date: Date) -> Bool { isEqual(to: date, toGranularity: .year) }
    
    public var remainingFromNow: String {
        return Duration.seconds(self.timeIntervalSinceNow)
            .formatted(
                Duration.UnitsFormatStyle(
                    allowedUnits: [.days, .hours, .minutes, .seconds],
                    width: .wide,
                    maximumUnitCount: 2,
                    zeroValueUnits: .hide,
                    fractionalPart: .hide,
                )
                .locale(LocalizationSupport.shared.locale)
            )
    }

}

public func formatTimeInterval(_ s: TimeInterval) -> String {
    Duration.UnitsFormatStyle(allowedUnits: [.minutes, .seconds], width: .wide).format(.seconds(s))
}
