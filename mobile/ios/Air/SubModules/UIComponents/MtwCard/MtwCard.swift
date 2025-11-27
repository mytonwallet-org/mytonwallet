//
//  MtwCard.swift
//  UIComponents
//
//  Created by nikstar on 19.11.2025.
//

import SwiftUI

public struct MtwCard: View {
    
    var aspectRatio: CGFloat?
    
    public init(aspectRatio: CGFloat?) {
        self.aspectRatio = aspectRatio
    }
    
    public var body: some View {
        Color.clear
            .aspectRatio(aspectRatio, contentMode: .fit)
            .contentShape(.containerRelative)
    }
}
