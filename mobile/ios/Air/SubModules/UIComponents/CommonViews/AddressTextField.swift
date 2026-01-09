
import Foundation
import SwiftUI
import WalletContext

public struct AddressTextField: UIViewRepresentable {
    
    @Binding var value: String
    @Binding var isFocused: Bool
    var onNext: () -> ()
    
    @State private var cooldown: Date = .distantPast
    
    public init(value: Binding<String>, isFocused: Binding<Bool>, onNext: @escaping () -> Void) {
        self._value = value
        self._isFocused = isFocused
        self.onNext = onNext
    }
    
    public final class Coordinator: NSObject, UITextViewDelegate {
        
        var onChange: (String) -> ()
        var onFocusChange: (Bool) -> ()
        var onNext: () -> ()
        
        init(onChange: @escaping (String) -> Void, onFocusChange: @escaping (Bool) -> Void, onNext: @escaping () -> Void) {
            self.onChange = onChange
            self.onFocusChange = onFocusChange
            self.onNext = onNext
        }
        
        public func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if text == "\n" {
                DispatchQueue.main.async { self.onNext() }
                return false
            }
            return true
        }
        
        public func textViewDidChange(_ textView: UITextView) {
            onChange(textView.text)
        }
        
        public func textViewDidBeginEditing(_ textView: UITextView) {
            onFocusChange(true)
        }
        
        public func textViewDidEndEditing(_ textView: UITextView) {
            onFocusChange(false)
        }
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(
            onChange: {
                value = $0
            },
            onFocusChange: { isFocused in
                self.isFocused = isFocused
                if !isFocused {
                    self.cooldown = .now
                }
            },
            onNext: onNext
        )
    }
    
    public func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.font = .preferredFont(forTextStyle: .body)
        view.autocorrectionType = .no
        view.autocapitalizationType = .none
        view.keyboardType = .asciiCapable
        view.textContainerInset = .zero
        view.textContainer.lineBreakMode = .byCharWrapping
        view.textContainer.lineFragmentPadding = 0
        view.textContainer.maximumNumberOfLines = 1
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byCharWrapping
        view.typingAttributes = [
            .paragraphStyle: paragraphStyle,
            .font: UIFont.systemFont(ofSize: 17),
            .foregroundColor: WTheme.primaryLabel,
        ]
        view.dataDetectorTypes = []
        view.returnKeyType = .next
        if #available(iOS 18.0, *) {
            view.writingToolsBehavior = .none
        }
        view.delegate = context.coordinator
        return view
    }
    
    public func updateUIView(_ view: UITextView, context: Context) {
        if value != view.text {
            view.text = value
        }
        if isFocused && !view.isFirstResponder {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if Date().timeIntervalSince(cooldown) > 0.2 { // make sure kb doesn't reappear when navigating away from screen
                    let ok = view.becomeFirstResponder()
                    if !ok {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01)  {
                            isFocused = false
                        }
                    }
                }
            }
        } else if !isFocused && view.isFirstResponder {
            let ok = view.resignFirstResponder()
            if !ok {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01)  {
                    isFocused = true
                }
            }
        }
    }
    
    public func sizeThatFits(_ proposal: ProposedViewSize, uiView view: UITextView, context: Context) -> CGSize? {
        switch proposal.width {
        case 0, nil:
            var size = view.intrinsicContentSize
            size.width = max(20, size.width)
            return size
        case .infinity:
            return CGSize(width: .infinity, height: view.intrinsicContentSize.height)
        case .some(let width):
            var size = view.sizeThatFits(.init(width: width, height: .infinity))
            size.width = max(20, width)
            return size
        }
    }
}
