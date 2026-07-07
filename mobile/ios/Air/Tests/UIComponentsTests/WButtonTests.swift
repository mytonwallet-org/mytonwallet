import Testing
import UIKit
import UIComponents

@MainActor
@Suite("WButton")
struct WButtonTests {
    @Test
    func `disabled primary title color stays white`() {
        guard !isGlassButtonStylingEnabled else { return }

        let button = WButton(style: .primary)

        button.setTitle("Continue", for: .normal)
        button.isEnabled = false

        #expect(button.titleColor(for: .disabled)?.isEqual(UIColor.white) == true)
    }

    @Test
    func `disabled attributed primary title color stays white`() throws {
        guard !isGlassButtonStylingEnabled else { return }

        let button = WButton(style: .primary)

        button.setAttributedTitle(NSAttributedString(string: "Minimum amount"), for: .normal)
        button.isEnabled = false

        let title = try #require(button.attributedTitle(for: .disabled))
        let color = title.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
        #expect(color?.isEqual(UIColor.white) == true)
    }

    @Test
    func `disabled primary title color follows contrast tint for label accent`() {
        guard !isGlassButtonStylingEnabled else { return }

        let window = UIWindow(frame: CGRect(origin: .zero, size: CGSize(width: 100, height: 100)))
        window.tintColor = .label
        let button = WButton(style: .primary)
        window.addSubview(button)

        button.setTitle("Continue", for: .normal)
        button.isEnabled = false

        #expect(button.titleColor(for: .disabled)?.isEqual(UIColor.air.background) == true)
    }

    @Test
    func `glass primary attributed title is not rewritten`() throws {
        guard isGlassButtonStylingEnabled else { return }

        let button = WButton(style: .primary)

        button.setAttributedTitle(NSAttributedString(string: "Minimum amount"), for: .normal)
        button.isEnabled = false

        let title = try #require(button.attributedTitle(for: .normal))
        let color = title.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
        #expect(color == nil)
    }

    @Test
    func `compact capsule uses self sizing metrics`() throws {
        let button = WButton(style: .compactCapsule)
        let configuration = try #require(button.configuration)

        #expect(WButton.height(for: .compactCapsule) == 42)
        #expect(button.titleLabel?.font.pointSize == 15)
        #expect(configuration.contentInsets.top == 10)
        #expect(configuration.contentInsets.leading == 18)
        #expect(configuration.contentInsets.bottom == 10)
        #expect(configuration.contentInsets.trailing == 18)
        #expect(configuration.imagePadding == 6)

        let heightConstraint = button.constraints.first {
            $0.firstAttribute == .height && $0.secondAttribute == .notAnAttribute
        }
        #expect(heightConstraint?.constant == WButton.compactHeight)
    }

    private var isGlassButtonStylingEnabled: Bool {
        if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
            return true
        }
        return false
    }
}
