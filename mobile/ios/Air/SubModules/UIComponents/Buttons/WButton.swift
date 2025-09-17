//
//  WButton.swift
//  UIComponents
//
//  Created by Sina on 3/30/23.
//

import UIKit
import SwiftUI
import WalletContext

fileprivate let _borderRadius = 12.0
fileprivate let _font = UIFont.systemFont(ofSize: 17, weight: .semibold)
fileprivate let _accentFont = UIFont.systemFont(ofSize: 12, weight: .regular)

public enum WButtonStyle {
    case primary
    case secondary
    case clearBackground
    case accent
    case none
}

public class WButton: WBaseButton, WThemedView {

    public static let defaultHeight = CGFloat(50.0)
    public static let defaultHeightAccent = CGFloat(60.0)

    private(set) public var style = WButtonStyle.primary

    public convenience init(style: WButtonStyle = .primary, buttonType: UIButton.ButtonType = .system) {
        self.init(type: buttonType)
        self.style = style
        self.setup()
    }
    
    private func setup() {
        // disable default styling of iOS 15+ to prevent tint/font set conflict issues
        // setting configuration to .none on interface builder makes text disappear
        configuration = .none
        
        // set corner radius
        layer.cornerRadius = _borderRadius
        // set height anchor as default value
        let _height: CGFloat
        switch style {
        case .accent:
            _height = WButton.defaultHeightAccent
            break
        default:
            _height = WButton.defaultHeight
            break
        }
        let heightConstraint = heightAnchor.constraint(
            equalToConstant: _height
        )
        heightConstraint.priority = UILayoutPriority(800)
        heightConstraint.isActive = true
        // set font
        switch style {
        case .accent:
            titleLabel?.font = _accentFont
        default:
            titleLabel?.font = _font
        }
        
        // set theme colors
        updateTheme()
    }
    
    private var primaryButtonTint: UIColor {
        if WTheme.primaryButton.background == .label {
            return WTheme.background
        } else {
            return WTheme.primaryButton.tint
        }
    }
    
    public func updateTheme() {
        switch style {
        case .primary:
            if !forcedBackgroundColor {
                super.backgroundColor = isEnabled ? WTheme.primaryButton.background : WTheme.primaryButton.disabledBackground
            }
            if !forcedTintColor {
                super.tintColor = isEnabled ? primaryButtonTint : WTheme.primaryButton.disabledTint
            }

        case .secondary:
            if !forcedBackgroundColor {
                super.backgroundColor = isEnabled ? WTheme.tint.withAlphaComponent(0.15) : .clear
            }
            if !forcedTintColor {
                super.tintColor = isEnabled ? WTheme.tint : WTheme.tint.withAlphaComponent(0.5)
            }

        case .clearBackground:
            super.backgroundColor = .clear
            if !forcedTintColor {
                super.tintColor = isEnabled ? WTheme.tint : WTheme.tint.withAlphaComponent(0.5)
            }

        case .accent:
            if !forcedBackgroundColor {
                super.backgroundColor = WTheme.accentButton.background
            }
            if !forcedTintColor {
                super.tintColor = WTheme.accentButton.tint
            }

        default:
            break
        }
    }
    
    var forcedTintColor: Bool = false
    public override var tintColor: UIColor! {
        get {
            return super.tintColor
        }
        set {
            forcedTintColor = true
            super.tintColor = newValue
        }
    }
    
    var forcedBackgroundColor: Bool = false
    public override var backgroundColor: UIColor? {
        get {
            return super.backgroundColor
        }
        set {
            forcedBackgroundColor = true
            super.backgroundColor = newValue
        }
    }

