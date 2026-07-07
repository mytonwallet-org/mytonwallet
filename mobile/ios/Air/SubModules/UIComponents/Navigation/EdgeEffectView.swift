import UIKit

public final class EdgeEffectView: UIView {
    public enum Edge {
        case top
        case bottom
    }

    private struct Configuration {
        var content: UIColor?
        var blur: Bool
        var alpha: CGFloat
        var edge: Edge
        var edgeSize: CGFloat
    }

    private let contentView = UIView()
    private let contentMaskView = UIImageView()
    private var blurView: EdgeVariableBlurView?
    private var configuration = Configuration(
        content: nil,
        blur: false,
        alpha: 0.75,
        edge: .top,
        edgeSize: 0
    )
    private var currentMaskKey: String?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        contentView.mask = contentMaskView
        addSubview(contentView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        applyConfiguration()
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyContentColor()
    }

    public func updateColor(_ color: UIColor) {
        configuration.content = color
        applyContentColor()
    }

    public func update(
        content: UIColor?,
        blur: Bool = false,
        alpha: CGFloat = 0.75,
        edge: Edge,
        edgeSize: CGFloat
    ) {
        configuration = Configuration(
            content: content,
            blur: blur,
            alpha: alpha,
            edge: edge,
            edgeSize: edgeSize
        )
        applyConfiguration()
    }

    private func applyConfiguration() {
        guard !bounds.isEmpty else { return }

        applyContentColor()
        contentView.alpha = configuration.alpha
        contentView.frame = bounds
        contentMaskView.frame = bounds

        let edgeSize = max(0, min(configuration.edgeSize, bounds.height))
        let maskKey = "\(edgeSize)-\(configuration.edge)"
        if currentMaskKey != maskKey {
            currentMaskKey = maskKey
            contentMaskView.image = edgeSize > 0
                ? Self.generateEdgeGradient(baseHeight: edgeSize, isInverted: configuration.edge == .bottom)
                : nil
        }

        if configuration.blur {
            let blurHeight = max(edgeSize, bounds.height - 14)
            let blurFrame = CGRect(
                x: 0,
                y: configuration.edge == .bottom ? bounds.height - blurHeight : 0,
                width: bounds.width,
                height: blurHeight
            )
            let blurView: EdgeVariableBlurView
            if let current = self.blurView {
                blurView = current
            } else {
                blurView = EdgeVariableBlurView(maxBlurRadius: 1)
                insertSubview(blurView, at: 0)
                self.blurView = blurView
            }
            blurView.frame = blurFrame
            blurView.update(
                size: blurFrame.size,
                constantHeight: max(1, edgeSize - 4),
                isInverted: configuration.edge == .bottom,
                gradient: Self.generateEdgeGradientData(baseHeight: max(1, edgeSize - 4))
            )
            blurView.transform = contentMaskView.transform
        } else if let blurView {
            self.blurView = nil
            blurView.removeFromSuperview()
        }
    }

    private func applyContentColor() {
        if let content = configuration.content {
            contentView.backgroundColor = content
        }
    }

    private static func generateEdgeGradientData(baseHeight: CGFloat) -> EdgeVariableBlurGradient {
        let norm = edgeGradientAlpha.max() ?? 1
        return EdgeVariableBlurGradient(
            height: baseHeight,
            alpha: edgeGradientAlpha.map { $0 / norm },
            positions: edgeGradientLocations
        )
    }

    private static func generateEdgeGradient(baseHeight: CGFloat, isInverted: Bool) -> UIImage {
        let norm = edgeGradientAlpha.max() ?? 1
        let image = generateGradientImage(
            size: CGSize(width: 1, height: baseHeight),
            colors: edgeGradientAlpha.map { UIColor(white: 0, alpha: $0 / norm) },
            locations: edgeGradientLocations,
            isInverted: isInverted
        )
        return image.resizableImage(
            withCapInsets: UIEdgeInsets(
                top: isInverted ? baseHeight : 0,
                left: 0,
                bottom: isInverted ? 0 : baseHeight,
                right: 0
            ),
            resizingMode: .stretch
        )
    }

    private static func generateGradientImage(size: CGSize, colors: [UIColor], locations: [CGFloat], isInverted: Bool) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        defer { UIGraphicsEndImageContext() }

