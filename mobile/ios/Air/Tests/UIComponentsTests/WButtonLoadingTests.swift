import SwiftUI
import Testing
import UIKit
import WalletContext
import WalletResources
@testable import UIComponents

@Suite(.serialized) @MainActor
struct WButtonLoadingTests {
    init() { _ = WalletResourcesBundle.bundle.load() }

    @Test(arguments: ["Confirm", "Подтвердить", "Confirm this transaction"], [false, true])
    func `a narrow button replaces its full label with a centered spinner`(title: String, isRtl: Bool) throws {
        let button = WButton()
        button.semanticContentAttribute = isRtl ? .forceRightToLeft : .forceLeftToRight
        button.setTitle(title, for: .normal)
        button.frame = CGRect(x: 0, y: 0, width: 130, height: 52)
        button.showLoading = true
        button.layoutIfNeeded()

        let spinner = try spinner(in: button)
        #expect(abs(spinner.convert(spinner.bounds, to: button).midX - button.bounds.midX) < 0.5)
        #expect(button.titleLabel?.alpha == 0)
        #expect(button.title(for: .normal) == title)

        button.showLoading = false
        button.layoutIfNeeded()
        #expect(button.titleLabel?.alpha == 1)
        #expect(button.titleLabel?.transform == .identity)
        #expect(spinner.superview?.alpha == 0)
        #expect(abs(spinner.convert(CGPoint(x: spinner.bounds.midX, y: spinner.bounds.midY), to: button).x - button.bounds.midX) < 0.5)
    }

    @Test(arguments: [false, true])
    func `a wide button keeps the title and places the spinner at the trailing edge`(isRtl: Bool) throws {
        let button = WButton()
        button.semanticContentAttribute = isRtl ? .forceRightToLeft : .forceLeftToRight
        button.setTitle("Confirm", for: .normal)
        button.frame = CGRect(x: 0, y: 0, width: 360, height: 52)
        button.showLoading = true
        button.layoutIfNeeded()

        let spinner = try spinner(in: button)
        let frame = spinner.convert(spinner.bounds, to: button)
        let label = try #require(button.titleLabel)
        let titleFrame = label.convert(label.bounds, to: button)
        #expect(label.alpha == 1)
        #expect(isRtl ? frame.maxX + 8 <= titleFrame.minX : titleFrame.maxX + 8 <= frame.minX)
    }

    @Test func `resizing and replacing an attributed label rechecks available room`() throws {
        let button = WButton()
        button.setAttributedTitle(NSAttributedString(string: "Confirm", attributes: [.font: WButton.font]), for: .normal)
        button.frame = CGRect(x: 0, y: 0, width: 130, height: 52)
        button.showLoading = true
        button.layoutIfNeeded()
        #expect(button.titleLabel?.alpha == 0)

        button.frame.size.width = 360
        button.layoutIfNeeded()
        #expect(button.titleLabel?.alpha == 1)

        button.setAttributedTitle(NSAttributedString(string: "Confirm a much longer transaction label", attributes: [.font: WButton.font]), for: .normal)
        button.layoutIfNeeded()
        #expect(button.titleLabel?.alpha == 0)
        let spinner = try spinner(in: button)
        #expect(abs(spinner.convert(spinner.bounds, to: button).midX - button.bounds.midX) < 0.5)
    }

    @Test func `trade custom titles use the same loading replacement`() throws {
        let control = NativeTradeContinueButton(action: {})
        control.frame = CGRect(x: 0, y: 0, width: 150, height: 52)
        control.update(configuration: .init(title: .text("Подтвердить"), isEnabled: false, showLoading: true),
                       tintColor: .systemBlue, animated: false)
        control.layoutIfNeeded()
        control.button.layoutIfNeeded()
        let label = try #require(control.button.subviews.compactMap { $0 as? NativeTradeButtonTitleView }.first)
        #expect(label.alpha == 0)
        #expect(control.button.accessibilityLabel == "Подтвердить")
        #expect(!control.button.isUserInteractionEnabled)
        let spinner = try spinner(in: control.button)
        #expect(abs(spinner.convert(spinner.bounds, to: control.button).midX - control.button.bounds.midX) < 0.5)
    }

