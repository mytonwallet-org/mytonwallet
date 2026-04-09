import ContextMenuKit
import UIKit

@MainActor
public final class SegmentedControlContextMenuProvider: Sendable {
    public let sourcePortal: ContextMenuSourcePortal?

    private let configurationProvider: () -> ContextMenuConfiguration

    public init(
        sourcePortal: ContextMenuSourcePortal? = nil,
        configuration: @escaping () -> ContextMenuConfiguration
    ) {
        self.sourcePortal = sourcePortal
        self.configurationProvider = configuration
    }

    public func makeConfiguration() -> ContextMenuConfiguration {
        self.configurationProvider()
    }
}
