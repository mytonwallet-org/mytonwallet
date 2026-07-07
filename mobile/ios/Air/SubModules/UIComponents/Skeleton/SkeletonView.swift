//
//  SkeletonView.swift
//  UIComponents
//
//  Created by Sina on 7/7/24.
//

import SwiftUI
import UIKit
import WalletContext

public class SkeletonView: UIView {
    
    private var gradientLayer: CAGradientLayer!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isHidden = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public let colors: [UIColor] = [UIColor.white.withAlphaComponent(0), UIColor.white.withAlphaComponent(0.3)]
    
    public func setupView(vertical: Bool) {
        gradientLayer = CAGradientLayer()
        if vertical {
            gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
            gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        } else {
            gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
            gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        }
        gradientLayer.locations = [0.0, 0.5, 1.0]

        layer.addSublayer(gradientLayer)
        
        updateTheme()
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer?.frame = bounds
    }
    
    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if isAnimating {
            startAnimating()
        } else {
            stopAnimating()
        }
    }

    public private(set) var isAnimating: Bool = false
    public func startAnimating() {
        isHidden = false
        isAnimating = true
        if gradientLayer.animation(forKey: "skeletonAnimation") != nil {
            return
        }
        let keyframeAnimation = CAKeyframeAnimation(keyPath: "locations")
        keyframeAnimation.values = [
            [-0.3, -0.2, -0.1, 0.0],
            [1.0, 1.1, 1.2, 1.3],
            [1.0, 1.1, 1.2, 1.3]
        ]
        keyframeAnimation.keyTimes = [0.0, 0.5, 1.0]
        keyframeAnimation.duration = 2
        keyframeAnimation.repeatCount = .infinity

        gradientLayer.add(keyframeAnimation, forKey: "skeletonAnimation")
    }
    
    public func stopAnimating() {
        isAnimating = false
        isHidden = true
        gradientLayer.removeAnimation(forKey: "skeletonAnimation")
    }
    
    private func updateTheme() {
        gradientLayer.colors = [colors[0].cgColor, colors[1].cgColor, colors[1].cgColor, colors[0].cgColor]
    }
    
    public func applyMask(with views: [UIView]) {
        guard let superview else {
            return
        }
        self.mask = createCombinedMask(from: views, in: superview)
    }
    
    private func createCombinedMask(from views: [UIView], in parentView: UIView) -> UIView {
        let maskView = UIView(frame: parentView.bounds)
        maskView.backgroundColor = .clear
        
        for view in views {
            let convertedFrame = parentView.convert(view.frame, from: view.superview)
            let cornerRadius = view.layer.cornerRadius
            let maskedCorners = view.layer.maskedCorners
            
            let maskLayer = CALayer()
            maskLayer.frame = convertedFrame
            maskLayer.cornerRadius = cornerRadius
            maskLayer.maskedCorners = maskedCorners
            maskLayer.backgroundColor = UIColor.white.cgColor
            maskView.layer.addSublayer(maskLayer)
        }
        return maskView
    }
}

public enum SkeletonPlaceholderSurface {
    case light
    case dark
    case colored

    var fillColor: Color {
        switch self {
        case .colored: .white.opacity(0.3)
        case .light: .air.groupedBackground.opacity(0.5)
        case .dark: .air.groupedItem.opacity(0.8)
        }
    }
}

private struct SkeletonShimmerTarget: Equatable {
    var frame: CGRect
    var cornerRadius: CGFloat
    var style: RoundedCornerStyle
    var surface: SkeletonPlaceholderSurface?

    init(
        frame: CGRect,
        cornerRadius: CGFloat,
        style: RoundedCornerStyle = .continuous,
        surface: SkeletonPlaceholderSurface? = nil
    ) {
        self.frame = frame
        self.cornerRadius = cornerRadius
        self.style = style
        self.surface = surface
    }
}

private struct SkeletonShimmerTargetPreferenceKey: PreferenceKey {
    static var defaultValue: [SkeletonShimmerTarget] { [] }