    @Test func `rapid loading reversal leaves the title restored`() async throws {
        let button = WButton()
        button.setTitle("Подтвердить", for: .normal)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        controller.view.addSubview(button)
        button.frame = CGRect(x: 20, y: 100, width: 150, height: 52)
        button.layoutIfNeeded()

        for loading in [true, false, true, false] {
            button.showLoading = loading
            button.layoutIfNeeded()
        }
        try await Task.sleep(for: .milliseconds(400))
        let spinner = try spinner(in: button)
        #expect(button.titleLabel?.alpha == 1)
        #expect(button.titleLabel?.transform == .identity)
        #expect(spinner.superview?.alpha == 0)
        #expect(!spinner.isAnimating)
    }

    @Test(arguments: [CGFloat(150), CGFloat(360)])
    func testHostedButtonPreservesLoadingPlacementAndWidth(width: CGFloat) async throws {
        let host = UIHostingController(rootView:
            Button("Подтвердить", action: {})
                .buttonStyle(.airPrimary)
                .environment(\.isLoading, true)
                .frame(width: width)
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(500))
        host.view.layoutIfNeeded()
        let button = try #require(descendants(of: host.view).compactMap { $0 as? WButton }.first)
        let spinner = try spinner(in: button)
        let content = try #require(button.subviews.first { $0 is any UIContentView })
        let isNarrow = width == 150
        let expectedSpinnerX = isNarrow ? button.bounds.midX : button.bounds.maxX - 28
        #expect(abs(button.bounds.width - width) < 0.5)
        #expect(abs(spinner.convert(spinner.bounds, to: button).midX - expectedSpinnerX) < 0.5)
        #expect(content.alpha == (isNarrow ? 0 : 1))
        #expect(!button.isUserInteractionEnabled)
    }