        guard let context = UIGraphicsGetCurrentContext(),
              let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors.map(\.cgColor) as CFArray,
                locations: locations
              ) else {
            return UIImage()
        }

        if isInverted {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: size.height),
                end: .zero,
                options: []
            )
        } else {
            context.drawLinearGradient(
                gradient,
                start: .zero,
                end: CGPoint(x: 0, y: size.height),
                options: []
            )
        }

        return UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
    }
}

private struct EdgeVariableBlurGradient: Equatable {
    var height: CGFloat
    var alpha: [CGFloat]
    var positions: [CGFloat]
}

private final class EdgeVariableBlurView: UIView {
    private struct Params: Equatable {
        var size: CGSize
        var constantHeight: CGFloat
        var isInverted: Bool
        var gradient: EdgeVariableBlurGradient
    }

    private let maxBlurRadius: CGFloat
    private let effectLayerDelegate = NullLayerDelegate()
    private var effectLayer: CALayer?
    private var effect: EdgeVariableBlurEffect?
    private var params: Params?

    init(maxBlurRadius: CGFloat) {
        self.maxBlurRadius = maxBlurRadius
        super.init(frame: .zero)

        if let effectLayer = createBackdropLayer() {
            self.effectLayer = effectLayer
            self.effect = EdgeVariableBlurEffect(layer: effectLayer, maxBlurRadius: maxBlurRadius)
            effectLayer.delegate = effectLayerDelegate
            effectLayer.setValue(0.5, forKey: "scale")
            layer.addSublayer(effectLayer)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(size: CGSize, constantHeight: CGFloat, isInverted: Bool, gradient: EdgeVariableBlurGradient) {
        let params = Params(
            size: size,
            constantHeight: constantHeight,
            isInverted: isInverted,
            gradient: gradient
        )
        guard params != self.params else { return }
        self.params = params
        effect?.update(
            size: size,
            constantHeight: constantHeight,
            isInverted: isInverted,
            gradient: gradient
        )
    }
}

@MainActor
private final class EdgeVariableBlurEffect {
    private struct Params: Equatable {
        var size: CGSize
        var constantHeight: CGFloat
        var isInverted: Bool
        var gradient: EdgeVariableBlurGradient
    }

    private let layer: CALayer
    private let maxBlurRadius: CGFloat
    private let maskSourceView: UIImageView?
    private var gradientImage: UIImage?
    private var params: Params?

    init(layer: CALayer, maxBlurRadius: CGFloat) {
        self.layer = layer
        self.maxBlurRadius = maxBlurRadius

        if #available(iOS 26, *) {
            let maskSourceView = UIImageView()
            maskSourceView.layer.name = "mask_source"
            self.maskSourceView = maskSourceView

            if let variableBlur = makeVariableBlurFilter() {
                variableBlur.setValue(maxBlurRadius, forKey: "inputRadius")
                variableBlur.setValue("mask_source", forKey: "inputSourceSublayerName")
                variableBlur.setValue(true, forKey: "inputNormalizeEdges")
                layer.filters = [variableBlur]
            }

            layer.addSublayer(maskSourceView.layer)
        } else {
            self.maskSourceView = nil
        }
    }

    func update(size: CGSize, constantHeight: CGFloat, isInverted: Bool, gradient: EdgeVariableBlurGradient) {
        let params = Params(
            size: size,
            constantHeight: constantHeight,
            isInverted: isInverted,
            gradient: gradient
        )
        guard params != self.params else { return }

        let isInvertedUpdated = isInverted != self.params?.isInverted
        let isGradientUpdated = isInvertedUpdated || gradient != self.params?.gradient
        let isHeightUpdated = isInvertedUpdated || gradient.height != self.params?.gradient.height || size.height != self.params?.size.height

        if isGradientUpdated {
            gradientImage = EdgeEffectView.generateEdgeGradientForBlur(
                baseHeight: max(1, gradient.height),
                isInverted: isInverted
            )
        }

        self.params = params

        let bounds = CGRect(origin: .zero, size: size)
        layer.frame = bounds

        if let maskSourceView {
            if isGradientUpdated {
                maskSourceView.image = gradientImage
            }
            maskSourceView.frame = bounds
            maskSourceView.layer.frame = bounds
        } else if isHeightUpdated || isGradientUpdated {
            updateLegacyEffect()
        }
    }

    private func updateLegacyEffect() {
        guard let params, let gradientImage else { return }
        guard let variableBlur = makeVariableBlurFilter() else { return }

        variableBlur.setValue(maxBlurRadius, forKey: "inputRadius")
        variableBlur.setValue(true, forKey: "inputNormalizeEdges")

        let maskSize = CGSize(width: 1, height: min(800, params.size.height))
        guard let image = generateImage(size: maskSize, opaque: false, drawing: { size, context in
            context.clear(CGRect(origin: .zero, size: size))

            let mainEffectFrame: CGRect
            let additionalEffectFrame: CGRect
            if params.isInverted {
                mainEffectFrame = CGRect(origin: .zero, size: CGSize(width: size.width, height: params.constantHeight))
                additionalEffectFrame = CGRect(
                    x: 0,
                    y: params.constantHeight,
                    width: size.width,
                    height: max(0, size.height - params.constantHeight)
                )
            } else {
                mainEffectFrame = CGRect(
                    x: 0,
                    y: size.height - params.constantHeight,
                    width: size.width,
                    height: params.constantHeight
                )
                additionalEffectFrame = CGRect(
                    x: 0,
                    y: 0,
                    width: size.width,
                    height: max(0, size.height - params.constantHeight)
                )
            }

            context.setFillColor(UIColor(white: 0, alpha: 1).cgColor)
            context.fill(additionalEffectFrame)
            gradientImage.draw(in: mainEffectFrame, blendMode: .normal, alpha: 1)
        })?.cgImage else {
            return
        }

        variableBlur.setValue(image, forKey: "inputMaskImage")
        layer.filters = [variableBlur]
    }
}

private final class NullAction: NSObject, CAAction {
    func run(forKey event: String, object anObject: Any, arguments dict: [AnyHashable: Any]?) {
    }
}

private final class NullLayerDelegate: NSObject, CALayerDelegate {
    private let nullAction = NullAction()

