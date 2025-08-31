
import Foundation
import SwiftUI
import WalletCore
import WalletContext


public struct TipView<Content: View>: View {
    
    var title: String
    var wide: Bool
    var content: () -> Content
    
    @State private var show = false
    @State private var dismissing = false
    @State private var dy: CGFloat = 0
    
    public init(title: String, wide: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.wide = wide
        self.content = content
    }
    
    public var body: some View {
        ZStack(alignment: .center) {
            Color.clear.ignoresSafeArea()
            if show {
                Color.black.opacity(dismissing ? 0 : 0.4).ignoresSafeArea()
                    .transition(.opacity)
                    .contentShape(.rect)
                    .onTapGesture {
                        if dy == 0 {
                            dismiss()
                        }
                    }
                    .gesture(dragGesture)
                contents
                    .transition(.asymmetric(
                        insertion: .scale(scale: 1.15).combined(with: .opacity),
                        removal: .identity
                    ))
                    .opacity(dismissing ? 0 : 1)
                    .gesture(dragGesture)
            }
        }
        .onAppear {
            withAnimation(.spring(duration: 0.3)) {
                show = true
            }
        }
    }
    
    var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged({ drag in
                self.dy = drag.translation.height
            })
            .onEnded({ drag in
                if drag.predictedEndTranslation.height > 90 {
                    dismiss()
                } else {
                    withAnimation(.spring) {
                        dy = 0
                    }
                }
        })
    }
    
    var contents: some View {
        VStack(spacing: 0) {
            
            VStack(spacing: 8) {
                Image("TipIcon", bundle: AirBundle)
                    .foregroundStyle(Color(WTheme.tint))
                    .padding(4)
                
                Text(title)
                    .fontWeight(.semibold)
                    .font17h22()

                content()
                    .font13()
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 18)
            .background(Color(WTheme.modularBackground))
            
            Rectangle()
                .fill(Color(WTheme.separator))
                .frame(height: 0.333)
            
            Button(action: dismiss) {
                Text(lang("OK"))
                    .fontWeight(.semibold)
                    .font17h22()
                    .foregroundStyle(Color(WTheme.tint))
                    .tint(Color(WTheme.tint))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .contentShape(.rect)
                    .background(Color(WTheme.modularBackground))
            }
        }
        .clipShape(.rect(cornerRadius: 14))
        .padding(.horizontal, wide ? 32 : 60)
        .offset(y: dy / 6)
        .buttonStyle(.plain)
    }
    
    func dismiss() {
        let duration = 0.25
        withAnimation(.easeIn(duration: duration)) {
            dismissing = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.02) {
            topViewController()?.presentingViewController?.dismiss(animated: false)
        }
    }
}
