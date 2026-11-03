import SwiftUI
import UIKit

/// A tab page that takes a neighbouring tab's background color while the pager brings that tab in, so both screens
/// change color together
@MainActor
public protocol WPagingBackgroundTinting: AnyObject {
    /// The color to show behind the page's content, or nil for its own background
    func setPagingBackgroundColor(_ color: UIColor?)
}

/// The paging background color of a page whose background SwiftUI draws. Only `WPagingBackground` observes it, so a
/// color change on every paging frame redraws the background alone.
@MainActor
public final class WPagingBackgroundTint: ObservableObject {
    @Published public var color: UIColor?

    public init() {}
}

/// A page background that shows the paging tint while there is one, and `base` otherwise. Like a color background,
/// it reaches under the bars, past the safe area.
public struct WPagingBackground: View {
    @ObservedObject private var tint: WPagingBackgroundTint
    private let base: Color

    public init(tint: WPagingBackgroundTint, base: Color) {
        self.tint = tint
        self.base = base
    }

    public var body: some View {
        Group {
            if let color = tint.color {
                Color(uiColor: color)
            } else {
                base
            }
        }
        .ignoresSafeArea()
    }
}
