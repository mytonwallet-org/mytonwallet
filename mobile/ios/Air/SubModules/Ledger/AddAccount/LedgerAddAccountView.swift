
import UIComponents
import WalletContext
import SwiftUI
import Perception


struct LedgerAddAccountView: View {
    
    var viewModel: LedgerViewModel
    
    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 32) {
                Image.airBundle("LedgerConnect")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(.top, 50)
                    .padding(.bottom, 30)
                ZStack {
                    Color(WTheme.background)
                        .clipShape(.rect(cornerRadius: 16))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .ignoresSafeArea()
                    VStack(spacing: 0) {
                        LedgerStepsView(viewModel: viewModel)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .padding(.top, 20)
                        buttons
                    }
                }
            }
            .navigationBarInset(60)
        }
    }
    
    @ViewBuilder
    var buttons: some View {
        HStack {
            if viewModel.showRetry {
                Button(action: { viewModel.restart() }) {
                    Text(lang("Try Again"))
                }
                .buttonStyle(WUIButtonStyle(style: .secondary))
                .environment(\.isEnabled, viewModel.retryEnabled)
            }
        }
        .frame(height: 50)
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 16)
        .animation(.smooth, value: viewModel.showRetry)
        
    }
}
