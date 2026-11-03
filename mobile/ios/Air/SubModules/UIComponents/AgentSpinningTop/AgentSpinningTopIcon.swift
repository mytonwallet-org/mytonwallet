import UIKit

/// The Agent's spinning top mark as a flat icon, for buttons and other places where the 3D top is too heavy
@MainActor
public enum AgentSpinningTopIcon {
    /// Design box of the mark, in points
    public static let designSize: CGFloat = 48

    /// The silhouette in the 48 × 48 design box
    public static func makeSilhouette() -> UIBezierPath {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 27.9273, y: 5.83017))
        path.addCurve(to: CGPoint(x: 29.1794, y: 6.44973), controlPoint1: CGPoint(x: 28.4264, y: 5.93633), controlPoint2: CGPoint(x: 28.8487, y: 6.13815))
        path.addCurve(to: CGPoint(x: 29.8436, y: 7.59927), controlPoint1: CGPoint(x: 29.5101, y: 6.76148), controlPoint2: CGPoint(x: 29.7215, y: 7.15589))
        path.addCurve(to: CGPoint(x: 29.7647, y: 10.8073), controlPoint1: CGPoint(x: 30.0812, y: 8.46254), controlPoint2: CGPoint(x: 29.9938, y: 9.56759))
        path.addCurve(to: CGPoint(x: 28.6385, y: 20.5677), controlPoint1: CGPoint(x: 29.0665, y: 14.5722), controlPoint2: CGPoint(x: 28.6137, y: 17.8016))
        path.addCurve(to: CGPoint(x: 30.3414, y: 27.455), controlPoint1: CGPoint(x: 28.6634, y: 23.3287), controlPoint2: CGPoint(x: 29.1653, y: 25.5925))
        path.addLine(to: CGPoint(x: 30.6961, y: 27.9657))
        path.addCurve(to: CGPoint(x: 39.099, y: 32.3316), controlPoint1: CGPoint(x: 32.5716, y: 30.4252), controlPoint2: CGPoint(x: 35.8393, y: 31.4942))
        path.addLine(to: CGPoint(x: 39.542, y: 32.4737))
        path.addCurve(to: CGPoint(x: 40.57, y: 33.1235), controlPoint1: CGPoint(x: 39.9628, y: 32.6341), controlPoint2: CGPoint(x: 40.3147, y: 32.8538))
        path.addCurve(to: CGPoint(x: 40.9508, y: 34.4884), controlPoint1: CGPoint(x: 40.9164, y: 33.4895), controlPoint2: CGPoint(x: 41.1033, y: 33.9781))
        path.addCurve(to: CGPoint(x: 39.963, y: 35.5284), controlPoint1: CGPoint(x: 40.8024, y: 34.9991), controlPoint2: CGPoint(x: 40.4395, y: 35.3491))
        path.addCurve(to: CGPoint(x: 38.3683, y: 35.6187), controlPoint1: CGPoint(x: 39.5048, y: 35.7005), controlPoint2: CGPoint(x: 38.9523, y: 35.7149))
        path.addLine(to: CGPoint(x: 38.3645, y: 35.6179))
        path.addCurve(to: CGPoint(x: 27.4432, y: 36.2617), controlPoint1: CGPoint(x: 33.1702, y: 34.7339), controlPoint2: CGPoint(x: 29.8284, y: 35.0041))
        path.addLine(to: CGPoint(x: 27.4409, y: 36.2632))
        path.addCurve(to: CGPoint(x: 24.5352, y: 39.2617), controlPoint1: CGPoint(x: 26.3923, y: 36.8121), controlPoint2: CGPoint(x: 25.4761, y: 37.9784))
        path.addCurve(to: CGPoint(x: 23.1513, y: 41.0941), controlPoint1: CGPoint(x: 24.0783, y: 39.8849), controlPoint2: CGPoint(x: 23.6164, y: 40.533))
        path.addCurve(to: CGPoint(x: 21.6438, y: 42.5029), controlPoint1: CGPoint(x: 22.6875, y: 41.6537), controlPoint2: CGPoint(x: 22.1891, y: 42.1649))
        path.addLine(to: CGPoint(x: 21.6415, y: 42.5044))
        path.addCurve(to: CGPoint(x: 20.0717, y: 42.7877), controlPoint1: CGPoint(x: 21.1682, y: 42.7939), controlPoint2: CGPoint(x: 20.6129, y: 42.9026))
        path.addCurve(to: CGPoint(x: 18.751, y: 41.89), controlPoint1: CGPoint(x: 19.5304, y: 42.6727), controlPoint2: CGPoint(x: 19.0658, y: 42.3471))
        path.addLine(to: CGPoint(x: 18.7495, y: 41.8877))
        path.addCurve(to: CGPoint(x: 17.9473, y: 39.988), controlPoint1: CGPoint(x: 18.3891, y: 41.3573), controlPoint2: CGPoint(x: 18.1434, y: 40.6875))
        path.addCurve(to: CGPoint(x: 17.4283, y: 37.7511), controlPoint1: CGPoint(x: 17.7506, y: 39.2864), controlPoint2: CGPoint(x: 17.5922, y: 38.5061))
        path.addCurve(to: CGPoint(x: 15.9916, y: 33.8296), controlPoint1: CGPoint(x: 17.0907, y: 36.1958), controlPoint2: CGPoint(x: 16.7265, y: 34.7575))
        path.addCurve(to: CGPoint(x: 6.27478, y: 28.797), controlPoint1: CGPoint(x: 14.3241, y: 31.7102), controlPoint2: CGPoint(x: 11.3805, y: 30.1024))
        path.addCurve(to: CGPoint(x: 4.85092, y: 28.0651), controlPoint1: CGPoint(x: 5.7018, y: 28.6473), controlPoint2: CGPoint(x: 5.1996, y: 28.409))
        path.addCurve(to: CGPoint(x: 4.37152, y: 26.7132), controlPoint1: CGPoint(x: 4.48851, y: 27.7074), controlPoint2: CGPoint(x: 4.2993, y: 27.2402))
        path.addLine(to: CGPoint(x: 4.41213, y: 26.5222))
        path.addCurve(to: CGPoint(x: 5.27453, y: 25.6212), controlPoint1: CGPoint(x: 4.53494, y: 26.0951), controlPoint2: CGPoint(x: 4.86778, y: 25.7905))
        path.addCurve(to: CGPoint(x: 6.94047, y: 25.4961), controlPoint1: CGPoint(x: 5.73176, y: 25.4312), controlPoint2: CGPoint(x: 6.31102, y: 25.3907))
        path.addCurve(to: CGPoint(x: 16.9244, y: 24.6032), controlPoint1: CGPoint(x: 10.4794, y: 26.0941), controlPoint2: CGPoint(x: 14.1343, y: 26.4538))
        path.addCurve(to: CGPoint(x: 21.2814, y: 19.0039), controlPoint1: CGPoint(x: 18.7566, y: 23.3801), controlPoint2: CGPoint(x: 20.1356, y: 21.5161))
        path.addCurve(to: CGPoint(x: 24.2225, y: 9.62924), controlPoint1: CGPoint(x: 22.4292, y: 16.487), controlPoint2: CGPoint(x: 23.329, y: 13.3526))
        path.addCurve(to: CGPoint(x: 25.4572, y: 6.66692), controlPoint1: CGPoint(x: 24.5174, y: 8.40352), controlPoint2: CGPoint(x: 24.8889, y: 7.3589))
        path.addCurve(to: CGPoint(x: 26.5315, y: 5.88691), controlPoint1: CGPoint(x: 25.7491, y: 6.31158), controlPoint2: CGPoint(x: 26.1025, y: 6.0371))
        path.addCurve(to: CGPoint(x: 27.9273, y: 5.83017), controlPoint1: CGPoint(x: 26.9604, y: 5.73686), controlPoint2: CGPoint(x: 27.4282, y: 5.72407))
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
