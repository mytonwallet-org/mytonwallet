
import SwiftUI
import UIComponents
import WalletContext
import Perception


struct LedgerStepsView: View {
    var viewModel: LedgerViewModel
    
    var body: some View {
        WithPerceptionTracking {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 12) {
                ForEach(viewModel.steps) { step in
                    StepView(step: step)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 16)
            .padding(.horizontal, 16)
            .padding(.horizontal, 16)
            .animation(.default, value: viewModel.steps)
        }
    }
}
