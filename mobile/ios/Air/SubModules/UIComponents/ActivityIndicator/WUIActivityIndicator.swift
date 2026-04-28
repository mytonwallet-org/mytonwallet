import SwiftUI
import WalletContext

public struct WUIActivityIndicator: View {
    private let size: CGFloat?
    private let duration: TimeInterval

    @State private var angle: Angle = .zero

    public init(size: CGFloat? = nil, duration: TimeInterval = 0.625) {
        self.size = size
        self.duration = duration
    }

    public var body: some View {
        image
            .rotationEffect(angle)
            .onAppear {
                withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                    angle += .radians(2 * .pi)
                }
            }
    }

    @ViewBuilder
    private var image: some View {
        if let size {
            Image.airBundle("ActivityIndicator")
                .renderingMode(.template)
                .resizable()
                .frame(width: size, height: size)
        } else {
            Image.airBundle("ActivityIndicator")
                .renderingMode(.template)
        }
    }
}
