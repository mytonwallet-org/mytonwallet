import Testing
import UIKit
@testable import UISend

@MainActor
@Suite("Send Continue Button Animation")
struct SendContinueButtonAnimationTests {
    @Test
    func `showing a hidden opaque button restores visibility and interaction`() {
        let button = UIView()
        button.alpha = 1
        button.isHidden = true
        button.isUserInteractionEnabled = false

        setSendContinueButtonHidden(
            button,
            hidden: false,
            animated: false
        )

        #expect(button.alpha == 1)
        #expect(!button.isHidden)
        #expect(button.isUserInteractionEnabled)
    }
}
