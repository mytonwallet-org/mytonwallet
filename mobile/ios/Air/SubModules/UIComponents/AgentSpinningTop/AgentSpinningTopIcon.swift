import UIKit

/// The Agent's spinning top mark as a flat icon, for buttons and other places where the 3D top is too heavy
@MainActor
public enum AgentSpinningTopIcon {
    /// Design box of the mark, in points
    public static let designSize: CGFloat = 48

    /// The silhouette in the 48 × 48 design box: the 3D top's in its still pose, with the point where the 3D top's is
    /// and its rim tips rounded
    public static func makeSilhouette() -> UIBezierPath {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 20.9714, y: 42.9249))
        path.addCurve(to: CGPoint(x: 19.3497, y: 42.2609), controlPoint1: CGPoint(x: 20.3761, y: 42.9056), controlPoint2: CGPoint(x: 19.7459, y: 42.7284))
        path.addCurve(to: CGPoint(x: 15.4832, y: 33.1684), controlPoint1: CGPoint(x: 17.779, y: 40.4078), controlPoint2: CGPoint(x: 18.135, y: 35.8634))
        path.addCurve(to: CGPoint(x: 12.981, y: 31.1843), controlPoint1: CGPoint(x: 14.8554, y: 32.5304), controlPoint2: CGPoint(x: 13.7768, y: 31.5764))
        path.addCurve(to: CGPoint(x: 5.625, y: 26.7701), controlPoint1: CGPoint(x: 11.3855, y: 30.3981), controlPoint2: CGPoint(x: 5.6069, y: 29.1549))
        path.addCurve(to: CGPoint(x: 13.1737, y: 24.9361), controlPoint1: CGPoint(x: 5.6443, y: 24.2355), controlPoint2: CGPoint(x: 11.6534, y: 25.0133))
        path.addCurve(to: CGPoint(x: 15.2338, y: 24.5567), controlPoint1: CGPoint(x: 13.7302, y: 24.9079), controlPoint2: CGPoint(x: 14.6948, y: 24.7162))
        path.addCurve(to: CGPoint(x: 19.5599, y: 21.4935), controlPoint1: CGPoint(x: 16.6433, y: 24.1396), controlPoint2: CGPoint(x: 18.6172, y: 22.6204))
        path.addCurve(to: CGPoint(x: 23.9803, y: 11.3876), controlPoint1: CGPoint(x: 21.5859, y: 19.0714), controlPoint2: CGPoint(x: 23.1407, y: 14.4387))
        path.addCurve(to: CGPoint(x: 25.5745, y: 6.5622), controlPoint1: CGPoint(x: 24.3835, y: 9.9224), controlPoint2: CGPoint(x: 24.7871, y: 7.8424))
        path.addCurve(to: CGPoint(x: 27.3669, y: 5.3965), controlPoint1: CGPoint(x: 25.9811, y: 5.9011), controlPoint2: CGPoint(x: 26.5548, y: 5.3977))
        path.addCurve(to: CGPoint(x: 29.4812, y: 6.9585), controlPoint1: CGPoint(x: 28.4389, y: 5.3949), controlPoint2: CGPoint(x: 29.1754, y: 5.923))
        path.addCurve(to: CGPoint(x: 29.0774, y: 13.5837), controlPoint1: CGPoint(x: 29.9389, y: 8.5082), controlPoint2: CGPoint(x: 29.2416, y: 11.8675))
        path.addCurve(to: CGPoint(x: 29.2704, y: 22.6638), controlPoint1: CGPoint(x: 28.7979, y: 16.5054), controlPoint2: CGPoint(x: 28.6599, y: 19.7795))
        path.addCurve(to: CGPoint(x: 40.455, y: 33.1387), controlPoint1: CGPoint(x: 30.9983, y: 30.8265), controlPoint2: CGPoint(x: 40.4442, y: 29.5855))
        path.addCurve(to: CGPoint(x: 31.9053, y: 34.9061), controlPoint1: CGPoint(x: 40.4633, y: 35.8721), controlPoint2: CGPoint(x: 33.5044, y: 34.8566))
        path.addCurve(to: CGPoint(x: 30.0053, y: 35.3412), controlPoint1: CGPoint(x: 31.4909, y: 34.9189), controlPoint2: CGPoint(x: 30.4215, y: 35.2021))
        path.addCurve(to: CGPoint(x: 26.1497, y: 37.7069), controlPoint1: CGPoint(x: 28.5212, y: 35.8372), controlPoint2: CGPoint(x: 27.2322, y: 36.554))
        path.addCurve(to: CGPoint(x: 20.9714, y: 42.9249), controlPoint1: CGPoint(x: 24.9957, y: 38.9359), controlPoint2: CGPoint(x: 22.5676, y: 42.9767))
        path.close()
        return path
    }

    /// The mark filled with its blue-to-purple gradient
    public static func makeImage(size: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).image { context in
            let cgContext = context.cgContext
            let scale = size / designSize
            cgContext.scaleBy(x: scale, y: scale)
            let path = makeSilhouette()
            cgContext.addPath(path.cgPath)
            cgContext.clip()
            let colors = [
                UIColor(red: 0, green: 0x88 / 255.0, blue: 1, alpha: 0.3).cgColor,
                UIColor(red: 0, green: 0xBE / 255.0, blue: 1, alpha: 0.6).cgColor,
                UIColor(red: 0xB6 / 255.0, green: 0x56 / 255.0, blue: 1, alpha: 0.3).cgColor,
            ] as CFArray
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 0.476359, 1]
            ) else { return }
            cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 9.63672, y: 1.94238),
                end: CGPoint(x: 47.9633, y: 12.8032),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }
    }

    /// A template image of the mark on a `canvas` shared with other icons: its silhouette, rather than its design box,
    /// sits in the middle, `markHeight` tall
    public static func makeTemplateImage(canvas: CGSize, markHeight: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let path = makeSilhouette()
        let bounds = path.cgPath.boundingBoxOfPath
        let scale = markHeight / bounds.height
        return UIGraphicsImageRenderer(size: canvas, format: format).image { context in
            let cgContext = context.cgContext
            cgContext.translateBy(x: canvas.width / 2, y: canvas.height / 2)
            cgContext.scaleBy(x: scale, y: scale)
            cgContext.translateBy(x: -bounds.midX, y: -bounds.midY)
            UIColor.black.setFill()
            path.fill()
        }.withRenderingMode(.alwaysTemplate)
    }

    public static func makeTemplateImage(size: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).image { context in
            let scale = size / designSize
            context.cgContext.scaleBy(x: scale, y: scale)
            UIColor.black.setFill()
            makeSilhouette().fill()
        }.withRenderingMode(.alwaysTemplate)
    }
}
