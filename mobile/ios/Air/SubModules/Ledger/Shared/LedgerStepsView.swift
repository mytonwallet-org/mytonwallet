
import SwiftUI
import UIComponents
import WalletContext
import WalletCore


struct LedgerStepsView: View {
    @ObservedObject var viewModel: LedgerViewModel
    
    var body: some View {
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
