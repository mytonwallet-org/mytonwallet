//
//  ActionsWidgetTimelineProvider.swift
//  App
//
//  Created by nikstar on 23.09.2025.
//

import SwiftUI
import WalletCore
import WidgetKit


struct ActionsWidgetTimelineProvider: AppIntentTimelineProvider {
    
    func placeholder(in context: Context) -> ActionsWidgetTimelineEntry {
        return ActionsWidgetTimelineEntry.placeholder
    }

    func snapshot(for configuration: ActionsWidgetConfiguration, in context: Context) async -> ActionsWidgetTimelineEntry {
        if context.isPreview {
            return ActionsWidgetTimelineEntry.placeholder
        }
        return ActionsWidgetTimelineEntry(
            date: .now,
            style: configuration.style,
        )
    }

    func timeline(for configuration: ActionsWidgetConfiguration, in context: Context) async -> Timeline<ActionsWidgetTimelineEntry> {
        let entry = ActionsWidgetTimelineEntry(
            date: .now,
            style: configuration.style,
        )
        return Timeline(entries: [entry], policy: .after(Date(timeIntervalSinceNow: 1800)))
    }
}
