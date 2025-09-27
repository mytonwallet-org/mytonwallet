//
//  TokenWidgetTimelineEntry.swift
//  App
//
//  Created by nikstar on 23.09.2025.
//

import SwiftUI
import WalletCore
import WidgetKit

public struct ActionsWidgetTimelineEntry: TimelineEntry {
    public var date: Date
    public var style: ActionsStyle
}

public extension ActionsWidgetTimelineEntry {
    static var placeholder: ActionsWidgetTimelineEntry {
        return ActionsWidgetTimelineEntry(
            date: .now,
            style: .neutral,
        )
    }
}   
