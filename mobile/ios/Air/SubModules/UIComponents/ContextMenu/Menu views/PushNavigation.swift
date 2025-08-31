
import UIKit
import SwiftUI
import WalletContext

public struct PushNavigation<First: View, Second: View>: View {
    
    @EnvironmentObject private var context: MenuContext
    
    var first: (@escaping () -> ()) -> First
    var second: (@escaping () -> ()) -> Second
    
    @State private var detailsPresented: CGFloat = 0
    
    public init(first: @escaping (@escaping () -> Void) -> First, second: @escaping (@escaping () -> Void) -> Second) {
        self.first = first
        self.second = second
    }
    
    public var body: some View {
        first(push)
            .offset(x: -50 * detailsPresented)
            .opacity(1.0 - 0.35 * detailsPresented)
            .allowsHitTesting(detailsPresented == 0)
            .overlay(alignment: .top) {
                second(pop)
                    .offset(x: 250 * (1 - detailsPresented) )
                    .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged({ v in
                        detailsPresented = clamp(1.0 - v.translation.width / 250, to: 0...1)
                    }).onEnded({ v in
                        if abs(v.translation.width) > 20 {
                            if #available(iOS 17.0, *) {
                                withAnimation(.interpolatingSpring(.smooth, initialVelocity: v.velocity.width/100.0)) {
                                    detailsPresented = v.predictedEndTranslation.width > 100 ? 0 : 1
                                }
                            } else {
                                withAnimation(.interpolatingSpring) {
                                    detailsPresented = v.predictedEndTranslation.width > 100 ? 0 : 1
                                }
                            }
                        }
                    }))
            }
            .contentShape(.containerRelative)
            .clipped()
            .animation(.spring(duration: 0.25), value: detailsPresented)
            .onChange(of: detailsPresented) { detailsPresented in
                if detailsPresented == 0 {
                    context.setPrefix("0-")
                } else if detailsPresented == 1 {
                    context.setPrefix("1-")
                } else {
                    context.setPrefix("?")
                }
            }
    }
    
    func push() {
        withAnimation(.spring) {
            detailsPresented = 1
        }
    }
    
    func pop() {
        withAnimation(.spring) {
            detailsPresented = 0
        }
    }
}
