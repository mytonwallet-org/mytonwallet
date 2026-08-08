import Testing
import UIKit
@testable import UIComponents

@Suite("Address Text Field")
@MainActor
struct AddressTextFieldTests {
    @Test
    func `single line input scrolls horizontally without wrapping`() {
        let textView = AddressTextField.PasteAwareTextView(
            frame: CGRect(x: 0, y: 0, width: 240, height: 22)
        )
        textView.font = .systemFont(ofSize: 17)

        AddressTextField.configureTextLayout(
            textView,
            maximumNumberOfLines: 1
        )
        textView.text = "UQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJKZ"
        textView.updateSingleLineContainerSize()

        #expect(textView.isScrollEnabled)
        #expect(!textView.showsHorizontalScrollIndicator)
        #expect(textView.textContainer.maximumNumberOfLines == 1)
        #expect(textView.textContainer.lineBreakMode == .byClipping)
        #expect(!textView.textContainer.widthTracksTextView)
        #expect(textView.textContainer.size.width > textView.bounds.width)
        #expect(textView.contentSize.width > textView.bounds.width)
    }

    @Test
    func `multiline input keeps wrapping and intrinsic height sizing`() {
        let textView = UITextView()

        AddressTextField.configureTextLayout(
            textView,
            maximumNumberOfLines: 0
        )

        #expect(!textView.isScrollEnabled)
        #expect(textView.textContainer.maximumNumberOfLines == 0)
        #expect(textView.textContainer.lineBreakMode == .byCharWrapping)
        #expect(textView.textContainer.widthTracksTextView)
    }
}
