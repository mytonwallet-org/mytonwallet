//
//  WButton.swift
//  UIComponents
//
//  Created by Sina on 3/30/23.
//

import UIKit
import SwiftUI
import WalletContext


public struct WUIButtonStyle: PrimitiveButtonStyle {
    
    public var style: WButtonStyle
    public var loadingIndicatorDelay: CGFloat = 0.2
    public var useLegacyShadow: Bool

    public init(style: WButtonStyle, useLegacyShadow: Bool = false) {
        self.style = style
        self.useLegacyShadow = useLegacyShadow
    }
    
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isLoading) private var isLoading
    @State private var isTouching: Bool = false
    @State private var isShowingLoadingIndicator = false
    
    var textColor: UIColor {
        switch style {
        case .primary:
            UIColor.white // FIXME: Doesn't work for white theme color
        case .destructive:
            .white
        case .thickDestructiveCapsule:
            isEnabled ? .air.error : .air.secondaryLabel
        case .secondary, .clearBackground, .thickCapsule:
            .tintColor
        }
    }

    var backgroundColor: UIColor {
        switch style {
        case .primary:
            .tintColor
        case .secondary:
            .tintColor.withAlphaComponent(0.15)
        case .clearBackground:
            .clear
        case .thickDestructiveCapsule, .thickCapsule:
            if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
                .clear
            } else {
                .air.secondaryFill
            }
        case .destructive:
            .air.error
        }
    }
    
    public func makeBody(configuration: Configuration) -> some View {
        Group {
            if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
                content(configuration: configuration)
                    .glassEffect(Glass.regular.tint(Color(backgroundColor)).interactive(isEnabled), in: .capsule)
            } else if useLegacyShadow {
                content(configuration: configuration)
                    .background(Color(backgroundColor), in: .rect(cornerRadius: WButton.borderRadius))
                    .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 2)
            } else {
                content(configuration: configuration)
                    .background(Color(backgroundColor), in: .rect(cornerRadius: WButton.borderRadius))
            }
        }
        .opacity(isEnabled || style == .thickDestructiveCapsule ? 1 : 0.5)
        .contentShape(.rect)
        .onTapGesture {
            configuration.trigger()
        }
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in
            withAnimation(.spring(duration: 0.1)) {
                isTouching = true
            }
        }.onEnded { _ in
            withAnimation(.spring(duration: 0.5)) {
                isTouching = false
            }
        })
        .allowsHitTesting(!isLoading)
        .onChange(of: isLoading) { isLoading in
            withAnimation(.spring().delay(isLoading ? loadingIndicatorDelay : 0)) {
                isShowingLoadingIndicator = isLoading
            }
        }
    }
    
    func content(configuration: Configuration) -> some View {
        HStack  {
            if !isShowingLoadingIndicator {
                configuration.label
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            } else {
                loadingIndicator
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .font(Font(WButton.font(for: style)))
        .foregroundStyle(Color(textColor))
        .opacity(isEnabled && isTouching ? 0.5 : 1)
        .frame(height: IOS_26_MODE_ENABLED ? 52 : 50)
        .frame(maxWidth: .infinity)
    }
    
    var loadingIndicator: some View {
        WUIActivityIndicator()
    }
}

public extension PrimitiveButtonStyle where Self == WUIButtonStyle {
    static var airPrimary: WUIButtonStyle { WUIButtonStyle(style: .primary) }
    static var airSecondary: WUIButtonStyle { WUIButtonStyle(style: .secondary) }
    static var airSecondaryDestructive: WUIButtonStyle {  WUIButtonStyle(style: .thickDestructiveCapsule) }
    static var airClearBackground: WUIButtonStyle { WUIButtonStyle(style: .clearBackground) }
    
    func withLegacyShadow() -> WUIButtonStyle {
        var result = self
        result.useLegacyShadow = true
        return result
    }
}

public extension EnvironmentValues {
    @Entry var isLoading = false
}

#if DEBUG
@available(iOS 17.0, *)
#Preview("Loading") {
    @Previewable @State var isLoading = false

    Button(action: {}) {
        Text("Hello")
    }
    .buttonStyle(.airPrimary)
    .environment(\.isLoading, isLoading)
    .padding()
    .task {
        isLoading = false
        try? await Task.sleep(for: .seconds(2))
        isLoading = true
        try? await Task.sleep(for: .seconds(2))
        isLoading = false
        try? await Task.sleep(for: .seconds(2))
        isLoading = true
    }
}

@available(iOS 17.0, *)
#Preview("All Styles") {
    let styles: [(String, WUIButtonStyle)] = [
        ("Primary", .airPrimary),
        ("Secondary", .airSecondary),
        ("Secondary Destructive", .airSecondaryDestructive),
        ("Secondary Destructive Shadow", .airSecondaryDestructive.withLegacyShadow()),
        ("Clear", .airClearBackground),
    ]

    ScrollView {
        VStack(spacing: 24) {
            ForEach(styles, id: \.0) { name, style in
                VStack(alignment: .leading, spacing: 8) {
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)

                    HStack(spacing: 12) {
                        Button(action: {}) { Text("Enabled") }
                            .buttonStyle(style)

                        Button(action: {}) { Text("Disabled") }
                            .buttonStyle(style)
                            .disabled(true)
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding(.vertical)
    }
}
#endif
