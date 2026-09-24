import SwiftUI

@MainActor
public final class CardBackgroundLibrary {
    struct Stop: Decodable {
        let location: Double
        let color: String
    }

    struct Background: Decodable {
        let fill: String?
        let transform: [Double]?
        let stops: [Stop]?
    }

    struct Spot: Decodable {
        let commands: [[Double]]
        let filter: [Double]
    }

    struct Data: Decodable {
        let revision: String
        let attributes: [CardBackgroundAttribute]
        let backgrounds: [String: Background]
        let colors: [String: [String: String]]
        let textures: [String: [[[Double]]]]
        let spots: [String: [String: Spot]]
        let shines: [String: [Double]]
    }

    public static let shared: Result<CardBackgroundLibrary, Error> = Result { try CardBackgroundLibrary() }

    public var attributes: [CardBackgroundAttribute] { data.attributes }

    let data: Data
    let textures: [String: [Path]]
    let textureBounds: [String: CGRect]
    let spots: [String: [String: Path]]

    private init() throws {
        guard let url = Bundle.module.url(forResource: "CardBackgroundRecipes", withExtension: "json", subdirectory: "CardBackgrounds")
            ?? Bundle.module.url(forResource: "CardBackgroundRecipes", withExtension: "json") else {
            throw CardBackgroundSeed.InvalidSeed(message: "Card background recipes are missing from the resource bundle.")
        }
        data = try JSONDecoder().decode(Data.self, from: Foundation.Data(contentsOf: url))
        textures = data.textures.mapValues { $0.map(Self.path) }
        textureBounds = textures.mapValues { $0.reduce(CGRect.null) { $0.union($1.cgPath.boundingBoxOfPath) } }
        spots = data.spots.mapValues { $0.mapValues { Self.path($0.commands) } }
    }

    private static func path(_ commands: [[Double]]) -> Path {
        var path = Path()
        for c in commands {
            switch c[0] {
            case 0: path.move(to: CGPoint(x: c[1], y: c[2]))
            case 1: path.addLine(to: CGPoint(x: c[1], y: c[2]))
            case 2: path.addCurve(to: CGPoint(x: c[5], y: c[6]), control1: CGPoint(x: c[1], y: c[2]), control2: CGPoint(x: c[3], y: c[4]))
            case 3: path.addQuadCurve(to: CGPoint(x: c[3], y: c[4]), control: CGPoint(x: c[1], y: c[2]))
            case 4: path.closeSubpath()
            default: preconditionFailure("Unsupported bundled vector command")
            }
        }
        return path
    }
}

