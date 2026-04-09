import SwiftUI
import UIKit

@available(iOS 16.0, *)
public extension ContextMenuCustomRow {
    @MainActor
    static func swiftUI<Content: View>(
        id: String = UUID().uuidString,
        preferredWidth: CGFloat? = nil,
        sizing: ContextMenuCustomRowSizing = .automatic(),
        interaction: ContextMenuCustomRowInteraction = .contentHandlesTouches,
        ignoreSafeArea: Bool = true,
        @ViewBuilder content: @escaping @MainActor (ContextMenuCustomRowContext) -> Content
    ) -> ContextMenuCustomRow {
        ContextMenuCustomRow(
            id: id,
            preferredWidth: preferredWidth,
            sizing: sizing,
            interaction: interaction
        ) { context in
            let rootView = content(context)
            return ContextMenuHostingView(ignoreSafeArea: ignoreSafeArea) {
                rootView
            }
        }
    }
}

@available(iOS 16.0, *)
private final class ContextMenuHostingView<Content: View>: UIView {
    private let contentView: UIView & UIContentView

    init(ignoreSafeArea: Bool, @ViewBuilder content: () -> Content) {
        let configuration = UIHostingConfiguration(content: content)
            .margins(.all, 0.0)
        let contentView = configuration.makeContentView()
        self.contentView = contentView

        super.init(frame: .zero)

        self.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: self.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: self.bottomAnchor)
        ])

        if ignoreSafeArea {
            self.disableSafeArea()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func disableSafeArea() {
        disableSafeAreaImpl(view: self.contentView)
    }
}

private func disableSafeAreaImpl(view: UIView) {
    guard let viewClass = object_getClass(view) else {
        return
    }

    let viewSubclassName = String(cString: class_getName(viewClass)).appending("_ContextMenuIgnoreSafeArea")
    if let viewSubclass = NSClassFromString(viewSubclassName) {
        object_setClass(view, viewSubclass)
    } else {
        guard let viewClassNameUtf8 = (viewSubclassName as NSString).utf8String else {
            return
        }
        guard let viewSubclass = objc_allocateClassPair(viewClass, viewClassNameUtf8, 0) else {
            return
        }

        if let method = class_getInstanceMethod(UIView.self, #selector(getter: UIView.safeAreaInsets)) {
            let safeAreaInsets: @convention(block) (AnyObject) -> UIEdgeInsets = { _ in
                .zero
            }
            class_addMethod(
                viewSubclass,
                #selector(getter: UIView.safeAreaInsets),
                imp_implementationWithBlock(safeAreaInsets),
                method_getTypeEncoding(method)
            )
        }

        objc_registerClassPair(viewSubclass)
        object_setClass(view, viewSubclass)
    }
}
