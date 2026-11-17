import SwiftUI
import WalletContext

public struct GramDiamondWithParticles: View {
    private let diamondSize: CGFloat
    private let isMetalAvailable: Bool

    @State private var isPressed = false
    @State private var isHovered = false

    public init(diamondSize: CGFloat = 130) {
        self.init(diamondSize: diamondSize, isMetalAvailable: TelegramDiamondView.isAvailable)
    }

    init(diamondSize: CGFloat, isMetalAvailable: Bool) {
        self.diamondSize = diamondSize
        self.isMetalAvailable = isMetalAvailable
    }

    public var body: some View {
        Group {
            if isMetalAvailable {
                ZStack {
                    SparkleParticleBackground(isWelcome: true, welcomeColor: .tintColor,
                                              isHovered: isHovered, isPressed: isPressed)
                        .frame(width: 386, height: 268)
                        .offset(y: -10)
                        .allowsHitTesting(false)
                    TelegramDiamondView(size: diamondSize * 1.5, stoneWidth: diamondSize,
                        maxGrow: 1.15, hoverSpeed: 2, shouldRotateOnTap: true,
                        onPressChange: { isPressed = $0 }, onHoverChange: { isHovered = $0 })
                        .frame(width: diamondSize, height: diamondSize)
                }
                .onDisappear {
                    isPressed = false
                    isHovered = false
                }
            } else {
                Image.airBundle("GramDiamond")
                    .resizable()
                    .scaledToFit()
                    .allowsHitTesting(false)
            }
        }
        .frame(width: diamondSize, height: diamondSize)
        .accessibilityHidden(true)
    }
}
