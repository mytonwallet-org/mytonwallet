
import SwiftUI
import UIComponents
import WalletContext
import Perception


struct LedgerSignView<HeaderView: View>: View {
    
    var headerView: HeaderView
    
    var viewModel: LedgerViewModel
    
    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                headerView
                    .padding(44)
                ZStack {
                    Color(WTheme.background)
                        .clipShape(.rect(cornerRadius: 16))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .ignoresSafeArea()
                    VStack(spacing: 0) {
                        Image.airBundle("LedgerConnect")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(.horizontal, 60)
                            .padding(.top, 20)
                            .padding(.bottom, 16)
                        LedgerStepsView(viewModel: viewModel)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
            Button(action: { viewModel.stop() }) {
                Text(lang("Cancel"))
            }
            .buttonStyle(WUIButtonStyle(style: .clearBackground))
            .environment(\.isEnabled, viewModel.backEnabled)
            
            if viewModel.showRetry {
                Button(action: { viewModel.restart() }) {
                    Text(lang("Try Again"))
                }
                .buttonStyle(WUIButtonStyle(style: .secondary))
                .environment(\.isEnabled, viewModel.retryEnabled)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 10)
        .animation(.smooth, value: viewModel.showRetry)
    }
}