    static func reduce(value: inout [SkeletonShimmerTarget], nextValue: () -> [SkeletonShimmerTarget]) {
        value.append(contentsOf: nextValue())
    }
}

private let coordinameSpaceName = "SkeletonShimmerCoordinateSpace"

private enum SkeletonActiveKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var skeletonActive: Bool {
        get { self[SkeletonActiveKey.self] }
        set { self[SkeletonActiveKey.self] = newValue }
    }
}

private struct SkeletonShimmerTargetModifier: ViewModifier {
    let cornerRadius: CGFloat
    let style: RoundedCornerStyle
    let barInset: EdgeInsets
    let surface: SkeletonPlaceholderSurface?

    @Environment(\.skeletonActive) private var skeletonActive

    func body(content: Content) -> some View {
        content
            .accessibilityHidden(skeletonActive)
            .background {
            if skeletonActive {
                GeometryReader { geometry in
                    Color.clear
                        .preference(
                            key: SkeletonShimmerTargetPreferenceKey.self,
                            value: [
                                SkeletonShimmerTarget(
                                    frame: geometry.frame(in: .named(coordinameSpaceName)).inset(by: barInset),
                                    cornerRadius: cornerRadius,
                                    style: style,
                                    surface: surface
                                ),
                            ]
                        )
                }
            }
        }
    }
}

private extension CGRect {
    func inset(by insets: EdgeInsets) -> CGRect {
        inset(by: UIEdgeInsets(
            top: insets.top,
            left: insets.leading,
            bottom: insets.bottom,
            right: insets.trailing
        ))
    }
}

private extension [SkeletonShimmerTarget] {
    var unionRect: CGRect {
        reduce(into: self[0].frame) { $0 = $0.union($1.frame) }
    }
}

private struct SkeletonPlaceholderModifier: ViewModifier {
    let surface: SkeletonPlaceholderSurface
    let cornerRadius: CGFloat
    let cornerStyle: RoundedCornerStyle
    let barInset: EdgeInsets

    @Environment(\.skeletonActive) private var skeletonActive

    func body(content: Content) -> some View {
        content
            .opacity(skeletonActive ? 0 : 1)
            .modifier(SkeletonShimmerTargetModifier(
                cornerRadius: cornerRadius,
                style: cornerStyle,
                barInset: barInset,
                surface: surface
            ))
            .animation(nil, value: skeletonActive)
    }
}

private struct SkeletonShimmerContainerModifier: ViewModifier {
    let isActive: Bool
    let shimmerReferenceHeight: CGFloat

    @State private var targets: [SkeletonShimmerTarget] = []

    func body(content: Content) -> some View {
        content
            .environment(\.skeletonActive, isActive)
            .coordinateSpace(name: coordinameSpaceName)
            .onPreferenceChange(SkeletonShimmerTargetPreferenceKey.self) { targets = $0 }
            .overlay {
                if isActive, !targets.isEmpty {
                    ZStack {
                        SkeletonPlaceholderBarsOverlay(targets: targets)
                        TimelineView(.animation) { timeline in
                            SkeletonShimmerOverlay(
                                sweep: Self.sweep(at: timeline.date),
                                targets: targets,
                                referenceHeight: shimmerReferenceHeight
                            )
                        }
                    }
                    .clipped()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
    }
    
    private static func sweep(at date: Date) -> CGFloat {
        let duration: TimeInterval = 2
        let elapsed = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: duration)
        let progress = elapsed / duration
        if progress <= 0.5 {
            return CGFloat(progress / 0.5)
        }
        return 1
    }
}

private struct SkeletonPlaceholderBarsOverlay: View {
    let targets: [SkeletonShimmerTarget]

    var body: some View {
        Canvas { context, _ in
            for target in targets {
                guard let surface = target.surface else { continue }
                let rect = target.frame
                guard rect.width > 0, rect.height > 0 else { continue }
                let path = Path(roundedRect: rect, cornerRadius: target.cornerRadius, style: target.style)
                context.fill(path, with: .color(surface.fillColor))
            }
        }
    }
}

private struct SkeletonShimmerOverlay: View {
    let sweep: CGFloat
    let targets: [SkeletonShimmerTarget]
    let referenceHeight: CGFloat

