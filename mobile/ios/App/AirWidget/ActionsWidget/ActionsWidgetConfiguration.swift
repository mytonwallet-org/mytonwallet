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

struct ActionsWidgetConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Actions"
    static var description: IntentDescription = "Quick access to actions."

    @Parameter(title: "Style", default: .neutral)
    var style: ActionsStyle
}
