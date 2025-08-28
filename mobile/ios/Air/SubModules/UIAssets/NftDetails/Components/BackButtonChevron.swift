
import SwiftUI

struct BackButtonChevron: View {
    
    var action: () -> ()
    
    var body: some View {
        Button(action: action) {
            Image.airBundle("BackButtonChevron32")
                .frame(width: 32, height: 32)
                .padding(.leading, 16)
                .contentShape(.rect)
        }
    }
}