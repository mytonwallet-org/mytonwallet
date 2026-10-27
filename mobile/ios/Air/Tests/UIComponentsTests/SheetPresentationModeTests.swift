import Testing
import UIKit
@testable import UIComponents

@MainActor
struct SheetPresentationModeTests {
    @Test
    func `sheet modes distinguish floating bottom attached and compact height fullscreen`() {
        guard #available(iOS 17.0, *) else { return }
        #expect(mode(.regular, .regular) == .floating)
        #expect(mode(.compact, .regular) == .bottomAttached)
        #expect(mode(.regular, .compact) == .fullScreen)
        #expect(mode(.compact, .compact) == .fullScreen)
        #expect(mode(.regular, .compact, edgeAttached: true) == .bottomAttached)
        #expect(mode(.compact, .compact, edgeAttached: true) == .bottomAttached)
        #expect(mode(.regular, .regular, edgeAttached: true) == .floating)
        #expect(mode(.unspecified, .regular) == nil)
        #expect(mode(.regular, .unspecified) == nil)
    }

    @Test
    func `classification uses the container configuration before the sheet is presented`() throws {
        guard #available(iOS 17.0, *) else { return }
        let presenter = UIViewController()
        let child = UIViewController()
        let navigation = UINavigationController(rootViewController: child)
        presenter.traitOverrides.horizontalSizeClass = .regular
        presenter.traitOverrides.verticalSizeClass = .compact
        #expect(child.sheetPresentationMode(presentingFrom: presenter) == .fullScreen)
        let sheet = try #require(navigation.sheetPresentationController)
        sheet.prefersEdgeAttachedInCompactHeight = true
        #expect(child.sheetPresentationMode(presentingFrom: presenter) == .bottomAttached)
        let fullscreen = UIViewController()
        fullscreen.modalPresentationStyle = .fullScreen
        #expect(fullscreen.sheetPresentationMode(presentingFrom: presenter) == .fullScreen)
        let popover = UIViewController()
        popover.modalPresentationStyle = .popover
        #expect(popover.sheetPresentationMode(presentingFrom: presenter) == nil)
    }

    @Test
    func `a compact presenter inside a regular window still produces a floating sheet`() {
        guard #available(iOS 17.0, *) else { return }
        let window = UIWindow()
        window.traitOverrides.horizontalSizeClass = .regular
        window.traitOverrides.verticalSizeClass = .regular
        let presenter = UIViewController()
        presenter.traitOverrides.horizontalSizeClass = .compact
        presenter.traitOverrides.verticalSizeClass = .regular
        window.addSubview(presenter.view)
        let navigation = UINavigationController(rootViewController: UIViewController())
        #expect(navigation.sheetPresentationMode(presentingFrom: presenter) == .floating)
    }

    private func mode(_ width: UIUserInterfaceSizeClass, _ height: UIUserInterfaceSizeClass, edgeAttached: Bool = false) -> SheetPresentationMode? {
        SheetPresentationMode(traits: traits(width, height), prefersEdgeAttachedInCompactHeight: edgeAttached)
    }

    private func traits(_ width: UIUserInterfaceSizeClass, _ height: UIUserInterfaceSizeClass) -> UITraitCollection {
        UITraitCollection(traitsFrom: [UITraitCollection(horizontalSizeClass: width), UITraitCollection(verticalSizeClass: height)])
    }
}
