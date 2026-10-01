import SwiftUI
import UIKit

private struct HorizontalContentMarginsKey: EnvironmentKey {
    static let defaultValue = EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
}

public extension EnvironmentValues {
    /// Outer content spacing inside SwiftUI's inherited safe area.
    var horizontalContentMargins: EdgeInsets {
        get { self[HorizontalContentMarginsKey.self] }
        set { self[HorizontalContentMarginsKey.self] = newValue }
    }
}

public struct LayoutMarginsContent<Content: View>: View {
    @Environment(\.layoutDirection) private var layoutDirection
    let content: Content
    var margins = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)

    init(content: Content) {
        self.content = content
    }

    public var body: some View {
        content.environment(\.horizontalContentMargins, EdgeInsets(
            top: 0,
            leading: layoutDirection == .rightToLeft ? margins.right : margins.left,
            bottom: 0,
            trailing: layoutDirection == .rightToLeft ? margins.left : margins.right
        ))
    }
}

/// Shares UIKit's resolved content margins without adding the safe area twice.
public final class LayoutMarginsHostingController<Content: View>: UIHostingController<LayoutMarginsContent<Content>> {
    public init(rootView: Content) {
        super.init(rootView: LayoutMarginsContent(content: rootView))
        view.insetsLayoutMarginsFromSafeArea = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateContentMargins()
    }

    public override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateContentMargins()
    }

    public override func viewLayoutMarginsDidChange() {
        super.viewLayoutMarginsDidChange()
        updateContentMargins()
    }

    private func updateContentMargins() {
        guard isViewLoaded else { return }
        let container = parent?.view ?? view!
        let safeArea = container.safeAreaInsets
        let margins = container.layoutMargins
        let contentMargins = UIEdgeInsets(
            top: 0,
            left: max(0, margins.left - safeArea.left),
            bottom: 0,
            right: max(0, margins.right - safeArea.right)
        )
        if rootView.margins != contentMargins {
            rootView.margins = contentMargins
        }
    }
}
