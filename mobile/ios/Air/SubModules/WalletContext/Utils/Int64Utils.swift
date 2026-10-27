//
//  Int64Utils.swift
//  WalletContext
//
//  Created by Sina on 4/29/23.
//

import Foundation

extension Int64 {
    public var dateTimeString: String {
        let date = Date(timeIntervalSince1970: Double(self) / 1000)
        return if date.isInSameYear(as: Date()) {
            date.formatted(.localizedDateTime
                .month(.wide).day(.defaultDigits)
                .hour(.defaultDigits(amPM: .abbreviated)).minute()
            )
        } else {
            date.formatted(.localizedDateTime
                .year(.defaultDigits).month(.wide).day(.defaultDigits)
                .hour(.defaultDigits(amPM: .abbreviated)).minute()
            )
        }
    }
}
