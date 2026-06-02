import Foundation

public protocol MfaProtectedActionResult: Sendable {
    var mfaRequestHash: String? { get }
    var protectedActionError: String? { get }
    func handleMfaConfirmation(accountId: String, request: ApiMfaRequest) async throws
}

public extension MfaProtectedActionResult {
    var protectedActionError: String? { nil }
    func handleMfaConfirmation(accountId: String, request: ApiMfaRequest) async throws {}
}

public struct ApiMfaProtectedResult: Decodable, Sendable {
    public var activityId: String?
    public var activityIds: [String]?
    public var mfaRequestHash: String?
    public var error: String?

    public init(
        activityId: String? = nil,
        activityIds: [String]? = nil,
        mfaRequestHash: String? = nil,
        error: String? = nil
    ) {
        self.activityId = activityId
        self.activityIds = activityIds
        self.mfaRequestHash = mfaRequestHash
        self.error = error
    }

    public var firstActivityId: String? {
        activityId ?? activityIds?.first
    }
}

extension ApiMfaProtectedResult: MfaProtectedActionResult {
    public var protectedActionError: String? { error }
}
