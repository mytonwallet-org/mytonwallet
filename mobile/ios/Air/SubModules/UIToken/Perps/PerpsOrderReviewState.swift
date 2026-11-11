import Foundation
import Perception

/// What a review's state needs of the data it shows.
protocol PerpsReviewData {
    var status: PerpsOrderReviewDisplayData.Status { get set }
}

extension PerpsOrderReviewDisplayData: PerpsReviewData {}

typealias PerpsOrderReviewState = PerpsReviewState<PerpsOrderReviewDisplayData>

@Perceptible @MainActor
final class PerpsReviewState<Data: PerpsReviewData> {
    private(set) var data: Data
    private(set) var pendingRequestID: UUID?
    @PerceptionIgnored private let onConfirm: (PerpsOrderReviewRequest) -> Void

    init(data: Data, onConfirm: @escaping (PerpsOrderReviewRequest) -> Void) {
        self.data = data
        self.onConfirm = onConfirm
    }

    var canConfirm: Bool { pendingRequestID == nil && data.status == .ready }

    /// While a confirmation is pending, only the update that answers it applies.
    @discardableResult
    func update(data: Data, for request: PerpsOrderReviewRequest? = nil) -> Bool {
        guard pendingRequestID == request?.id else { return false }
        self.data = data
        pendingRequestID = nil
        return true
    }

    func confirm() {
        guard canConfirm else { return }
        let request = PerpsOrderReviewRequest(id: UUID())
        pendingRequestID = request.id
        data.status = .loading
        onConfirm(request)
    }
}
