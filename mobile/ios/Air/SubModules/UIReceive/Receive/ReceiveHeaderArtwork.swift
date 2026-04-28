import SwiftUI
import UIComponents
import WalletCore

struct ReceiveHeaderBackgroundView: View {
    var chain: ApiChain

    var body: some View {
        let palette = chain.receiveHeaderPalette

        GeometryReader { geometry in
            let scale = max(1, geometry.size.width / Self.referenceSize.width)
            let contentWidth = Self.referenceSize.width * scale
            let xOffset = (geometry.size.width - contentWidth) / 2

            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    ForEach(Self.polygons.indices, id: \.self) { index in
                        let polygon = Self.polygons[index]

                        ReceiveHeaderPolygonShape(points: polygon.points, sourceSize: polygon.frame.size)
                            .fill(palette.colors[polygon.colorIndex])
                            .frame(
                                width: polygon.frame.width * scale,
                                height: polygon.frame.height * scale
                            )
                            .position(
                                x: polygon.frame.midX * scale,
                                y: polygon.frame.midY * scale
                            )
                    }
                }
                .frame(width: contentWidth, height: Self.referenceSize.height * scale, alignment: .topLeading)
                .blur(radius: 70 * scale)
                .offset(x: xOffset)
            }
            .frame(width: geometry.size.width, height: Self.referenceSize.height, alignment: .topLeading)
            .clipped()
        }
        .frame(height: Self.referenceSize.height)
    }
}

struct ReceiveHeaderOrnamentView: View {
    var chain: ApiChain
    var opacity: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Self.items) { item in
                ChainIcon(chain, font: .system(size: item.size), color: .black)
                    .frame(width: item.size, height: item.size)
                    .blendMode(.softLight)
                    .opacity(item.opacity * opacity)
                    .position(
                        x: item.x + item.size / 2,
                        y: item.y + item.size / 2
                    )
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .allowsHitTesting(false)
    }
}

private struct ReceiveHeaderPalette {
    let colors: [Color]

    init(_ colors: [Color]) {
        self.colors = colors
    }
}

private func figmaColor(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> Color {
    Color(cgColor: CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
}

private struct ReceiveHeaderPolygonData {
    let frame: CGRect
    let colorIndex: Int
    let points: [CGPoint]
}

private struct ReceiveHeaderPolygonShape: Shape {
    let points: [CGPoint]
    let sourceSize: CGSize

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }

        let xScale = rect.width / sourceSize.width
        let yScale = rect.height / sourceSize.height

        func scaled(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: rect.minX + point.x * xScale,
                y: rect.minY + point.y * yScale
            )
        }

        path.move(to: scaled(first))
        for point in points.dropFirst() {
            path.addLine(to: scaled(point))
        }
        path.closeSubpath()

        return path
    }
}

private struct ReceiveHeaderOrnamentItem: Identifiable {
    let id: Int
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let opacity: CGFloat
}

private extension ReceiveHeaderBackgroundView {
    static let referenceSize = CGSize(width: 402, height: 360)

    static let polygons = [
        ReceiveHeaderPolygonData(
            frame: CGRect(x: 0, y: -4.0099, width: 275.4613, height: 229.0099),
            colorIndex: 0,
            points: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 275.4613, y: 0),
                CGPoint(x: 223.4610, y: 180.6393),
                CGPoint(x: 0, y: 229.0099),
            ]
        ),
        ReceiveHeaderPolygonData(
            frame: CGRect(x: 127.4523, y: -7.5743, width: 274.5478, height: 216.0891),
            colorIndex: 1,
            points: [
                CGPoint(x: 28.0279, y: 0),
                CGPoint(x: 274.5478, y: 0),
                CGPoint(x: 274.5478, y: 168.1811),
                CGPoint(x: 75.5800, y: 216.0891),
                CGPoint(x: 0, y: 183.6226),
            ]
        ),
        ReceiveHeaderPolygonData(
            frame: CGRect(x: 126.5386, y: 157.7227, width: 275.4613, height: 202.2773),
            colorIndex: 2,
            points: [
                CGPoint(x: 52.0004, y: 48.3706),
                CGPoint(x: 275.4613, y: 0),
                CGPoint(x: 275.4613, y: 202.2773),
                CGPoint(x: 0, y: 202.2773),
            ]
        ),
        ReceiveHeaderPolygonData(
            frame: CGRect(x: 0, y: 175.5446, width: 292.8205, height: 184.9010),
            colorIndex: 3,
            points: [
                CGPoint(x: 0, y: 47.9080),
                CGPoint(x: 198.9678, y: 0),
                CGPoint(x: 292.8205, y: 32.4666),
                CGPoint(x: 246.5198, y: 184.9010),
                CGPoint(x: 0, y: 184.9010),
            ]
        ),
    ]
}

