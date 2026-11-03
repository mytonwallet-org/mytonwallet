import SwiftUI
import UIKit
import UIComponents
import WalletContext

/// The app's alert asking for a line of text, with Telegram's alert text field (AlertInputFieldComponent): a capsule
/// as wide as the alert's buttons, focused as the alert opens, whose Return submits and closes the alert
@MainActor
enum AgentTextInputAlert {
    /// The text field's capsule reaches past the alert's text by this much on each side, to line up with its buttons
    static let fieldOutset: CGFloat = 8

    static func make(
        title: String,
        message: String? = nil,
        text: String?,
        placeholder: String,
        characterLimit: Int? = nil,
        submitTitle: String,
        onSubmit: @escaping (String) -> Void
    ) -> WAlertController {
        let input = Input(initialText: text ?? "")
        let submit = { onSubmit(input.text) }
        let alert = WAlertController(actions: [
            WAlertAction(title: submitTitle, style: .primary, handler: submit),
            WAlertAction(title: lang("Cancel")),
        ]) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .textStyle(.bodyStrong, scaling: .dynamic)
                    .accessibilityAddTraits(.isHeader)
                if let message, !message.isEmpty {
                    Text(message)
                }
                AgentAlertTextField(
                    text: input.initialText,
                    placeholder: placeholder,
                    characterLimit: characterLimit,
                    onMake: { input.field = $0 },
                    onReturn: { [weak input] in
                        // The submit runs once the alert has gone, as its button's does
                        guard let alert = input?.alert, !alert.isBeingDismissed else { return }
                        alert.dismiss(animated: true, completion: submit)
                    }
                )
                .frame(height: AgentAlertTextFieldView.height)
                .padding(.horizontal, -fieldOutset)
                .padding(.top, 13)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        input.alert = alert
        return alert
    }

    private final class Input {
        let initialText: String
        /// Kept until the submit, which runs once the alert has gone
        var field: UITextField?
        weak var alert: WAlertController?

        var text: String { field?.text ?? initialText }

        init(initialText: String) {
            self.initialText = initialText
        }
    }
}

private struct AgentAlertTextField: UIViewRepresentable {
    let text: String
    let placeholder: String
    let characterLimit: Int?
    let onMake: (UITextField) -> Void
    let onReturn: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(characterLimit: characterLimit, onReturn: onReturn)
    }

    func makeUIView(context: Context) -> AgentAlertTextFieldView {
        let field = AgentAlertTextFieldView()
        field.text = text
        field.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor.label.withAlphaComponent(0.4), .font: AgentAlertTextFieldView.font]
        )
        field.delegate = context.coordinator
        onMake(field)
        return field
    }

    func updateUIView(_ field: AgentAlertTextFieldView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, UITextFieldDelegate {
        private let characterLimit: Int?
        private let onReturn: () -> Void

        init(characterLimit: Int?, onReturn: @escaping () -> Void) {
            self.characterLimit = characterLimit
            self.onReturn = onReturn
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            guard let characterLimit else { return true }
            return (textField.text ?? "").utf16.count - range.length + string.utf16.count <= characterLimit
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            onReturn()
            return false
        }
    }
}

/// Telegram's alert text field: 17 pt text 18 pt into a 50 pt capsule, with the clear button centred 25 pt from its end
final class AgentAlertTextFieldView: UITextField {
    static let height: CGFloat = 50
    static let font = UIFont.systemFont(ofSize: 17)
    private static let textInset: CGFloat = 18
    private static let clearButtonSize: CGFloat = 44
    private static let clearButtonCenterInset: CGFloat = 25
    /// The text ends this far from the capsule's end, clear of the clear button
    private static let textTrailingInset: CGFloat = 66

    private var hasFocusedOnce = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        font = Self.font
        textColor = .label
        tintColor = AirTintColor
        backgroundColor = UIColor.label.withAlphaComponent(0.1)
        layer.cornerRadius = Self.height / 2
        clearButtonMode = .whileEditing
        autocapitalizationType = .sentences
        returnKeyType = .done
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.height)
    }

    override func textRect(forBounds bounds: CGRect) -> CGRect {
        let width = max(0, bounds.width - Self.textInset - Self.textTrailingInset)
        let x = isRightToLeft ? Self.textTrailingInset : Self.textInset
        return CGRect(x: x, y: 0, width: width, height: bounds.height)
    }

    override func editingRect(forBounds bounds: CGRect) -> CGRect {
        textRect(forBounds: bounds)
    }

    override func placeholderRect(forBounds bounds: CGRect) -> CGRect {
        textRect(forBounds: bounds)
    }

    override func clearButtonRect(forBounds bounds: CGRect) -> CGRect {
        let centerX = isRightToLeft ? Self.clearButtonCenterInset : bounds.width - Self.clearButtonCenterInset
        return CGRect(
            x: centerX - Self.clearButtonSize / 2,
            y: (bounds.height - Self.clearButtonSize) / 2,
            width: Self.clearButtonSize,
            height: Self.clearButtonSize
        )
    }

    private var isRightToLeft: Bool {
        effectiveUserInterfaceLayoutDirection == .rightToLeft
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, !hasFocusedOnce else { return }
        hasFocusedOnce = true
        DispatchQueue.main.async { [weak self] in
            self?.focusOncePresented()
        }
    }

    /// Takes the keyboard once the alert's presentation has finished, as the system doesn't hand it over during the
    /// presentation from iOS 27
    private func focusOncePresented() {
        var responder: UIResponder? = self
        while let current = responder, !(current is UIViewController) {
            responder = current.next
        }
        if let coordinator = (responder as? UIViewController)?.transitionCoordinator {
            coordinator.animate(alongsideTransition: nil) { [weak self] _ in
                _ = self?.becomeFirstResponder()
            }
        } else {
            _ = becomeFirstResponder()
        }
    }
}
