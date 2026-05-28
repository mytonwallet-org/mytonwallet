
import SwiftUI
import UIComponents
import WalletContext


struct ProgressBulletPoint: View {
    
    var status: StepStatus
    
    @State private var angle: Angle = .zero
    
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            switch status {
            case .none, .hidden:
                Circle()
                    .fill(Color(WTheme.primaryLabel))
                    .frame(width: 3, height: 3)
                    .transition(.scale)

            case .current:
                Image.airBundle("ActivityIndicator")
                    .renderingMode(.template)
                    .resizable()
                    .foregroundStyle(Color(WTheme.tint))
                    .rotationEffect(angle)
                    .transition(.scale)
                
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .resizable()
                    .foregroundStyle(.green)
                    .transition(.scale)
                
            case .error:
                Image(systemName: "xmark.circle.fill")
                    .resizable()
                    .foregroundStyle(.red)
                    .transition(.scale)
                
            }
        }
        .frame(width: 14, height: 14)
        .frame(width: 20, height: 20)
        .alignmentGuide(.firstTextBaseline, computeValue: { $0.height - 4 })
        .onChange(of: status) { status in
            if case .current = status {
                withAnimation(.linear(duration: 0.625).repeatForever(autoreverses: false)) {
                    angle += .radians(2 * .pi)
                }
            }
        }
        .onAppear {
            if case .current = status {
                withAnimation(.linear(duration: 0.625).repeatForever(autoreverses: false)) {
                    angle += .radians(2 * .pi)
                }
            }
        }
        .animation(.snappy, value: status)
    }
}
