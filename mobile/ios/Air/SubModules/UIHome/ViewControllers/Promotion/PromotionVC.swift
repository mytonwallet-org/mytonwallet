import Foundation
import Kingfisher
import SwiftUI
import UIComponents
import UIKit
import WalletCore
import WalletContext

public final class PromotionVC: WViewController {
    private let promotion: ApiPromotion
    private var hostingController: UIHostingController<PromotionView>?
    private var contentHeight: CGFloat = 0

    private var currentSheetPresentationController: UISheetPresentationController? {
        navigationController?.sheetPresentationController ?? sheetPresentationController
    }

    public init(promotion: ApiPromotion) {
        self.promotion = promotion
        super.init(nibName: nil, bundle: nil)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        configureNavigationItemWithTransparentBackground()
        addCloseNavigationItemIfNeeded()
        let hostingController = addHostingController(
            PromotionView(
                promotion: promotion,
                onHeightChange: { [weak self] height in
                    self?.onHeightChange(height)
                },
                onAction: { [weak self] actionURL in
                    self?.dismiss(animated: true) {
                        UIApplication.shared.open(actionURL)
                    }
                }
            ),
            constraints: .fill
        )
        self.hostingController = hostingController
        currentSheetPresentationController?.prefersGrabberVisible = false
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateSheetHeight(animated: false)
    }

    private func onHeightChange(_ height: CGFloat) {
        guard height > 0 else { return }
        guard abs(contentHeight - height) > 0.5 else { return }
        contentHeight = height
        updateSheetHeight(animated: true)
    }

    private func updateSheetHeight(animated: Bool) {
        guard contentHeight > 0, let sheet = currentSheetPresentationController else { return }
        let contentHeight = self.contentHeight

        let apply = {
            sheet.detents = [
                .custom(identifier: .content) { context in
                    min(contentHeight, context.maximumDetentValue)
                }
            ]
            sheet.selectedDetentIdentifier = .content
        }

        if animated, view.window != nil {
            sheet.animateChanges {
                apply()
            }
        } else {
            apply()
        }
    }
}

private struct PromotionView: View {
    let promotion: ApiPromotion
    let onHeightChange: (CGFloat) -> Void
    let onAction: (URL) -> Void
    @State private var surfaceHeight: CGFloat = 0
    @State private var actionButtonHeight: CGFloat = 0

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                if let heroURL {
                    heroImage(url: heroURL)
                }

