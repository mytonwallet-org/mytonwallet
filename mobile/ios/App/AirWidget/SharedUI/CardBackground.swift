//
//  AirWidget.swift
//  AirWidget
//
//  Created by nikstar on 23.09.2025.
//

import SwiftUI
import WalletCore
import WalletContext
import UIComponents
import WidgetKit
import UIKit
import Charts

private let blurRadius: CGFloat = 100
private let defaultAccentColor = "0079C8" // design has 0088CC but it iOS then applies a brightening layer

func colorForSlug(_ tokenSlug: String, tokenColor: String?) -> Color {
    if tokenSlug == TRX_SLUG {
        return .red
    }
    return Color(UIColor(hex: tokenColor ?? defaultAccentColor))
}

struct CardBackground: View {
    
    var tokenSlug: String
    var tokenColor: String?
    
    var body: some View {
        let bottomColor = self.backgroundColor
        let topBackgroundColor = bottomColor.lightened(by: 0.12)
        let rightHighlightColor = bottomColor.lightened(by: 1.1)
        let leftHighlightColor = bottomColor.lightened(by: 1.3)
        
        return ZStack {
            topBackgroundColor
            
            Circle().fill(rightHighlightColor)
                .blur(radius: blurRadius)
                .scaleEffect(CGSize(width: 4, height: 0.8))
                .rotationEffect(.degrees(10))
                .offset(x: 280, y: -50)
            
            Circle().fill(bottomColor)
                .blur(radius: blurRadius)
                .scaleEffect(CGSize(width: 5, height: 2))
                .offset(x: 200, y: 100)
            
            Circle().fill(leftHighlightColor)
                .blur(radius: blurRadius)
                .scaleEffect(CGSize(width: 1.2, height: 0.5))
                .rotationEffect(.degrees(-20))
                .offset(x: -200, y: -20)

            // apply darkening layer here?
//            Color.black.opacity(0.2)
//                .blendMode(.overlay)
        }
        .overlay {
            
            Ellipse()
                .fill(.black.opacity(0.05))
                .strokeBorder(.white.opacity(0.05), lineWidth: 2)
                .frame(width: 190, height: 430)
                .rotationEffect(.degrees(30))
                .offset(x: 95, y: 80)
                .blendMode(.overlay)

            Ellipse()
                .fill(.black.opacity(0.07))
                .strokeBorder(.white.opacity(0.05), lineWidth: 2)
                .frame(width: 295, height: 690)
                .rotationEffect(.degrees(30))
                .offset(x: 70, y: 50)
                .blendMode(.overlay)

            Ellipse()
                .fill(.black.opacity(0.07))
                .strokeBorder(.white.opacity(0.05), lineWidth: 2)
                .frame(width: 395, height: 925)
                .rotationEffect(.degrees(30))
                .offset(x: 60, y: -20)
                .blendMode(.overlay)
        }
        .drawingGroup()
    }
    
    private var backgroundColor: Color {
        colorForSlug(tokenSlug, tokenColor: tokenColor)
    }
}

private extension Color {
    func lightened(by amount: CGFloat) -> Color {
        adjusted(brightnessDelta: amount, saturationDelta: -amount * 0.35)
    }
    
    func darkened(by amount: CGFloat) -> Color {
        adjusted(brightnessDelta: -amount, saturationDelta: amount * 0.25)
    }
    
    private func adjusted(brightnessDelta: CGFloat, saturationDelta: CGFloat) -> Color {
        let uiColor = UIColor(self)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        guard uiColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return self
        }
        let newSaturation = clamp(saturation + saturationDelta, min: 0, max: 1)
        let newBrightness = clamp(brightness + brightnessDelta, min: 0, max: 1)
        return Color(
            hue: Double(hue),
            saturation: Double(newSaturation),
            brightness: Double(newBrightness),
            opacity: Double(alpha)
        )
    }
    
    private func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.max(min, Swift.min(max, value))
    }
}

