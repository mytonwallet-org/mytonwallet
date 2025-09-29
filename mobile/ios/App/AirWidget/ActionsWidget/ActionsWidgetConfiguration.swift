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
    static var title: LocalizedStringResource = LocalizedStringResource("Actions", bundle: LocalizationSupport.shared.bundle)
    static var description: IntentDescription = IntentDescription(LocalizedStringResource("$actions_description", bundle: LocalizationSupport.shared.bundle))

    @Parameter(title: LocalizedStringResource("Style", bundle: LocalizationSupport.shared.bundle), default: .neutral)
    var style: ActionsStyle
}
