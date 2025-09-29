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
    
    public static var typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("Chart Period", bundle: LocalizationSupport.shared.bundle))
    
    public static var caseDisplayRepresentations: [PricePeriod : DisplayRepresentation] {
        return [
            .all: DisplayRepresentation(title: LocalizedStringResource("$period_all", bundle: LocalizationSupport.shared.bundle)),
            .year: DisplayRepresentation(title: LocalizedStringResource("$period_year", bundle: LocalizationSupport.shared.bundle)),
            .threeMonths: DisplayRepresentation(title: LocalizedStringResource("$period_3months", bundle: LocalizationSupport.shared.bundle)),
            .month: DisplayRepresentation(title: LocalizedStringResource("$period_month", bundle: LocalizationSupport.shared.bundle)),
            .week: DisplayRepresentation(title: LocalizedStringResource("$period_week", bundle: LocalizationSupport.shared.bundle)),
            .day: DisplayRepresentation(title: LocalizedStringResource("$period_day", bundle: LocalizationSupport.shared.bundle)),
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
        return IntentItemCollection(items: [.all, .year, .threeMonths, .month, .week, .day])
    }
}
