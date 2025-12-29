
import SwiftUI
import WalletCore
import WalletContext


public struct AddViewButton<S: ShapeStyle>: View {
    
    var accountId: String
    var foregroundStyle: S
    
    public init(accountId: String, foregroundStyle: S) {
        self.accountId = accountId
        self.foregroundStyle = foregroundStyle
    }
    
    public var body: some View {
        if #available(iOS 26, iOSApplicationExtension 26, *) {
            Button(action: onTap) {
                sharedContent
                    .foregroundStyle(foregroundStyle)
            }
            .buttonStyle(.glassProminent)
            .tint(.blue)
        } else {
            Button(action: onTap) {
                sharedContent
                    .padding(7)
                    .background {
                        Rectangle()
                            .opacity(0.15)
                    }
                    .clipShape(.capsule)
                    .foregroundStyle(foregroundStyle)
            }
        }
    }
    
    var sharedContent: some View {
        HStack(spacing: 2) {
            Image.airBundle("AddView")
            Text(lang("$view_mode"))
        }
        .frame(height: 14)
        .font(.system(size: 14, weight: .semibold))
        .padding(.trailing, 1)
    }
    
    func onTap() {
        withAnimation {
            AppActions.saveTemporaryViewAccount(accountId: accountId)
        }
    }
}


#Preview {
    ZStack {
        HStack(spacing: 0) {
            Color.blue
            Color.blue.opacity(0.5)
        }
        
        VStack {
            AddViewButton(accountId: "0-mainnet", foregroundStyle: .white)
        }
        .scaleEffect(4)
        .padding()
    }
}
