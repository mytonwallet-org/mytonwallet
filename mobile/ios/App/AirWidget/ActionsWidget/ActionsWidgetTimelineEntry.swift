import WidgetKit

public struct ActionsWidgetTimelineEntry: TimelineEntry {
    public var date: Date
    public var style: ActionsStyle
}

public extension ActionsWidgetTimelineEntry {
    static var placeholder: ActionsWidgetTimelineEntry {
        ActionsWidgetTimelineEntry(
            date: .now,
            style: .neutral,
        )
    }
}