                VStack(spacing: 0) {
                    if let title = modal?.title.nilIfEmpty {
                        Text(title)
                            .font(.system(size: 20, weight: .heavy))
                            .foregroundStyle(titleColor)
                            .multilineTextAlignment(.center)
                    }

                    if let description = modal?.description.nilIfEmpty {
                        descriptionText(description)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(descriptionColor)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .padding(.top, 32)
                    }

                    if let availability = modal?.availabilityIndicator?.nilIfEmpty {
                        Text(availability)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.16), in: .capsule)
                            .padding(.top, 32)
                    }

                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { height in
                surfaceHeight = height
                reportHeight()
            }
        }
        .ignoresSafeArea(edges: .top)
        .scrollDisabled(true)
        .backportScrollEdgeEffectHidden()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let action = modal?.actionButton,
               let url = URL(string: action.url),
               !action.title.isEmpty
            {
                Button(action.title) {
                    onAction(url)
                }
                .buttonStyle(.airPrimary)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { height in
                    actionButtonHeight = height
                    reportHeight()
                }
            } else {
                Color.clear
                    .frame(height: 0)
                    .onAppear {
                        actionButtonHeight = 0
                        reportHeight()
                    }
            }
        }
        .background {
            ZStack {
                backgroundFallbackView

                if let backgroundURL {
                    backgroundImage(url: backgroundURL)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
        }
    }

    private func reportHeight() {
        onHeightChange(surfaceHeight + actionButtonHeight)
    }

    @ViewBuilder
    private func heroImage(url: URL) -> some View {
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay(alignment: .top) {
                GeometryReader { geometry in
                    KFImage(url)
                        .placeholder {
                            Color.clear
                        }
                        .fade(duration: 0.18)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func backgroundImage(url: URL) -> some View {
        GeometryReader { geometry in
            KFImage(url)
                .placeholder {
                    Color.clear
                }
                .fade(duration: 0.5)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
        }
    }

    private var modal: ApiPromotion.Modal? {
        promotion.modal
    }

    private var backgroundURL: URL? {
        modal?.backgroundImageUrl.nilIfEmpty.flatMap(URL.init(string:))
    }

    private var heroURL: URL? {
        modal?.heroImageUrl?.nilIfEmpty.flatMap(URL.init(string:))
    }

    @ViewBuilder
    private var backgroundFallbackView: some View {
        if let backgroundFallback = modal?.backgroundFallback.nilIfEmpty {
            if let gradient = CSSLinearGradient(backgroundFallback) {
                LinearGradient(
                    stops: gradient.stops,
                    startPoint: gradient.startPoint,
                    endPoint: gradient.endPoint
                )
            } else if let color = UIColor(cssColor: backgroundFallback) {
                Color(color)
            } else {
                Color.air.sheetBackground
            }
        } else {
            Color.air.sheetBackground
        }
    }

    private var titleColor: Color {
        if let titleColor = modal?.titleColor?.nilIfEmpty {
            if let color = UIColor(cssColor: titleColor) {
                return Color(color)
            }
        }
        return .white
    }

    private var descriptionColor: Color {
        if let descriptionColor = modal?.descriptionColor?.nilIfEmpty {
            if let color = UIColor(cssColor: descriptionColor) {
                return Color(color)
            }
        }
        return .white.opacity(0.75)
    }

    @ViewBuilder
    private func descriptionText(_ description: String) -> some View {
        if let markdown = try? AttributedString(
            markdown: description,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(markdown)
        } else {
            Text(description)
        }
    }
}

private extension UISheetPresentationController.Detent.Identifier {
    static let content = UISheetPresentationController.Detent.Identifier("content")
}

private struct CSSLinearGradient {
    let stops: [Gradient.Stop]
    let startPoint: UnitPoint
    let endPoint: UnitPoint

    init?(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("linear-gradient("), trimmed.hasSuffix(")") else { return nil }
        let body = String(trimmed.dropFirst("linear-gradient(".count).dropLast())
        let parts = splitTopLevelCommaSeparated(body)
        guard parts.count >= 2 else { return nil }

        let angle = Self.parseAngle(parts[0]) ?? 180
        let stopParts = Self.parseAngle(parts[0]) == nil ? parts : Array(parts.dropFirst())
        let parsedStops = stopParts.enumerated().compactMap { index, part -> Gradient.Stop? in
            guard let color = Self.parseStopColor(from: part) else { return nil }
            let location = Self.parseStopLocation(from: part) ?? (
                stopParts.count == 1 ? 0 : Double(index) / Double(stopParts.count - 1)
            )
            return Gradient.Stop(color: Color(color), location: location)
        }
        guard parsedStops.count >= 2 else { return nil }

        self.stops = parsedStops
        let vector = Self.vector(for: angle)
        self.startPoint = UnitPoint(x: 0.5 - vector.x / 2, y: 0.5 - vector.y / 2)
        self.endPoint = UnitPoint(x: 0.5 + vector.x / 2, y: 0.5 + vector.y / 2)
    }

    private static func parseAngle(_ rawValue: String) -> Double? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix("deg") else { return nil }
        return Double(trimmed.dropLast(3).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func parseStopColor(from rawValue: String) -> UIColor? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = trimmed.range(
            of: #"^(.*)\s+([0-9]+(?:\.[0-9]+)?)%$"#,
            options: .regularExpression
        ) {
            let colorString = String(trimmed[match]).replacingOccurrences(
                of: #"\s+([0-9]+(?:\.[0-9]+)?)%$"#,
                with: "",
                options: .regularExpression
            )
            return UIColor(cssColor: colorString)
        }
        return UIColor(cssColor: trimmed)
    }

    private static func parseStopLocation(from rawValue: String) -> Double? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = trimmed.range(
            of: #"([0-9]+(?:\.[0-9]+)?)%$"#,
            options: .regularExpression
        ) else { return nil }
        guard let value = Double(trimmed[match].dropLast()) else { return nil }
        return value / 100
    }

    private static func vector(for angle: Double) -> CGPoint {
        let radians = angle * .pi / 180
        return CGPoint(x: sin(radians), y: -cos(radians))
    }
}

private extension UIColor {
    convenience init?(cssColor: String) {
        let trimmed = cssColor.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("#") {
            self.init(hex: trimmed)
            return
        }

        if let rgba = Self.parseRGBA(trimmed) {
            self.init(
                red: rgba.red / 255,
                green: rgba.green / 255,
                blue: rgba.blue / 255,
                alpha: rgba.alpha
            )
            return
        }

        return nil
    }

    private static func parseRGBA(_ rawValue: String) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)? {
        let normalized = rawValue.lowercased()
        let prefix: String
        switch true {
        case normalized.hasPrefix("rgba("):
            prefix = "rgba("
        case normalized.hasPrefix("rgb("):
            prefix = "rgb("
        default:
            return nil
        }
        guard normalized.hasSuffix(")") else { return nil }
        let body = String(normalized.dropFirst(prefix.count).dropLast())
        let parts = splitTopLevelCommaSeparated(body).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard parts.count == (prefix == "rgba(" ? 4 : 3),
              let red = Double(parts[0]),
              let green = Double(parts[1]),
              let blue = Double(parts[2])
        else {
            return nil
        }
        let alpha = parts.count == 4 ? (Double(parts[3]) ?? 1) : 1
        return (
            red: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: CGFloat(alpha)
        )
    }
}

private func splitTopLevelCommaSeparated(_ rawValue: String) -> [String] {
    var result: [String] = []
    var current = ""
    var depth = 0

    for character in rawValue {
        switch character {
        case "(":
            depth += 1
            current.append(character)
        case ")":
            depth -= 1
            current.append(character)
        case "," where depth == 0:
            result.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
            current = ""
        default:
            current.append(character)
        }
    }

    if !current.isEmpty {
        result.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    return result
}

#if DEBUG
@available(iOS 26, *)
#Preview("Promotion Modal") {
    PromotionView(
        promotion: DebugPromotionPreset.airPromotion,
        onHeightChange: { _ in },
        onAction: { _ in }
    )
}
#endif
