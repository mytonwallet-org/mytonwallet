
import SwiftUI
import UIKit


open class HostingView: UIView {
    
    open var contentView: UIView & UIContentView
    
    public init(ignoreSafeArea: Bool = true, @ViewBuilder content: () -> some View) {

        let configuration = UIHostingConfiguration(content: content)
            .margins(.all, 0)
        let contentView = configuration
            .makeContentView()
        self.contentView = contentView
        
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false        
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        
        if ignoreSafeArea {
            disableSafeArea()
        }
    }
    
    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override open func layoutSubviews() {
        super.layoutSubviews()
    }

    override open var intrinsicContentSize: CGSize {
        return super.intrinsicContentSize
    }

    override open func systemLayoutSizeFitting(_ targetSize: CGSize, withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority, verticalFittingPriority: UILayoutPriority) -> CGSize {
        return super.systemLayoutSizeFitting(targetSize, withHorizontalFittingPriority: horizontalFittingPriority, verticalFittingPriority: verticalFittingPriority)
    }
}

/// Fix for a bug:
///   1. place HostingView in scroll view,
///   2. scroll away
///   3. switch to other tab or lock phone
///   4. scroll hosting view back into view
///   5. view appears misaligned by 34 points (bottom safe area)
///
/// Reference:
///   - Found here: https://github.com/scenee/FloatingPanel/issues/454
///   - This solution: https://defagos.github.io/swiftui_collection_part3/
///   - Alternative:  https://x.com/b3ll/status/1193747288302075906
///   - Radar and mention for `_UIHostingView`: https://openradar.appspot.com/FB8176223
extension HostingView {
    public func disableSafeArea() {
        _disableSafeAreaImpl(view: contentView)
    }
}

func _disableSafeAreaImpl(view: UIView) {
    guard let viewClass = object_getClass(view) else { return }
    
    let viewSubclassName = String(cString: class_getName(viewClass)).appending("_IgnoreSafeArea")
    if let viewSubclass = NSClassFromString(viewSubclassName) {
        object_setClass(view, viewSubclass)
    }
    else {
        guard let viewClassNameUtf8 = (viewSubclassName as NSString).utf8String else { return }
        guard let viewSubclass = objc_allocateClassPair(viewClass, viewClassNameUtf8, 0) else { return }
        
        if let method = class_getInstanceMethod(UIView.self, #selector(getter: UIView.safeAreaInsets)) {
            let safeAreaInsets: @convention(block) (AnyObject) -> UIEdgeInsets = { _ in
                return .zero
            }
            class_addMethod(viewSubclass, #selector(getter: UIView.safeAreaInsets), imp_implementationWithBlock(safeAreaInsets), method_getTypeEncoding(method))
        }
        
        objc_registerClassPair(viewSubclass)
        object_setClass(view, viewSubclass)
    }
}