    private static let locationStarts: [CGFloat] = [-0.3, -0.2, -0.1, 0.0]
    private static let sweepSpan: CGFloat = 1.3
    private static let highlightOpacity: CGFloat = 0.3

    var body: some View {
        GeometryReader { geometry in
            let containerWidth = geometry.size.width

            LinearGradient(
                gradient: Gradient(stops: gradientStops),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: containerWidth, height: referenceHeight)
            .mask {
                Canvas { context, _ in
                    for target in targets {
                        let rect = target.frame
                        guard rect.width > 0, rect.height > 0 else { continue }
                        let path = Path(roundedRect: rect, cornerRadius: target.cornerRadius, style: target.style)
                        context.fill(path, with: .color(.white))
                    }
                }
                .frame(width: containerWidth, height: referenceHeight)
            }
        }
    }

    private var gradientStops: [Gradient.Stop] {
        let baseColor: Color = .white
        let colors: [Color] = [
            .clear,
            baseColor.opacity(Self.highlightOpacity),
            baseColor.opacity(Self.highlightOpacity),
            .clear,
        ]
        return zip(Self.locationStarts, colors).map { start, color in
            .init(color: color, location: start + sweep * Self.sweepSpan)
        }
    }
}

extension View {
    public func skeletonContainer(isActive: Bool = true, shimmerReferenceHeight: CGFloat = 800) -> some View {
        modifier(SkeletonShimmerContainerModifier(
            isActive: isActive,
            shimmerReferenceHeight: shimmerReferenceHeight
        ))
    }

    public func skeleton(cornerRadius: CGFloat = 0, style: RoundedCornerStyle = .continuous) -> some View {
        modifier(SkeletonShimmerTargetModifier(
            cornerRadius: cornerRadius,
            style: style,
            barInset: .init(),
            surface: nil
        ))
    }

    public func skeletonPlaceholder(
        surface: SkeletonPlaceholderSurface = .light,
        cornerRadius: CGFloat = 4,
        cornerStyle: RoundedCornerStyle = .continuous,
        barInset: EdgeInsets = .init()
    ) -> some View {
        modifier(SkeletonPlaceholderModifier(
            surface: surface,
            cornerRadius: cornerRadius,
            cornerStyle: cornerStyle,
            barInset: barInset
        ))
    }
}

#if DEBUG
#Preview {
    InsetList(topPadding: 16, spacing: 24) {
        InsetSection {
            InsetCell(horizontalPadding: 12, verticalPadding: 10) {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.air.groupedBackground)
                        .frame(width: 40, height: 40)
                        .skeletonPlaceholder(cornerRadius: 20)

                    VStack(alignment: .leading, spacing: 0) {
                        Text("Activity title")
                            .font(.system(size: 16, weight: .medium))
                            .frame(minHeight: 22)
                            .skeletonPlaceholder(barInset: EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                        Text("Amount · time")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .frame(minHeight: 20)
                            .skeletonPlaceholder(barInset: EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                    }
                }
            }
        } header: {
            Text("Recent Activity")
        }

        InsetSection {
            InsetCell(horizontalPadding: 12, verticalPadding: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Main Wallet")
                        .font(.system(size: 16, weight: .medium))
                        .skeletonPlaceholder()
                    Text("Main Wallet subtitle subtitle subtitle")
                        .font(.system(size: 14))
                        .skeletonPlaceholder()
                }
            }
        } header: {
            Text("Selected Wallet")
                .skeletonPlaceholder(surface: .dark, cornerRadius: 8)
        }
        
        Rectangle()
            .frame(maxWidth: .infinity, minHeight: 400, maxHeight: 400)
            .skeletonPlaceholder(surface: .dark, cornerRadius: 8)
    }
    .background(Color.air.groupedBackground)
    .skeletonContainer()
}
#endif
