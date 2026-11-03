import MetalKit
import UIKit
import XCTest
@testable import UIComponents
import WalletResources

@MainActor
final class AgentSpinningTopBackdropTests: XCTestCase {
    func testRestingRefreshAndFirstHoldSequence() async throws {
        _ = WalletResourcesBundle.bundle.load()
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            throw XCTSkip("Recording the presented top requires an application host with a window scene")
        }
        let controller = UIViewController()
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.backgroundColor = .white
        let gradient = CAGradientLayer()
        gradient.frame = controller.view.bounds
        gradient.colors = [UIColor.systemCyan.withAlphaComponent(0.25).cgColor, UIColor.white.cgColor]
        gradient.startPoint = .zero
        gradient.endPoint = CGPoint(x: 0.35, y: 0.1)
        controller.view.layer.addSublayer(gradient)

        let top = AgentSpinningTopView(expandedScale: 2)
        top.frame = CGRect(x: 164, y: 190, width: 74, height: 74)
        controller.view.addSubview(top)
        let title = UILabel(frame: CGRect(x: 145, y: 278, width: 120, height: 40))
        title.text = "Agent"
        title.font = .systemFont(ofSize: 28, weight: .semibold)
        title.textColor = .black
        controller.view.addSubview(title)
        let phase = UILabel(frame: CGRect(x: 20, y: 420, width: 362, height: 60))
        phase.font = .monospacedSystemFont(ofSize: 16, weight: .medium)
        phase.textColor = .black
        phase.numberOfLines = 2
        controller.view.addSubview(phase)
        defer {
            top.isActive = false
            window.isHidden = true
        }
        window.layoutIfNeeded()
        top.layoutIfNeeded()
        let metal = try XCTUnwrap(top.subviews.compactMap { $0 as? MTKView }.first)
        let restingDrawableSize = metal.drawableSize
        metal.draw()

        // This paced scenario is also recorded through simctl. Screen recording observes compositor frames while
        // synchronous capture blocks the main thread; snapshots taken only after capture cannot detect a blink.
        phase.text = "A: Resting, two backdrop refreshes"
        try await Task.sleep(for: .milliseconds(4500))
        attachWindow(window, name: "Sequence A resting")
        phase.text = "B: First hold"
        top.perform(NSSelectorFromString("handlePress:"), with: BackdropTestPress(state: .began, point: CGPoint(x: 37, y: 37)))
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertTrue(metal.superview === window)
        XCTAssertGreaterThan(metal.drawableSize.width, restingDrawableSize.width)
        XCTAssertGreaterThan(metal.drawableSize.height, restingDrawableSize.height)
        XCTAssertFalse(metal.isHidden)
        attachWindow(window, name: "Sequence B first hold")

        phase.text = "C: Held and tilted over text"
        top.perform(NSSelectorFromString("handlePress:"), with: BackdropTestPress(state: .changed, point: CGPoint(x: 37, y: 147)))
        try await Task.sleep(for: .milliseconds(500))
        attachWindow(window, name: "Sequence C held over text")
        phase.text = "D: Released"
        top.perform(NSSelectorFromString("handlePress:"), with: BackdropTestPress(state: .ended, point: CGPoint(x: 37, y: 147)))
        try await Task.sleep(for: .milliseconds(2100))
        phase.text = "E: Resting after release"
        try await Task.sleep(for: .milliseconds(2300))
        XCTAssertTrue(metal.superview === top)
        XCTAssertEqual(metal.drawableSize, restingDrawableSize)
        XCTAssertFalse(metal.isHidden)
        attachWindow(window, name: "Sequence E resting again")

