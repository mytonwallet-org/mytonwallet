
import SwiftUI
import UIComponents
import WalletContext


struct ProgressBulletPoint: View {
    
    var status: StepStatus
    
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            switch status {
            case .none, .hidden:
                Circle()
                    .fill(Color.air.primaryLabel)
                    .frame(width: 3, height: 3)
                    .transition(.scale)

            case .current:
                WUIActivityIndicator(size: 14)
                    .foregroundStyle(.tint)
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
        .animation(.snappy, value: status)
    }
}
