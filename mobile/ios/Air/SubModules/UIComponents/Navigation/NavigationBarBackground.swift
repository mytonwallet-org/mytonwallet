//
//  NavigationBarBackground.swift
//  MyTonWalletAir
//
//  Created by nikstar on 10.11.2025.
//

import SwiftUI

public struct NavigationBarBackground: View {
    
    let fillColor = Color.air.sheetBackground
    let maxOpacity = 0.85
    
    public init() {
    }
    
    public var body: some View {
        ZStack {
            Rectangle().fill(gradient)
            VariableBlurView(maxBlurRadius: 1.5, direction: .custom(blurImage))
        }
    }
    
    var gradient: LinearGradient {
        LinearGradient(
            stops: [
                Gradient.Stop(color: fillColor.opacity(maxOpacity * 1), location: 0.5),
                Gradient.Stop(color: fillColor.opacity(maxOpacity * 0.9), location: 0.6),
                Gradient.Stop(color: fillColor.opacity(maxOpacity * 0.5), location: 0.85),
                Gradient.Stop(color: fillColor.opacity(maxOpacity * 0), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private let blurImage = _makeGradientImage()

private func _makeGradientImage(width: CGFloat = 100, height: CGFloat = 100) -> CGImage {
    let ciGradientFilter =  CIFilter.linearGradient()
    ciGradientFilter.color0 = CIColor.clear
    ciGradientFilter.color1 = CIColor.black
    ciGradientFilter.point0 = CGPoint(x: 0, y: 0.0 * height)
    ciGradientFilter.point1 = CGPoint(x: 0, y: 0.1 * height)
    return CIContext().createCGImage(ciGradientFilter.outputImage!, from: CGRect(x: 0, y: 0, width: width, height: height))!
}


#Preview {
    ZStack {
        HStack(spacing: 0) {
            Color.blue.opacity(0.5)
            Color.blue.opacity(0.8)
        }
        NavigationBarBackground()
            .frame(height: 100)
    }
}
