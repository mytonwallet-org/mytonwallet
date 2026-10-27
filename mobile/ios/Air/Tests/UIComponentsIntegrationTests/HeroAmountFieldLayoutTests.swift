import SwiftUI
import Testing
import UIKit
import WalletResources
@testable import UIComponents

@MainActor @Suite("Hero amount layout", .serialized)
struct HeroAmountFieldLayoutTests {
    @Test func `SwiftUI layout settles when the proposed width differs from rounded bounds`() async throws {
        _ = WalletResourcesBundle.bundle.load()
        for width: CGFloat in [365, 365 + 1.0 / 3, CGFloat(365).nextUp] {
            let field = LayoutCountingAmountField()
            field.focusesOnAppearance = false
            let state = AmountState()
            let host = UIHostingController(rootView: AmountView(field: field, state: state))
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width + 28, height: 852))
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { field.resignFirstResponder(); window.isHidden = true }
            for text in ["", "1", "29.76", "0.00001"] {
                state.text = text
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                field.becomeFirstResponder()
                try await Task.sleep(for: .milliseconds(100))
                #expect(field.layouts < 50)
            }
            field.configureAnimation(active: false, animated: false)
        }
    }

    @Test(arguments: ["", "29.76"])
    func `measuring other widths preserves displayed formatting and selection`(_ text: String) throws {
        _ = WalletResourcesBundle.bundle.load()
        let field = HeroAmountField()
        field.focusesOnAppearance = false
        field.maximumHeight = 86
        field.frame = CGRect(x: 0, y: 0, width: 365, height: 86)
        field.configure(text: text, prefix: "$", suffix: "", hasAmount: !text.isEmpty)
        field.layoutIfNeeded()
        let caret = try #require(field.position(from: field.beginningOfDocument, offset: min(1, text.count)))
        field.selectedTextRange = field.textRange(from: caret, to: caret)
        let font = try #require(field.font)
        let attributedText = field.attributedText
        let placeholder = field.attributedPlaceholder
        let defaultAttributes = NSDictionary(dictionary: field.defaultTextAttributes)
        for width: CGFloat in [0, 120, CGFloat(365).nextUp, 600] {
            let height = field.fittingHeight(forWidth: width)
            #expect(height > 0)
            if width == 0 { #expect(height < font.lineHeight) }
            #expect(field.font == font)
            #expect(field.attributedText == attributedText)
            #expect(field.attributedPlaceholder == placeholder)
            #expect(NSDictionary(dictionary: field.defaultTextAttributes) == defaultAttributes)
            #expect(field.selectedTextRange?.start == caret)
            #expect(field.selectedTextRange?.end == caret)
        }
    }
}

@MainActor private final class AmountState: ObservableObject {
    @Published var text = ""
}

private struct AmountView: View {
    let field: LayoutCountingAmountField
    @ObservedObject var state: AmountState
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 100)
            VStack(alignment: .leading, spacing: 0) {
                Text("0.00037 BTC").frame(height: 26)
                AmountRepresentable(field: field, text: state.text)
                    .padding(.leading, 24).padding(.trailing, 4)
            }.frame(height: 112)
            Spacer()
        }
    }
}

private struct AmountRepresentable: UIViewRepresentable {
    let field: LayoutCountingAmountField
    let text: String
    func makeUIView(context: Context) -> LayoutCountingAmountField { field }
    func updateUIView(_ view: LayoutCountingAmountField, context: Context) {
        view.maximumHeight = 86
        view.configure(text: text, prefix: "$", suffix: "", hasAmount: !text.isEmpty)
        view.configureAnimation(active: true, animated: true)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: LayoutCountingAmountField, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.intrinsicContentSize.width
        return CGSize(width: width, height: uiView.fittingHeight(forWidth: width))
    }
}

private final class LayoutCountingAmountField: HeroAmountField {
    var layouts = 0
    override func layoutSubviews() {
        layouts += 1
        // Fail a feedback loop without hanging the test runner.
        guard layouts < 50 else { return }
        super.layoutSubviews()
    }
}
