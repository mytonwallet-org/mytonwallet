//
//  NavigationHeader.swift
//  MyTonWalletAir
//
//  Created by nikstar on 10.11.2025.
//

import SwiftUI

public struct NavigationHeader<Title: View, Subtitle: View>: View {
    
    var title: Title
    var subtitle: Subtitle
    
    public init(@ViewBuilder title: () -> Title, @ViewBuilder subtitle: () -> Subtitle) {
        self.title = title()
        self.subtitle = subtitle()
    }
    
    public var body: some View {
        VStack(spacing: 2) {
            _title
            _subtitle
        }
        .frame(minWidth: 240, idealWidth: 240)
    }
    
    var _title: some View {
        title
            .font(.system(size: 17, weight: .semibold))
            .lineLimit(1)
    }
    
    var _subtitle: some View {
        subtitle
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(.secondary)
            .allowsTightening(true)
            .lineLimit(1)
            .offset(y: 1)
    }
}

extension NavigationHeader where Subtitle == EmptyView {
    public init(@ViewBuilder title: () -> Title) {
        self.title = title()
        self.subtitle = EmptyView()
    }
}