/// Native vector drawing in the generator's 400 × 232 coordinate system.
/// Geometry is decoded once; animation only changes the Metal sampling coordinates.
struct CardBackgroundArtwork: View, Equatable {
    enum Layer: Equatable { case complete, base, spot(Int) }
    let seed: CardBackgroundSeed
    let library: CardBackgroundLibrary
    var contrastOpacity: Double = 0
    var showContrast = false
    var layer: Layer = .complete
    var padding: CGFloat = 0

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.seed == rhs.seed && lhs.contrastOpacity == rhs.contrastOpacity && lhs.showContrast == rhs.showContrast
            && lhs.layer == rhs.layer && lhs.padding == rhs.padding
    }

    var body: some View {
        Canvas(opaque: layer == .complete || layer == .base, colorMode: .nonLinear) { context, size in
            var context = context
            context.scaleBy(x: size.width / (400 + 2 * padding), y: size.height / (232 + 2 * padding))
            context.translateBy(x: padding, y: padding)
            if case .spot(let index) = layer {
                drawSpots(in: context, index: index)
            } else {
                drawBackground(in: context)
                drawTexture(in: context)
                if layer == .complete {
                    drawSpots(in: context)
                    if showContrast && seed.isStandard { drawContrast(in: context) }
                }
                if !seed.isStandard { drawPremiumHighlight(in: context) }
            }
        }
        .accessibilityHidden(true)
    }

    private let rect = CGRect(x: 0, y: 0, width: 400, height: 232)

    private func drawBackground(in context: GraphicsContext) {
        let type = seed["Card Type"]
        if seed.isStandard {
            let background = library.data.backgrounds[seed["Background"]]
            if let transform = background?.transform, let stops = background?.stops {
                Self.radial(in: context, path: Path(rect), transform: Self.transform(transform), gradient: Gradient(stops: stops.map {
                    .init(color: Self.color($0.color), location: $0.location)
                }))
            } else {
                // Glass is intentionally absent in backgrounds.yaml; SvgCard uses white.
                context.fill(Path(rect), with: .color(Self.color(background?.fill ?? "#FFFFFF")))
            }
        } else if type == "⚜️ Gold" {
            context.fill(Path(rect), with: .linearGradient(Gradient(colors: [Self.color("#C4842B"), Self.color("#FFDE5E")]), startPoint: .init(x: 220, y: 0), endPoint: .init(x: 220, y: 232)))
        } else {
            let fill = type == "🗝 Black" ? "#000000" : type == "💍 Platinum" ? "#393A3F" : "#C4C3C5"
            context.fill(Path(rect), with: .color(Self.color(fill)))
            if type == "🗝 Black" || type == "💍 Platinum" {
                let black = type == "🗝 Black"
                Self.blurred(in: context, path: Path(ellipseIn: CGRect(x: black ? -249 : -274, y: black ? 220 : 249, width: 559, height: 272)), shading: .color(Self.color(black ? "#484D68" : "#010627")), radius: 129.5)
            }
        }
    }

    private func drawTexture(in context: GraphicsContext) {
        let name = seed["Texture Type"]
        guard seed.hasTexture, let paths = library.textures[name], let bounds = library.textureBounds[name] else { return }
        let scale = (Double(seed["Texture Size"]) ?? 900) / 900
        let rotation = Self.number(seed["Texture Rotation"]) * -.pi / 180
        let shiftX = Self.number(seed["Texture Position X"]) / 100
        let shiftY = Self.number(seed["Texture Position Y"]) / 100
        let x = shiftX * (400 - bounds.width * scale) - bounds.minX * scale
        let y = shiftY * (232 - bounds.height * scale) - bounds.minY * scale
        var context = context
        context.translateBy(x: x + bounds.midX * scale, y: y + bounds.midY * scale)
        context.rotate(by: .radians(rotation))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -bounds.midX, y: -bounds.midY)
        if seed["Card Type"] == "⚜️ Gold" { context.opacity = 0.75 }
        let hex = seed.isStandard
            ? library.data.colors["Texture Color"]?[seed["Texture Color"]] ?? "#FFFFFF"
            : seed["Card Type"] == "💍 Platinum" ? "#000006" : "#FFFFFF"
        let colors = hex.components(separatedBy: "-").map(Self.color)
        // Apply Gold's opacity to the group, including places where paths overlap.
        context.drawLayer { layer in
            for path in paths {
                // SVG objectBoundingBox gradients are local to each path, not the group.
                let box = path.cgPath.boundingBoxOfPath
                let shading: GraphicsContext.Shading = colors.count == 1 ? .color(colors[0]) : .linearGradient(
                    Gradient(colors: colors), startPoint: CGPoint(x: box.midX, y: box.minY), endPoint: CGPoint(x: box.midX, y: box.maxY)
                )
                if name == "Desert" || name == "Moderate" {
                    layer.fill(path, with: shading)
                } else {
                    layer.stroke(path, with: shading, style: StrokeStyle(lineWidth: 0.5, miterLimit: 10))
                }
            }
        }
    }

    private func drawSpots(in context: GraphicsContext, index: Int? = nil) {
        guard seed.isStandard else { return }
        for (i, ordinal) in ["First", "Second", "Third"].enumerated() {
            if let index, i != index { continue }
            let key = "\(ordinal) Spot"
            let position = seed["\(key) Position"]
            guard let hex = library.data.colors["\(key) Color"]?[seed["\(key) Color"]],
                  let path = library.spots[key]?[position], let filter = library.data.spots[key]?[position]?.filter else { continue }
            let colors = hex.components(separatedBy: "-").map(Self.color)
            let shading: GraphicsContext.Shading = colors.count == 1 ? .color(colors[0]) : .linearGradient(
                Gradient(colors: colors), startPoint: CGPoint(x: 134.545, y: 219.305), endPoint: CGPoint(x: 425.876, y: 219.305)
            )
            var context = context
            context.clip(to: Path(CGRect(x: filter[0], y: filter[1], width: filter[2], height: filter[3])))
            Self.blurred(in: context, path: path, shading: shading, radius: 40)
        }
    }

    private func drawPremiumHighlight(in context: GraphicsContext) {
        let black = seed["Card Type"] == "🗝 Black"
        var context = context
        context.clip(to: Path(black ? CGRect(x: 116, y: -119, width: 372.769, height: 242) : CGRect(x: 111, y: -103, width: 306, height: 206)))
        Self.blurred(in: context, path: Path(ellipseIn: CGRect(x: black ? 220 : 194, y: black ? -15 : -11, width: 164.77, height: 34)), shading: .color(Self.color("#F8F8F8")), radius: black ? 52 : 45)
    }

    private func drawContrast(in context: GraphicsContext) {
        let color: Color = seed["Text"] == "Dark" ? .white : .black
        let gradient = Gradient(stops: [
            .init(color: color, location: 0), .init(color: color.opacity(0.8), location: 0.25),
            .init(color: color.opacity(0.5), location: 0.5), .init(color: color.opacity(0.2), location: 0.75),
            .init(color: color.opacity(0), location: 1),
        ])
        let transform = CGAffineTransform(a: 0, b: 158, c: -269.69, d: 0, tx: 200, ty: 116)
        var overlay = context
        overlay.opacity = contrastOpacity
        overlay.blendMode = .overlay
        Self.radial(in: overlay, path: Path(rect), transform: transform, gradient: gradient)
        var base = context
        base.opacity = 0.16
        Self.radial(in: base, path: Path(rect), transform: transform, gradient: gradient)
    }

    static func blurred(in context: GraphicsContext, path: Path, shading: GraphicsContext.Shading, radius: Double) {
        var context = context
        context.addFilter(.blur(radius: radius))
        context.drawLayer { $0.fill(path, with: shading) }
    }

    static func radial(in context: GraphicsContext, path: Path, transform: CGAffineTransform, gradient: Gradient) {
        var context = context
        context.concatenate(transform)
        context.fill(path.applying(transform.inverted()), with: .radialGradient(gradient, center: .zero, startRadius: 0, endRadius: 1))
    }

    static func transform(_ v: [Double]) -> CGAffineTransform {
        CGAffineTransform(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5])
    }

    static func number(_ text: String) -> Double {
        Double(text.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: "°", with: "")) ?? 0
    }

    static func color(_ hex: String) -> Color {
        let rgb = UInt32(hex.dropFirst(), radix: 16) ?? 0
        return Color(.sRGB, red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255, opacity: 1)
    }
}