    func action(for layer: CALayer, forKey event: String) -> CAAction? {
        nullAction
    }
}

@MainActor
private func createBackdropLayer() -> CALayer? {
    let className = ("CA" as NSString).appendingFormat("BackdropLayer")
    guard let layerClass = NSClassFromString(className as String) as AnyObject as? NSObject else {
        return nil
    }
    let allocSelector = NSSelectorFromString("alloc")
    guard let allocMethod = layerClass.method(for: allocSelector) else {
        return nil
    }
    let alloc = unsafeBitCast(allocMethod, to: (@convention(c) (AnyObject, Selector) -> NSObject?).self)
    guard let layerObject = alloc(layerClass, allocSelector) else {
        return nil
    }

    let initSelector = NSSelectorFromString("init")
    guard let initMethod = layerObject.method(for: initSelector) else {
        return nil
    }
    let initialize = unsafeBitCast(initMethod, to: (@convention(c) (NSObject, Selector) -> NSObject?).self)
    return initialize(layerObject, initSelector) as? CALayer
}

private func makeVariableBlurFilter() -> NSObject? {
    guard let filterClass = NSClassFromString(String("retliFAC".reversed())) as? NSObject.Type else {
        return nil
    }
    let selector = NSSelectorFromString(String(":epyThtiWretlif".reversed()))
    guard filterClass.responds(to: selector) else {
        return nil
    }
    return filterClass.perform(selector, with: "variableBlur").takeUnretainedValue() as? NSObject
}

private func generateImage(size: CGSize, opaque: Bool, drawing: (CGSize, CGContext) -> Void) -> UIImage? {
    guard size.width > 0, size.height > 0 else { return nil }
    UIGraphicsBeginImageContextWithOptions(size, opaque, 0)
    defer { UIGraphicsEndImageContext() }
    guard let context = UIGraphicsGetCurrentContext() else { return nil }
    drawing(size, context)
    return UIGraphicsGetImageFromCurrentImageContext()
}

private let edgeGradientAlpha: [CGFloat] = [
    0.8470588235294118, 0.8431372549019608, 0.8392156862745098, 0.8352941176470589,
    0.8313725490196078, 0.8274509803921568, 0.8235294117647058, 0.8196078431372549,
    0.8156862745098039, 0.8117647058823529, 0.807843137254902, 0.803921568627451,
    0.8, 0.7960784313725491, 0.792156862745098, 0.788235294117647,
    0.7843137254901961, 0.7803921568627451, 0.7764705882352941, 0.7725490196078432,
    0.7686274509803921, 0.7647058823529411, 0.7607843137254902, 0.7568627450980392,
    0.7529411764705882, 0.7490196078431373, 0.7450980392156863, 0.7411764705882353,
    0.7372549019607844, 0.7333333333333334, 0.7294117647058824, 0.7254901960784313,
    0.7215686274509804, 0.7176470588235294, 0.7137254901960784, 0.7098039215686274,
    0.7019607843137254, 0.6941176470588235, 0.6862745098039216, 0.6784313725490196,
    0.6705882352941177, 0.6588235294117647, 0.6509803921568628, 0.6431372549019607,
    0.6313725490196078, 0.6235294117647059, 0.615686274509804, 0.603921568627451,
    0.596078431372549, 0.5882352941176471, 0.5764705882352941, 0.5647058823529412,
    0.5529411764705883, 0.5411764705882354, 0.5294117647058824, 0.5176470588235293,
    0.5058823529411764, 0.49411764705882355, 0.4862745098039216, 0.4745098039215686,
    0.4627450980392157, 0.4549019607843138, 0.44313725490196076, 0.43137254901960786,
    0.41960784313725485, 0.4117647058823529, 0.4, 0.388235294117647,
    0.3764705882352941, 0.3647058823529412, 0.3529411764705882, 0.3411764705882353,
    0.3294117647058824, 0.3176470588235294, 0.3058823529411765, 0.2941176470588235,
    0.2823529411764706, 0.2705882352941177, 0.2588235294117647, 0.2431372549019608,
    0.2313725490196078, 0.21568627450980393, 0.19999999999999996, 0.18039215686274512,
    0.16078431372549018, 0.14117647058823535, 0.11764705882352944,
    0.09019607843137256, 0.04705882352941182, 0.0,
]

private let edgeGradientLocations: [CGFloat] = [
    0.0, 0.020905923344947737, 0.059233449477351915, 0.08710801393728224,
    0.10801393728222997, 0.12195121951219512, 0.13240418118466898,
    0.14285714285714285, 0.15331010452961671, 0.1602787456445993,
    0.17073170731707318, 0.18118466898954705, 0.1916376306620209,
    0.20209059233449478, 0.20905923344947736, 0.21254355400696864,
    0.21951219512195122, 0.2264808362369338, 0.23344947735191637,
    0.23693379790940766, 0.24390243902439024, 0.24738675958188153,
    0.25435540069686413, 0.2578397212543554, 0.2613240418118467,
    0.2682926829268293, 0.27177700348432055, 0.27526132404181186,
    0.28222996515679444, 0.2857142857142857, 0.289198606271777,
    0.2926829268292683, 0.2961672473867596, 0.29965156794425085,
    0.30313588850174217, 0.30662020905923343, 0.313588850174216,
    0.3205574912891986, 0.32752613240418116, 0.3344947735191638,
    0.34146341463414637, 0.34843205574912894, 0.3554006968641115,
    0.3623693379790941, 0.3693379790940767, 0.37630662020905925,
    0.3797909407665505, 0.3867595818815331, 0.39372822299651566,
    0.397212543554007, 0.40418118466898956, 0.41114982578397213,
    0.4181184668989547, 0.4250871080139373, 0.43205574912891986,
    0.43902439024390244, 0.445993031358885, 0.4529616724738676,
    0.4564459930313589, 0.4634146341463415, 0.47038327526132406,
    0.4738675958188153, 0.4808362369337979, 0.4878048780487805,
    0.49477351916376305, 0.49825783972125437, 0.5052264808362369,
    0.5121951219512195, 0.519163763066202, 0.5261324041811847,
    0.5331010452961672, 0.5400696864111498, 0.5470383275261324,
    0.554006968641115, 0.5609756097560976, 0.5679442508710801,
    0.5749128919860628, 0.5818815331010453, 0.5888501742160279,
    0.5993031358885017, 0.6062717770034843, 0.6167247386759582,
    0.627177700348432, 0.6411149825783972, 0.6585365853658537,
    0.6759581881533101, 0.6968641114982579, 0.7282229965156795,
    0.7909407665505227, 1.0,
]

private extension EdgeEffectView {
    static func generateEdgeGradientForBlur(baseHeight: CGFloat, isInverted: Bool) -> UIImage {
        generateEdgeGradient(baseHeight: baseHeight, isInverted: isInverted)
    }
}
