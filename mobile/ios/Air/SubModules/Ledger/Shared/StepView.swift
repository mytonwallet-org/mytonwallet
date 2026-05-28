
import SwiftUI
import UIComponents
import WalletContext


struct StepView: View {
    
    var step: LedgerViewModel.Step
    
    var body: some View {
        GridRow {
            ProgressBulletPoint(status: step.status)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.id.displayTitlle)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle = step.status.displaySubtitle {
                    Text(subtitle)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(Color(WTheme.secondaryLabel))
                        .transition(.opacity.combined(with: .offset(y: -20)))
                }
            }
            .lineLimit(nil)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
