//
//  PeriodQuery.swift
//  App
//
//  Created by nikstar on 24.09.2025.
//

import AppIntents
import WalletCore
import WidgetKit
import WalletContext

public enum PricePeriod: String, CaseIterable, Equatable, Hashable, Codable, Sendable, AppEnum, Identifiable, AppEntity {
    
    case day = "1D"
    case week = "7D"
    case month = "1M"
    case threeMonths = "3M"
    case year = "1Y"
    case all = "ALL"
    
    public static var typeDisplayRepresentation: TypeDisplayRepresentation = TypeDisplayRepresentation(name: "Chart Period")
    
    public static var caseDisplayRepresentations: [PricePeriod : DisplayRepresentation] {
        return [
            .all: "All",
            .year: "1 Year",
            .threeMonths: "3 Months",
            .month: "1 Month",
            .week: "1 Week",
            .day: "1 Day",
        ]
    }
    
    public var id: String { rawValue }
    
    public static var defaultQuery = PeriodQuery()
}

public struct PeriodQuery: EntityQuery {

    public init() {}
    
    public func entities(for identifiers: [PricePeriod.ID]) async throws -> [PricePeriod] {
        return identifiers.compactMap { PricePeriod(rawValue: $0) }
    }

    public func suggestedEntities() async throws -> IntentItemCollection<PricePeriod> {
        return IntentItemCollection(items: [.day, .week, .month, .threeMonths, .year])
    }
}
