import Foundation
import Perception

@Perceptible @MainActor
final class PerpsOrderReviewState {
    private(set) var data: PerpsOrderReviewDisplayData
    private(set) var pendingRequestID: UUID?
    @PerceptionIgnored private let onConfirm: (PerpsOrderReviewRequest) -> Void
    @PerceptionIgnored private let onSelectPayment: ((PerpsOrderReviewRequest) -> Void)?

    init(data: PerpsOrderReviewDisplayData, onSelectPayment: ((PerpsOrderReviewRequest) -> Void)? = nil,
         onConfirm: @escaping (PerpsOrderReviewRequest) -> Void) {
        self.data = data
        self.onConfirm = onConfirm
        self.onSelectPayment = onSelectPayment
    }

    var canConfirm: Bool { pendingRequestID == nil && data.status == .ready && (data.mode.operation == .open || data.positionID?.isEmpty == false) }
    var canSelectPayment: Bool {
        data.status == .ready && data.mode.operation == .close && data.canSelectPayment && onSelectPayment != nil && pendingRequestID == nil
    }

    @discardableResult
    func update(data: PerpsOrderReviewDisplayData, for request: PerpsOrderReviewRequest? = nil) -> Bool {
        guard pendingRequestID == request?.id, data.positionID == self.data.positionID,
              data.mode.operation == self.data.mode.operation else { return false }
        if let request {
            guard request.reviewID == self.data.id, request.positionID == self.data.positionID,
                  request.operation == self.data.mode.operation else { return false }
        }
        self.data = data
        pendingRequestID = nil
        return true
    }

    func confirm() {
        guard canConfirm else { return }
        let request = makeRequest(.confirm)
        pendingRequestID = request.id
        data.status = .loading
        onConfirm(request)
    }

    func selectPayment() {
        guard canSelectPayment else { return }
        let request = makeRequest(.selectPayment)
        pendingRequestID = request.id
        data.status = .loading
        onSelectPayment?(request)
    }

    private func makeRequest(_ action: PerpsOrderReviewRequest.Action) -> PerpsOrderReviewRequest {
        .init(id: UUID(), reviewID: data.id, positionID: data.positionID, operation: data.mode.operation, action: action)
    }
}