private extension ReceiveHeaderOrnamentView {
    static let size = CGSize(width: 356, height: 160)

    static let items = [
        ReceiveHeaderOrnamentItem(id: 0, x: 32, y: 68, size: 24, opacity: 0.25),
        ReceiveHeaderOrnamentItem(id: 1, x: 36, y: 108, size: 20, opacity: 0.20),
        ReceiveHeaderOrnamentItem(id: 2, x: 36, y: 32, size: 20, opacity: 0.20),
        ReceiveHeaderOrnamentItem(id: 3, x: 0, y: 70, size: 20, opacity: 0.20),
        ReceiveHeaderOrnamentItem(id: 4, x: 40, y: 0, size: 16, opacity: 0.15),
        ReceiveHeaderOrnamentItem(id: 5, x: 40, y: 144, size: 16, opacity: 0.15),
        ReceiveHeaderOrnamentItem(id: 6, x: 300, y: 68, size: 24, opacity: 0.25),
        ReceiveHeaderOrnamentItem(id: 7, x: 300, y: 108, size: 20, opacity: 0.20),
        ReceiveHeaderOrnamentItem(id: 8, x: 300, y: 32, size: 20, opacity: 0.20),
        ReceiveHeaderOrnamentItem(id: 9, x: 300, y: 0, size: 16, opacity: 0.15),
        ReceiveHeaderOrnamentItem(id: 10, x: 300, y: 144, size: 16, opacity: 0.15),
        ReceiveHeaderOrnamentItem(id: 11, x: 4, y: 104, size: 16, opacity: 0.15),
        ReceiveHeaderOrnamentItem(id: 12, x: 8, y: 134, size: 12, opacity: 0.10),
        ReceiveHeaderOrnamentItem(id: 13, x: 8, y: 14, size: 12, opacity: 0.10),
        ReceiveHeaderOrnamentItem(id: 14, x: 4, y: 40, size: 16, opacity: 0.15),
        ReceiveHeaderOrnamentItem(id: 15, x: 336, y: 70, size: 20, opacity: 0.20),
        ReceiveHeaderOrnamentItem(id: 16, x: 336, y: 104, size: 16, opacity: 0.15),
        ReceiveHeaderOrnamentItem(id: 17, x: 336, y: 134, size: 12, opacity: 0.10),
        ReceiveHeaderOrnamentItem(id: 18, x: 336, y: 14, size: 12, opacity: 0.10),
        ReceiveHeaderOrnamentItem(id: 19, x: 336, y: 40, size: 16, opacity: 0.15),
    ]
}

