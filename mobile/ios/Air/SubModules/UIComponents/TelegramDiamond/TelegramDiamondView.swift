import Combine
import MetalKit
import SwiftUI

public struct TelegramDiamondView: View {
    public static var isAvailable: Bool { TelegramDiamondMetalView.isAvailable }

    @ObservedObject private var environment = CardBackgroundAnimationEnvironment.shared
    @State private var visible = false
    private let size: CGFloat
    private let renderingEnabled: Bool

    public init(size: CGFloat = 80, renderingEnabled: Bool = true) {
        self.size = size
        self.renderingEnabled = renderingEnabled
    }

    public var body: some View {
        DiamondRepresentable(size: size, active: visible && renderingEnabled && environment.applicationActive,
            animated: environment.diamondAnimationsEnabled)
            .frame(width: size, height: size)
            .onAppear { visible = true }
            .onDisappear { visible = false }
    }
}

private struct DiamondRepresentable: UIViewRepresentable {
    let size: CGFloat
    let active: Bool
    let animated: Bool

    func makeUIView(context: Context) -> TelegramDiamondContainerView {
        TelegramDiamondContainerView(size: size)
    }

    func updateUIView(_ view: TelegramDiamondContainerView, context: Context) {
        view.configure(active: active, animated: animated)
    }

    static func dismantleUIView(_ view: TelegramDiamondContainerView, coordinator: ()) {
        view.configure(active: false)
    }
}

final class TelegramDiamondContainerView: UIView {
    private let size: CGFloat
    private let diamond = TelegramDiamondMetalView(diamond: ())
    private var active = false
    private var texture: MTLTexture?
    private var captureRect = CGRect.zero

    init(size: CGFloat) {
        self.size = size
        super.init(frame: .zero)
        guard let diamond else { return }
        addSubview(diamond)
        diamond.expansionHost = { [weak self] in
            var responder: UIResponder? = self
            while let current = responder {
                if let controller = current as? UIViewController {
                    return controller.navigationController?.view
                }
                responder = current.next
            }
            return nil
        }
        diamond.onPressBegan = { [weak self] in self?.captureForeground() }
        diamond.onExpansionChanged = { [weak self] expanded in
            if !expanded { self?.texture = nil }
        }
        diamond.foregroundSource = { [weak self, weak diamond] in
            guard let self, let diamond, let texture = self.texture else { return nil }
            let rect = diamond.convert(self.captureRect, from: self)
                .offsetBy(dx: -diamond.bounds.midX, dy: -diamond.bounds.midY)
            return .init(texture: texture, uv: SIMD4(0, 0, 1, 1), rect: rect, preservesColors: true)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        diamond?.setRestingFrame(bounds, width: size * 0.9)
    }

    func configure(active: Bool, animated: Bool = true) {
        self.active = active
        diamond?.configure(active: active, animated: animated)
        if !active || !animated { texture = nil }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard active, isUserInteractionEnabled, !isHidden, alpha > 0.01, let diamond else { return nil }
        return diamond.hitTest(diamond.convert(point, from: self), with: event)
    }

    private func captureForeground() {
        // Keep the original background when a shrinking diamond is grabbed again.
        guard texture == nil else { return }
        guard let window, let diamond, let device = diamond.device,
              !UIAccessibility.isReduceTransparencyEnabled else { return }
        let canvas = diamond.expandedCanvasSize
        captureRect = CGRect(x: bounds.midX - canvas.width / 2, y: bounds.midY - canvas.height / 2,
            width: canvas.width, height: canvas.height)
        let windowRect = convert(captureRect, to: window)
        // Capture before expanding, including the title but excluding the resting diamond.
        let image = diamond.snapshotBackground(in: window, rect: windowRect)
        texture = DiamondForegroundTexture.make(image: image, device: device)
    }
}

enum DiamondForegroundTexture {
    /// Remove a header's flat background so the stone keeps its blue facets between glyphs.
    static func make(image: UIImage, device: MTLDevice) -> MTLTexture? {
        guard let image = image.cgImage else { return nil }
        let width = image.width, height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue),
            let bytes = context.data else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = bytes.assumingMemoryBound(to: UInt8.self)
        var bins: [Int: (count: Int, color: SIMD3<Float>)] = [:]
        for y in stride(from: 0, to: height, by: max(1, height / 32)) {
            for x in stride(from: 0, to: width, by: max(1, width / 32)) {
                let offset = y * context.bytesPerRow + x * 4
                guard pixels[offset + 3] > 250 else { continue }
                let key = Int(pixels[offset] / 16) | Int(pixels[offset + 1] / 16) << 4 | Int(pixels[offset + 2] / 16) << 8
                let color = SIMD3(Float(pixels[offset]), Float(pixels[offset + 1]), Float(pixels[offset + 2])) / 255
                let bin = bins[key] ?? (0, .zero)
                bins[key] = (bin.count + 1, bin.color + color)
            }
        }
        guard let bin = bins.values.max(by: { $0.count < $1.count }) else { return nil }
        let background = bin.color / Float(bin.count)
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * context.bytesPerRow + x * 4
                let originalAlpha = Float(pixels[offset + 3]) / 255
                guard originalAlpha > 0 else { continue }
                let color = SIMD3(Float(pixels[offset]), Float(pixels[offset + 1]), Float(pixels[offset + 2])) / (255 * originalAlpha)
                var alpha: Float = 0
                for component in 0..<3 {
                    let difference = color[component] - background[component]
                    let range = difference < 0 ? background[component] : 1 - background[component]
                    alpha = max(alpha, abs(difference) / max(0.001, range))
                }
                alpha = min(1, alpha)
                if alpha < 0.025 { alpha = 0 }
                let foreground = simd_clamp(color - background * (1 - alpha), .zero, SIMD3(repeating: alpha)) * originalAlpha
                for component in 0..<3 { pixels[offset + component] = UInt8(min(255, max(0, (foreground[component] * 255).rounded()))) }
                pixels[offset + 3] = UInt8((alpha * originalAlpha * 255).rounded())
            }
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: width, height: height, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.label = "Token hero foreground refraction"
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
            withBytes: bytes, bytesPerRow: context.bytesPerRow)
        return texture
    }
}