public struct CardBackgroundShine: View {
    public init(seed: CardBackgroundSeed, library: CardBackgroundLibrary) {
        self.seed = seed
        self.library = library
    }
    let seed: CardBackgroundSeed
    let library: CardBackgroundLibrary

    public var body: some View {
        Canvas { context, size in
            var context = context
            context.scaleBy(x: size.width / 400, y: size.height / 232)
            let black = seed["Card Type"] == "🗝 Black"
            let width = black ? 3.0 : 2.0
            let border = Path(roundedRect: CGRect(x: width / 2, y: width / 2, width: 400 - width, height: 232 - width), cornerRadius: 28 - width / 2)
                .strokedPath(StrokeStyle(lineWidth: width))
            if seed["Shine"] == "Radioactive" && seed.isStandard {
                context.fill(border, with: .color(CardBackgroundArtwork.color("#97FF9B")))
            } else {
                var base = context
                if !seed.isStandard { base.opacity = black ? 1 : 0.4 }
                let colors: [Color]
                switch seed["Card Type"] {
                case "🗝 Black": colors = [.white.opacity(0.06), .white.opacity(0.12)]
                case "💍 Platinum": colors = [CardBackgroundArtwork.color("#77777F"), .white]
                case "⚜️ Gold": colors = [CardBackgroundArtwork.color("#4C3403"), CardBackgroundArtwork.color("#B07D1D")]
                case "🪙 Silver": colors = [CardBackgroundArtwork.color("#272727"), CardBackgroundArtwork.color("#989898")]
                default: colors = [CardBackgroundArtwork.color("#8C94B0").opacity(0.5), CardBackgroundArtwork.color("#BABCC2").opacity(0.85)]
                }
                let start = seed.isStandard ? CGPoint(x: 247.799, y: 22.2918) : black ? CGPoint(x: 247.583, y: 22.994) : CGPoint(x: 247.345, y: 23.796)
                let end = seed.isStandard ? CGPoint(x: 183.074, y: 44.6986) : black ? CGPoint(x: 183.192, y: 45.351) : CGPoint(x: 183.326, y: 46.105)
                base.fill(border, with: .linearGradient(Gradient(colors: colors), startPoint: start, endPoint: end))
                let transform = seed.isStandard
                    ? library.data.shines[seed["Shine"]] ?? [200, 0, 0, 66.9519, 0, 116.438]
                    : black ? [-95.9282, 115.565, -115.144, -96.2785, 295.928, 0.869] : [-95.4486, 114.568, -41.6302, -31.7413, 295.448, 1.861]
                CardBackgroundArtwork.radial(in: context, path: border, transform: CardBackgroundArtwork.transform(transform), gradient: Gradient(colors: [.white, .white.opacity(0)]))
            }
        }
        .accessibilityHidden(true)
    }
}