private extension ApiChain {
    var receiveHeaderPalette: ReceiveHeaderPalette {
        switch self {
        case .ton:
            ReceiveHeaderPalette([
                figmaColor(0.07450980693101883, 0.9215686321258545, 0.8666666746139526),
                figmaColor(0, 0.6000000238418579, 0.9215686321258545),
                figmaColor(0.07450980693101883, 0.2705882489681244, 0.9215686321258545),
                figmaColor(0, 0.6000000238418579, 0.9215686321258545),
            ])
        case .tron:
            ReceiveHeaderPalette([
                figmaColor(0.9634267091751099, 0.4956822991371155, 0.2974329888820648),
                figmaColor(0.9176470637321472, 0.07450980693101883, 0.1725490242242813),
                figmaColor(1, 0.46982237696647644, 0.7084023356437683),
                figmaColor(0.9176470637321472, 0.07450980693101883, 0.1725490242242813),
            ])
        case .solana:
            ReceiveHeaderPalette([
                figmaColor(0.1568627506494522, 0.8784313797950745, 0.7254902124404907),
                figmaColor(0.6000000238418579, 0.2705882489681244, 1),
                figmaColor(0.09803921729326248, 0.9843137264251709, 0.6078431606292725),
                figmaColor(0.6000000238418579, 0.2705882489681244, 1),
            ])
        case .ethereum:
            ReceiveHeaderPalette([
                figmaColor(0.6369283199310303, 0.7070561647415161, 0.9374760985374451),
                figmaColor(0.2666666805744171, 0.29019609093666077, 0.47058823704719543),
                figmaColor(0.6401218175888062, 0.5451434254646301, 0.7486685514450073),
                figmaColor(0.2666666805744171, 0.29019609093666077, 0.47058823704719543),
            ])
        case .base:
            ReceiveHeaderPalette([
                figmaColor(0.5384552478790283, 0.6307641863822937, 1),
                figmaColor(0, 0, 1),
                figmaColor(0.28150999546051025, 0.6407549977302551, 1),
                figmaColor(0, 0, 1),
            ])
        case .bnb:
            ReceiveHeaderPalette([
                figmaColor(1, 0.9058823585510254, 0),
                figmaColor(0.26033586263656616, 0.3053140938282013, 0.5302051901817322),
                figmaColor(1, 0.6980392336845398, 0),
                figmaColor(0.26033586263656616, 0.3053140938282013, 0.5302051901817322),
            ])
//        case .polygon:
//            ReceiveHeaderPalette([
//                figmaColor(0.9584313631057739, 0.7921568751335144, 0.9803921580314636),
//                figmaColor(0.43921568989753723, 0, 0.9333333373069763),
//                figmaColor(0.8117647171020508, 0.6705882549285889, 0.9725490212440491),
//                figmaColor(0.43921568989753723, 0, 0.9333333373069763),
//            ])
        case .arbitrum:
            ReceiveHeaderPalette([
                figmaColor(0.5647059082984924, 0.8078431487083435, 0.9450980424880981),
                figmaColor(0.10588235408067703, 0.19607843458652496, 0.2862745225429535),
                figmaColor(0, 0.6784313917160034, 1),
                figmaColor(0.10588235408067703, 0.19607843458652496, 0.2862745225429535),
            ])
//        case .monad:
//            ReceiveHeaderPalette([
//                figmaColor(0.8163028955459595, 0.7833641171455383, 1),
//                figmaColor(0.3612353503704071, 0.24669823050498962, 1),
//                figmaColor(0.6652376055717468, 0.7042931914329529, 1),
//                figmaColor(0.3612353503704071, 0.24669823050498962, 1),
//            ])
//        case .avalanche:
//            ReceiveHeaderPalette([
//                figmaColor(0.45836639404296875, 0.7201559543609619, 1),
//                figmaColor(1, 0.2235294133424759, 0.29019609093666077),
//                figmaColor(0.4280964732170105, 0.5901358127593994, 1),
//                figmaColor(1, 0.2235294133424759, 0.29019609093666077),
//            ])
        case .hyperliquid:
            ReceiveHeaderPalette([
                figmaColor(0.7275996804237366, 0.9402077198028564, 0.9165846109390259),
                figmaColor(0, 0.1568627506494522, 0.13725490868091583),
                figmaColor(0.43529412150382996, 1, 0.8901960849761963),
                figmaColor(0, 0.1568627506494522, 0.13725490868091583),
            ])
        case .other:
            ReceiveHeaderPalette([
                figmaColor(0.07450980693101883, 0.9215686321258545, 0.8666666746139526),
                figmaColor(0, 0.6000000238418579, 0.9215686321258545),
                figmaColor(0.07450980693101883, 0.2705882489681244, 0.9215686321258545),
                figmaColor(0, 0.6000000238418579, 0.9215686321258545),
            ])
        }
    }
}
