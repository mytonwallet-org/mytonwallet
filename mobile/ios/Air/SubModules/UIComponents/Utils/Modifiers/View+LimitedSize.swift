import SwiftUI

extension View {
    /// Limits the view’s width to the given value **without expanding it**.
    /// Unlike `frame(maxWidth:/maxHeight:)`, it never forces the view to grow.
    /// The view keeps its intrinsic size and is only capped if it exceeds the limit.
    public func limitedSize(widthLimit: Double) -> some View {
        LimitedSizeLayout(widthLimit: widthLimit, heightLimit: nil) { self }
    }
}

fileprivate struct LimitedSizeLayout: Layout {
    private let widthLimit: CGFloat?
    private let heightLimit: CGFloat?

    init(widthLimit: CGFloat? = nil, heightLimit: CGFloat? = nil) {
        self.widthLimit = widthLimit
        self.heightLimit = heightLimit
    }

    func sizeThatFits(proposal _: ProposedViewSize,
                      subviews: Subviews,
                      cache _: inout ()) -> CGSize {
        let intrinsic = subviews[0].sizeThatFits(.unspecified)
        let width = widthLimit.map { min(intrinsic.width, $0) } ?? intrinsic.width
        let height = heightLimit.map { min(intrinsic.height, $0) } ?? intrinsic.height
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        subviews[0].place(at: bounds.origin,
                          proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}
