import XCTest
import UIKit
import UIComponents
@testable import UIAgent
import WalletContext
import WalletResources

@MainActor
final class AgentTextInputAlertTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        _ = WalletResourcesBundle.bundle.load()
    }

    /// The field lies inside the dialog on every iOS version, as wide as its buttons: the 300 pt panel less 14 pt on
    /// each side, centred on the screen
    func testFieldFitsTheDialogAndLinesUpWithItsButtons() async throws {
        let (alert, window) = try await show(
            AgentTextInputAlert.make(title: lang("Rename Chat"), text: "My portfolio", placeholder: lang("New Chat"), submitTitle: lang("Save")) { _ in }
        )
        defer { window.isHidden = true }
        let field = try await waitForTextInputField(in: alert)
        alert.view.layoutIfNeeded()

        let frame = field.convert(field.bounds, to: alert.view)
        XCTAssertEqual(frame.width, 300 - 28, accuracy: 0.5)
        XCTAssertEqual(frame.midX, alert.view.bounds.midX, accuracy: 0.5)
        XCTAssertEqual(frame.height, 50)
        XCTAssertEqual(field.layer.cornerRadius, 25)
        XCTAssertEqual(field.text, "My portfolio")
        XCTAssertEqual(field.attributedPlaceholder?.string, lang("New Chat"))
        XCTAssertEqual(field.font, .systemFont(ofSize: 17))
        XCTAssertEqual(field.textRect(forBounds: field.bounds).minX, 18)
        XCTAssertEqual(field.clearButtonRect(forBounds: field.bounds).midX, field.bounds.width - 25)
        XCTAssertEqual(field.clearButtonMode, .whileEditing)
        field.semanticContentAttribute = .forceRightToLeft
        XCTAssertEqual(field.textRect(forBounds: field.bounds).maxX, field.bounds.width - 18)
        XCTAssertEqual(field.clearButtonRect(forBounds: field.bounds).midX, 25)
        field.semanticContentAttribute = .unspecified
        XCTAssertEqual(field.returnKeyType, .done)
        XCTAssertEqual(field.autocapitalizationType, .sentences)
    }

    func testReturnSubmitsTheText() async throws {
        var submitted: [String] = []
        let (alert, window) = try await show(
            AgentTextInputAlert.make(title: lang("Rename Chat"), text: "My portfolio", placeholder: lang("New Chat"), submitTitle: lang("Save")) {
                submitted.append($0)
            }
        )
        defer { window.isHidden = true }
        let field = try await waitForTextInputField(in: alert)
        field.text = "Savings"

        XCTAssertEqual(field.delegate?.textFieldShouldReturn?(field), false)
        XCTAssertEqual(submitted, ["Savings"])
    }

    func testCharacterLimitKeepsTheTextWithinIt() async throws {
        let (alert, window) = try await show(
            AgentTextInputAlert.make(title: lang("Report a Problem"), text: nil, placeholder: lang("Optional"), characterLimit: 5, submitTitle: lang("Send")) { _ in }
        )
        defer { window.isHidden = true }
        let field = try await waitForTextInputField(in: alert)
        let delegate = try XCTUnwrap(field.delegate)

        XCTAssertEqual(delegate.textField?(field, shouldChangeCharactersIn: NSRange(location: 0, length: 0), replacementString: "12345"), true)
        XCTAssertEqual(delegate.textField?(field, shouldChangeCharactersIn: NSRange(location: 0, length: 0), replacementString: "123456"), false)
    }

    /// The alert as the whole of a key window, where its content draws as it does presented in the app
    private func show(_ alert: WAlertController) async throws -> (WAlertController, UIWindow) {
        let window = makeKeyWindow(showing: alert)
        window.layoutIfNeeded()
        return (alert, window)
    }
}
