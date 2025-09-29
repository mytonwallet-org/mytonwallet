//
//  ActionsWidgetConfiguration.swift
//  AirWidget
//
//  Created by nikstar on 23.09.2025.
//

import AppIntents
import WalletCore
import WidgetKit
import WalletContext

public enum ActionsStyle: String, AppEnum {

    case neutral
    case vivid

    public static let typeDisplayRepresentation: TypeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("Style", bundle: LocalizationSupport.shared.bundle))
    
    public static var caseDisplayRepresentations: [ActionsStyle : DisplayRepresentation] = [
        .neutral: DisplayRepresentation(title: LocalizedStringResource("Neutral", bundle: LocalizationSupport.shared.bundle)),
        .vivid: DisplayRepresentation(title: LocalizedStringResource("Vivid", bundle: LocalizationSupport.shared.bundle)),
    ]
}