        phase.text = "F: Holding before leaving the tab"
        top.perform(NSSelectorFromString("handlePress:"), with: BackdropTestPress(state: .began, point: CGPoint(x: 37, y: 37)))
        try await Task.sleep(for: .milliseconds(600))
        let nextPage = UIView(frame: window.bounds.offsetBy(dx: -window.bounds.width, dy: 0))
        nextPage.backgroundColor = .systemGray6
        let nextTitle = UILabel(frame: CGRect(x: 20, y: 420, width: 362, height: 60))
        nextTitle.text = "G: Another tab, no lifted top"
        nextTitle.textColor = .black
        nextTitle.font = phase.font
        nextPage.addSubview(nextTitle)
        controller.view.addSubview(nextPage)
        top.isActive = false
        UIView.animate(withDuration: 0.35) {
            controller.view.transform = CGAffineTransform(translationX: window.bounds.width, y: 0)
        }
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertTrue(metal.superview === top)
        XCTAssertFalse(window.subviews.contains { $0 === metal })
        attachWindow(window, name: "Sequence G after leaving the tab")

        controller.view.transform = .identity
        nextPage.removeFromSuperview()
        top.isActive = true
        phase.text = "H: Hiding the owner while held"
        top.perform(NSSelectorFromString("handlePress:"), with: BackdropTestPress(state: .began, point: CGPoint(x: 37, y: 37)))
        try await Task.sleep(for: .milliseconds(500))
        top.isHidden = true
        metal.draw()
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertTrue(metal.superview === top)
        XCTAssertFalse(window.subviews.contains { $0 === metal })
        attachWindow(window, name: "Sequence H hidden owner")
    }

    func testHeldTopCapturesTheBackgroundWithoutItsRestingImageOrAReplacementRectangle() async throws {
        _ = WalletResourcesBundle.bundle.load()
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            throw XCTSkip("The composed Metal backdrop requires an application host with a window scene")
        }
        for size in [CGFloat(24), 74] {
            let controller = UIViewController()
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
            window.rootViewController = controller
            window.makeKeyAndVisible()
            addBackdrop(to: controller.view, topSize: size)

            let top = AgentSpinningTopView()
            top.frame = CGRect(x: size == 24 ? 26 : 164, y: 220, width: size, height: size)
            controller.view.addSubview(top)
            defer {
                top.isActive = false
                window.isHidden = true
            }
            window.layoutIfNeeded()
            top.layoutIfNeeded()
            let metal = try XCTUnwrap(top.subviews.compactMap { $0 as? MTKView }.first)
            metal.draw()
            try await Task.sleep(for: .milliseconds(200))

            top.perform(NSSelectorFromString("handlePress:"), with: BackdropTestPress(state: .began, point: CGPoint(x: size / 2, y: size / 2)))
            metal.draw()
            let captured = try XCTUnwrap(Mirror(reflecting: metal).children.first { $0.label == "backdrop" }?.value as? MTLTexture)
            let localRect = try XCTUnwrap(Mirror(reflecting: top).children.first { $0.label == "backdropRect" }?.value as? CGRect)
            let windowRect = top.convert(localRect, to: window)

            // Use a separately displayed scene with no top. Matching CALayer's color pipeline avoids comparing
            // drawHierarchy's different gradient color conversion with the component's layer-rendered texture.
            let referenceController = UIViewController()
            let referenceWindow = UIWindow(windowScene: scene)
            referenceWindow.frame = window.frame
            referenceWindow.overrideUserInterfaceStyle = window.traitCollection.userInterfaceStyle
            referenceWindow.rootViewController = referenceController
            referenceWindow.makeKeyAndVisible()
            addBackdrop(to: referenceController.view, topSize: size)
            defer { referenceWindow.isHidden = true }
            referenceWindow.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(80))
            let expected = capture(referenceWindow, rect: windowRect, width: captured.width, height: captured.height, usingLayer: true)
            let composed = capture(referenceWindow, rect: windowRect, width: captured.width, height: captured.height)
            let opaquePixels = stride(from: 3, to: composed.count, by: 4).filter { composed[$0] > 200 }.count
            XCTAssertGreaterThan(opaquePixels, captured.width * captured.height / 2,
                                 "A blank compositor snapshot cannot validate the backdrop")
            var actual = [UInt8](repeating: 0, count: captured.width * captured.height * 4)
            captured.getBytes(&actual, bytesPerRow: captured.width * 4,
                             from: MTLRegionMake2D(0, 0, captured.width, captured.height), mipmapLevel: 0)
            for (name, pixels) in [("reference", expected), ("capture", actual)] {
                let opaque = stride(from: 3, to: pixels.count, by: 4).filter { pixels[$0] > 200 }.count
                let ink = stride(from: 0, to: pixels.count, by: 4).filter {
                    pixels[$0 + 3] > 200 && min(pixels[$0], pixels[$0 + 1], pixels[$0 + 2]) < 100
                }.count
                XCTAssertGreaterThan(opaque, captured.width * captured.height / 2, "\(name) must not be transparent")
                XCTAssertGreaterThan(ink, 50, "\(name) must contain the text behind the top")
            }
            let wrongPixels = stride(from: 0, to: actual.count, by: 4).filter { offset in
                (0..<4).contains { abs(Int(actual[offset + $0]) - Int(expected[offset + $0])) > 8 }
            }.count
            addImage(actual, width: captured.width, height: captured.height, name: "Captured backdrop \(Int(size))")
            addImage(expected, width: captured.width, height: captured.height, name: "Background without top \(Int(size))")
            XCTAssertLessThan(wrongPixels, 50, "The captured background contains \(wrongPixels) wrong pixels for the \(Int(size)) pt top")

            referenceWindow.isHidden = true
            window.makeKeyAndVisible()

            top.perform(NSSelectorFromString("handlePress:"), with: BackdropTestPress(state: .changed, point: CGPoint(x: size / 2, y: size / 2 + 110)))
            try await Task.sleep(for: .milliseconds(600))
            metal.draw()
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "Held top \(Int(size))"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func attachWindow(_ window: UIWindow, name: String) {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func addBackdrop(to view: UIView, topSize: CGFloat) {
        view.backgroundColor = .white
        let gradient = CAGradientLayer()
        gradient.frame = view.bounds
        gradient.colors = [UIColor.systemCyan.withAlphaComponent(0.25).cgColor, UIColor.white.cgColor]
        gradient.startPoint = .zero
        gradient.endPoint = CGPoint(x: 0.35, y: 0.1)
        view.layer.addSublayer(gradient)
        let title = UILabel()
        title.text = topSize == 24 ? "Relevant sources found" : "Agent"
        title.textColor = topSize == 24 ? .systemCyan : .label
        title.font = .systemFont(ofSize: topSize == 24 ? 17 : 28, weight: .semibold)
        title.frame = topSize == 24
            ? CGRect(x: 54, y: 220, width: 300, height: 24)
            : CGRect(x: 145, y: 302, width: 120, height: 40)
        view.addSubview(title)
    }

    private func capture(_ window: UIWindow, rect: CGRect, width: Int, height: Int, usingLayer: Bool = false) -> [UInt8] {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: colorSpace,
                                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)!
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: CGFloat(width) / rect.width, y: -CGFloat(height) / rect.height)
        context.translateBy(x: -rect.minX, y: -rect.minY)
        if usingLayer {
            window.layer.render(in: context)
        } else {
            UIGraphicsPushContext(context)
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
            UIGraphicsPopContext()
        }
        return Array(UnsafeBufferPointer(start: context.data!.assumingMemoryBound(to: UInt8.self), count: width * height * 4))
    }

    private func addImage(_ bytes: [UInt8], width: Int, height: Int, name: String) {
        let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue).union(.byteOrder32Little),
                            provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil,
                            shouldInterpolate: false, intent: .defaultIntent)!
        let attachment = XCTAttachment(image: UIImage(cgImage: image))
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private final class BackdropTestPress: UILongPressGestureRecognizer {
    private let reportedState: UIGestureRecognizer.State
    private let point: CGPoint

    init(state: UIGestureRecognizer.State, point: CGPoint) {
        reportedState = state
        self.point = point
        super.init(target: nil, action: nil)
    }

    override var state: UIGestureRecognizer.State {
        get { reportedState }
        set { }
    }

    override func location(in view: UIView?) -> CGPoint { point }
}