    @Test func `a finished SwiftUI operation cancels its delayed spinner`() async throws {
        func content(loading: Bool) -> some View {
            Button("Confirm", action: {})
                .buttonStyle(.airPrimary)
                .environment(\.isLoading, loading)
                .frame(width: 150)
        }
        let host = UIHostingController(rootView: content(loading: true))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        host.rootView = content(loading: false)
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(400))
        let button = try #require(descendants(of: host.view).compactMap { $0 as? WButton }.first)
        #expect(!button.showLoading)
        #expect(button.isUserInteractionEnabled)
    }

    @Test func `SwiftUI actions follow readiness and dynamic button styles`() async throws {
        var activations = 0
        func content(style: WButtonStyle, isEnabled: Bool, loading: Bool) -> some View {
            Button("Confirm") { activations += 1 }
                .buttonStyle(WUIButtonStyle(style: style))
                .disabled(!isEnabled)
                .environment(\.isLoading, loading)
                .frame(width: 150)
        }
        let host = UIHostingController(rootView: content(style: .primary, isEnabled: true, loading: false))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        let button = try #require(descendants(of: host.view).compactMap { $0 as? WButton }.first)
        try press(button)
        #expect(activations == 1)

        host.rootView = content(style: .primary, isEnabled: true, loading: true)
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        try press(button)
        #expect(activations == 1)

        host.rootView = content(style: .destructive, isEnabled: false, loading: false)
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        let destructiveButton = try #require(descendants(of: host.view).compactMap { $0 as? WButton }.first)
        #expect(destructiveButton.style == .destructive)
        try press(destructiveButton)
        #expect(activations == 1)
    }

    @Test(arguments: [UIUserInterfaceStyle.light, .dark])
    func `legacy SwiftUI primary labels remain white on colored backgrounds`(appearance: UIUserInterfaceStyle) async throws {
        if IOS_26_MODE_ENABLED, #available(iOS 26, *) { return }
        let host = UIHostingController(rootView:
            Button("MMMM", action: {})
                .buttonStyle(.airPrimary)
                .frame(width: 240)
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.tintColor = .systemBlue
        window.overrideUserInterfaceStyle = appearance
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        host.view.layoutIfNeeded()
        let button = try #require(descendants(of: host.view).compactMap { $0 as? WButton }.first)
        let pixels = try renderContentPixels(in: button)
        let whitePixels = stride(from: 0, to: pixels.count, by: 4).filter {
            min(pixels[$0], pixels[$0 + 1], pixels[$0 + 2], pixels[$0 + 3]) > 230
        }.count
        let bluePixels = stride(from: 0, to: pixels.count, by: 4).filter {
            pixels[$0] < 40 && pixels[$0 + 1] > 80 && pixels[$0 + 2] > 200 && pixels[$0 + 3] > 230
        }.count
        #expect(bluePixels > 100)
        #expect(whitePixels > 20)
    }

    @Test func `SwiftUI clear background loading remains visible on a white surface`() async throws {
        let host = UIHostingController(rootView:
            Button("Open wallet without checking", action: {})
                .buttonStyle(.airClearBackground)
                .environment(\.isLoading, true)
                .frame(width: 150)
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.backgroundColor = .white
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(500))
        host.view.layoutIfNeeded()
        let button = try #require(descendants(of: host.view).compactMap { $0 as? WButton }.first)
        let spinner = try spinner(in: button)
        let color = spinner.tintColor.resolvedColor(with: button.traitCollection)
        #expect(spinner.isAnimating)
        #expect(spinner.superview?.alpha == 1)
        #expect(color != UIColor.white)
        #expect(color == UIColor.tintColor.resolvedColor(with: button.traitCollection))
        #expect(abs(spinner.convert(spinner.bounds, to: button).midX - button.bounds.midX) < 0.5)
    }

    @Test func `an interrupted loading entrance keeps rotating throughout its exit`() async throws {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        let button = WButton()
        button.setTitle("Confirm", for: .normal)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        controller.view.addSubview(button)
        button.frame = CGRect(x: 20, y: 100, width: 130, height: 52)
        button.layoutIfNeeded()
        button.showLoading = true
        button.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(80))
        let spinner = try spinner(in: button)
        #expect(spinner.isAnimating)

        button.showLoading = false
        button.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(190))
        #expect(spinner.isAnimating)
        #expect(!spinner.isHidden)

        try await Task.sleep(for: .milliseconds(160))
        #expect(!spinner.isAnimating)
        #expect(spinner.isHidden)
    }

    private func renderContentPixels(in button: WButton) throws -> [UInt8] {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: button.bounds.size, format: format).image { context in
            button.layer.render(in: context.cgContext)
        }
        let bitmap = try #require(image.cgImage?.cropping(to: button.bounds.insetBy(dx: 32, dy: 6)))
        var bytes = [UInt8](repeating: 0, count: bitmap.width * bitmap.height * 4)
        try bytes.withUnsafeMutableBytes { storage in
            let context = try #require(CGContext(data: storage.baseAddress, width: bitmap.width, height: bitmap.height,
                bitsPerComponent: 8, bytesPerRow: bitmap.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(bitmap, in: CGRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height))
        }
        return bytes
    }

    private func spinner(in button: WButton) throws -> WActivityIndicator {
        try #require(descendants(of: button).compactMap { $0 as? WActivityIndicator }.first)
    }

    private func press(_ button: WButton) throws {
        let target = try #require(button.allTargets.compactMap { $0.base as? NSObject }.first)
        let action = try #require(button.actions(forTarget: target, forControlEvent: .touchUpInside)?.first)
        target.perform(NSSelectorFromString(action))
    }

    private func descendants(of view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}