    // used to place a gap between the image and text
    public func centerTextAndImage(spacing: CGFloat, additionalOffset: CGFloat = 0) {
        switch style {
        case .primary, .secondary, .clearBackground, .none:
            let insetAmount = spacing / 2
            let isRTL = UIView.userInterfaceLayoutDirection(for: semanticContentAttribute) == .rightToLeft
            if isRTL {
               imageEdgeInsets = UIEdgeInsets(top: 0, left: insetAmount, bottom: 0, right: -insetAmount)
               titleEdgeInsets = UIEdgeInsets(top: 0, left: -insetAmount, bottom: 0, right: insetAmount)
               contentEdgeInsets = UIEdgeInsets(top: 0, left: -insetAmount, bottom: 0, right: -insetAmount)
            } else {
               imageEdgeInsets = UIEdgeInsets(top: 0, left: -insetAmount, bottom: 0, right: insetAmount)
               titleEdgeInsets = UIEdgeInsets(top: 0, left: insetAmount, bottom: 0, right: -insetAmount)
               contentEdgeInsets = UIEdgeInsets(top: 0, left: insetAmount, bottom: 0, right: insetAmount)
            }
            break
        case .accent:
            guard let imageSize = self.imageView?.image?.size,
                        let text = self.titleLabel?.text,
                        let font = self.titleLabel?.font
                        else { return }
            let labelString = NSString(string: text)
            let titleSize = labelString.size(withAttributes: [.font: font])
            if isRTL {
                self.titleEdgeInsets = UIEdgeInsets(top: 0.0,
                                                    left: 0,
                                                    bottom: -(imageSize.height + spacing) + additionalOffset / 2,
                                                    right: -imageSize.width)
            } else {
                self.titleEdgeInsets = UIEdgeInsets(top: 0.0,
                                                    left: -imageSize.width,
                                                    bottom: -(imageSize.height + spacing) + additionalOffset / 2,
                                                    right: 0.0)
            }
            if isRTL {
                self.imageEdgeInsets = UIEdgeInsets(top: -(titleSize.height + spacing) + additionalOffset / 4,
                                                    left: -titleSize.width,
                                                    bottom: additionalOffset / 4,
                                                    right: 0.0)
            } else {
                self.imageEdgeInsets = UIEdgeInsets(top: -(titleSize.height + spacing) + additionalOffset / 4,
                                                    left: 0.0,
                                                    bottom: additionalOffset / 4,
                                                    right: -titleSize.width)
            }
            let edgeOffset = abs(titleSize.height - imageSize.height) / 2.0;
            self.contentEdgeInsets = UIEdgeInsets(top: edgeOffset + additionalOffset,
                                                  left: 0.0,
                                                  bottom: edgeOffset + additionalOffset,
                                                  right: 0.0)
            break
        }
    }

    public override var isEnabled: Bool {
        didSet {
            updateTheme()
        }
    }
    
    // MARK: - Loading View
    private var loadingView: WActivityIndicator? = nil
    public var showLoading: Bool = false {
        didSet {
            if showLoading {
                if loadingView == nil {
                    loadingView = WActivityIndicator()
                    loadingView!.translatesAutoresizingMaskIntoConstraints = false
                    loadingView?.tintColor = style == .secondary ? WTheme.primaryButton.background :  .white
                    addSubview(loadingView!)
                    NSLayoutConstraint.activate([
                        loadingView!.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
                        loadingView!.centerYAnchor.constraint(equalTo: centerYAnchor)
                    ])
                }
                loadingView?.startAnimating(animated: true)
            } else {
                loadingView?.stopAnimating(animated: true)
            }
        }
    }
    
    public func apply(config: WButtonConfig) {
        self.setTitle(config.title, for: .normal)
        self.isEnabled = config.isEnabled
    }
}


public struct WUIButtonStyle: PrimitiveButtonStyle {
    
    public var style: WButtonStyle
    public var loadingIndicatorDelay: CGFloat = 0.2
    
    public init(style: WButtonStyle) {
        self.style = style
    }
    
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isLoading) private var isLoading
    @State private var isTouching: Bool = false
    @State private var angle: Angle = .zero
    @State private var isShowingLoadingIndicator = false
    
    var textColor: UIColor {
        switch style {
        case .primary:
            UIColor.white // FIXME: Doesn't work for white theme color
        case .secondary:
            WTheme.tint
        case .clearBackground:
            WTheme.tint
        default:
            WTheme.tint
        }
    }
    
    var backgroundColor: UIColor {
        switch style {
        case .primary:
            WTheme.tint
        case .secondary:
            WTheme.tint.withAlphaComponent(0.15)
        case .clearBackground:
            .clear
        default:
            .clear
        }
    }
    
    public func makeBody(configuration: Configuration) -> some View {
        HStack  {
            if !isShowingLoadingIndicator {
                configuration.label
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            } else {
                loadingIndicator
                    .rotationEffect(angle)
                    .onAppear {
                        withAnimation(.linear(duration: 0.625).repeatForever(autoreverses: false)) {
                            angle += .radians(2 * .pi)
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .font(Font(_font))
        .overlay {
        }
        .foregroundStyle(Color(textColor))
        .opacity(isEnabled && isTouching ? 0.5 : 1)
        .frame(height: 50)
        .frame(maxWidth: .infinity)
        .background(Color(backgroundColor), in: .rect(cornerRadius: _borderRadius))
        .opacity(isEnabled ? 1 : 0.5)
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
    
    var loadingIndicator: some View {
        Image.airBundle("ActivityIndicator")
            .renderingMode(.template)
    }
}

public extension PrimitiveButtonStyle where Self == WUIButtonStyle {
    static var airPrimary: WUIButtonStyle { WUIButtonStyle(style: .primary) }
    static var airSecondary: WUIButtonStyle { WUIButtonStyle(style: .secondary) }
    static var airClearBackground: WUIButtonStyle { WUIButtonStyle(style: .clearBackground) }
}

public extension EnvironmentValues {
    @Entry var isLoading = false
}

#if DEBUG
@available(iOS 17.0, *)
#Preview {
    @Previewable @State var isLoading = false
    
    Button(action: {}) {
        Text("Helldo")
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
#endif
