import Foundation

public struct ApiPortfolioHistoryResponse: Codable, Equatable, Sendable {
    public let status: String
    public let points: ApiHistoryList?
    public let datasets: [ApiPortfolioHistoryDataset]?
    public let base: String
    public let density: String
    public let historyScanCursor: Double?
    public let assetLimitExceeded: Bool?

    public init(
        status: String,
        points: ApiHistoryList?,
        datasets: [ApiPortfolioHistoryDataset]?,
        base: String,
        density: String,
        historyScanCursor: Double?,
        assetLimitExceeded: Bool?
    ) {
        self.status = status
        self.points = points
        self.datasets = datasets
        self.base = base
        self.density = density
        self.historyScanCursor = historyScanCursor
        self.assetLimitExceeded = assetLimitExceeded
    }
}

public struct ApiPortfolioHistoryDataset: Codable, Equatable, Sendable, Identifiable {
    public let assetId: Int
    public let symbol: String
    public let contractAddress: String
    public let color: String?
    public let points: ApiHistoryList
    public let impact: Double?

    public var id: Int { assetId }
}

public extension ApiPortfolioHistoryResponse {
    func normalizedForPortfolioDisplay(minimumValue: Double = 0.01) -> ApiPortfolioHistoryResponse {
        ApiPortfolioHistoryResponse(
            status: status,
            points: points,
            datasets: datasets?.map { $0.normalizedForPortfolioDisplay(minimumValue: minimumValue) },
            base: base,
            density: density,
            historyScanCursor: historyScanCursor,
            assetLimitExceeded: assetLimitExceeded
        )
    }
}

private extension ApiPortfolioHistoryDataset {
    func normalizedForPortfolioDisplay(minimumValue: Double) -> ApiPortfolioHistoryDataset {
        ApiPortfolioHistoryDataset(
            assetId: assetId,
            symbol: symbol,
            contractAddress: contractAddress,
            color: color,
            points: points.map { point in
                guard point.count >= 2, point[1] < minimumValue else {
                    return point
                }

                var normalizedPoint = point
                normalizedPoint[1] = 0
                return normalizedPoint
            },
            impact: impact
        )
    }
}
