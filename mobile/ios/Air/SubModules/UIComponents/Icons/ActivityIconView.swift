import SwiftUI
import WalletContext
import WalletCore

public struct ActivityIconView: UIViewRepresentable {

    public var activity: ApiActivity
    public var size: CGFloat
    public var accessorySize: CGFloat?
    
    public init(activity: ApiActivity, size: CGFloat, accessorySize: CGFloat?) {
        self.activity = activity
        self.size = size
        self.accessorySize = accessorySize
    }

    public func makeUIView(context: Context) -> IconView {
        IconView(size: size)
    }

    public func updateUIView(_ uiView: IconView, context: Context) {
        uiView.setSize(size)
        uiView.config(with: activity)
        if let accessorySize {
            let borderWidth = borderWidthForAccessorySize(accessorySize)
            let chainSize = max(0, accessorySize - 2 * borderWidth)
            let horizontalOffset = horizontalOffsetForAccessorySize(accessorySize)
            let verticalOffset = verticalOffsetForAccessorySize(accessorySize)
            uiView.setChainSize(chainSize, borderWidth: borderWidth, borderColor: WTheme.sheetBackground, horizontalOffset: horizontalOffset, verticalOffset: verticalOffset)
        }
    }

    private func borderWidthForAccessorySize(_ accessorySize: CGFloat) -> CGFloat {
        accessorySize <= 16 ? 1.0 : accessorySize < 50 ? 1.667 : 2.667
    }

    private func horizontalOffsetForAccessorySize(_ accessorySize: CGFloat) -> CGFloat {
        2.0
    }

    private func verticalOffsetForAccessorySize(_ accessorySize: CGFloat) -> CGFloat {
        accessorySize <= 16 ? 0 : 2
    }
}
