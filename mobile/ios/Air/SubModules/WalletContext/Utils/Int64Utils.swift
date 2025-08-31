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
        let dateFormatter = DateFormatter()
        if date.isInSameYear(as: Date()) {
            dateFormatter.dateFormat = "d MMMM 'at' H:mm"
        } else {
            dateFormatter.dateFormat = "d MMMM yyyy 'at' H:mm"
        }
        return dateFormatter.string(from: date)
    }
}
