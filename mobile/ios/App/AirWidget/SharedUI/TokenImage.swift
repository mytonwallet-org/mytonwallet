//
//  TokenImage.swift
//  App
//
//  Created by nikstar on 24.09.2025.
//

import SwiftUI
import UIKit
import WidgetKit

struct TokenImage: View {
    
    var image: UIImage?
    var size: CGFloat
    
    @Environment(\.widgetRenderingMode) private var renderingMode
    
    var isFullColor: Bool { renderingMode == .fullColor }
    
    var body: some View {
        if let image {
            let image = Image(uiImage: image)
                .resizable()
                .clipShape(.circle)
                .padding(1)
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                }
                .frame(width: size, height: size)
            
            if isFullColor {
                image
            } else {
                image
                    .luminanceToAlpha()
            }
        }
    }
}
