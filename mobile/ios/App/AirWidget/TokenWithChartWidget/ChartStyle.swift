//
//  ChartStyle.swift
//  App
//
//  Created by nikstar on 26.09.2025.
//


import AppIntents
import WalletCore
import WidgetKit
import WalletContext

public enum ChartStyle: String, AppEnum {

    case vivid
    case dark

    public static let typeDisplayRepresentation: TypeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("Style", bundle: LocalizationSupport.shared.bundle))
    
    public static var caseDisplayRepresentations: [ChartStyle : DisplayRepresentation] = [
        .vivid: DisplayRepresentation(title: LocalizedStringResource("Vivid", bundle: LocalizationSupport.shared.bundle)),
        .dark: DisplayRepresentation(title: LocalizedStringResource("Dark", bundle: LocalizationSupport.shared.bundle)),
    ]
}
