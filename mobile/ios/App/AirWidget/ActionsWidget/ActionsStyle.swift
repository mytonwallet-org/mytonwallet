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

    public static let typeDisplayRepresentation: TypeDisplayRepresentation = TypeDisplayRepresentation(name: "Style")
    
    public static var caseDisplayRepresentations: [ActionsStyle : DisplayRepresentation] = [
        .neutral: DisplayRepresentation(title: "Neutral"),
        .vivid: DisplayRepresentation(title: "Vivid"),
    ]
}
