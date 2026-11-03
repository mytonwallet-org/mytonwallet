import SwiftUI

@MainActor
final class PerpsHomeState: ObservableObject {
    @Published private(set) var data: PerpsHomeDisplayData
    @Published var operationStatus: PerpsOperationStatusDisplayData?
    private let onAction: (PerpsHomeAction) -> Void

    init(data: PerpsHomeDisplayData, onAction: @escaping (PerpsHomeAction) -> Void) {
        self.data = Self.normalized(data)
        self.onAction = onAction
    }

    /// A controller belongs to one wallet. A different wallet needs its own controller/state.
    func update(_ data: PerpsHomeDisplayData) {
        guard data.positions.accountID == self.data.positions.accountID else { return }
        self.data = Self.normalized(data)
    }

    func send(_ action: PerpsHomeAction) {
        switch action {
        case .position(let id):
            guard data.positions.status == .ready,
                  data.positions.positions.contains(where: { $0.id == id && $0.canSelect }) else { return }
        case .allPositions:
            guard data.positions.status == .ready, data.positions.totalCount > 0 else { return }
        case .activity(let id):
            guard data.activities.contains(where: { $0.id == id && $0.canSelect }) else { return }
        case .marketToken(let sectionID, let tokenID):
            guard data.marketSections.contains(where: { $0.id == sectionID && $0.tokens.contains(where: { $0.id == tokenID }) }) else { return }
        case .marketSection(let id):
            guard data.marketSections.contains(where: { $0.id == id && $0.showsSeeAll }) else { return }
        case .refresh: break
        }
        onAction(action)
    }

    private static func normalized(_ value: PerpsHomeDisplayData) -> PerpsHomeDisplayData {
        var value = value
        value.positions.positions = unique(value.positions.positions)
        value.positions.totalCount = max(value.positions.totalCount, value.positions.positions.count)
        value.activities = unique(value.activities)
        value.marketSections = unique(value.marketSections).map {
            var section = $0
            section.tokens = unique(section.tokens)
            return section
        }
        return value
    }

    private static func unique<T: Identifiable>(_ values: [T]) -> [T] where T.ID: Hashable {
        var ids = Set<T.ID>()
        return values.filter { ids.insert($0.id).inserted }
    }
}

public struct PerpsOperationStatusDisplayData {
    public let title: String
    public let message: String
    public let onSelect: () -> Void
    public let onDismiss: () -> Void

    public init(title: String, message: String, onSelect: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.title = title; self.message = message; self.onSelect = onSelect; self.onDismiss = onDismiss
    }
}
