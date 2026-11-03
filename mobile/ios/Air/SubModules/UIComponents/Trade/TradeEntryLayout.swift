import SwiftUI
import UIKit

/// Buy/Sell and Futures share native scrolling, keypad placement and responder handling.
public struct TradeEntryLayout<Content: View, Controls: View>: View {
    let editor: TradeEditor
    let hasText: Bool
    let navigationBarSpace: CGFloat
    let accessibilityPrefix: String
    let content: (CGFloat) -> Content
    let controls: Controls

    public init(editor: TradeEditor, hasText: Bool, navigationBarSpace: CGFloat = 64,
                accessibilityPrefix: String = "tokenTrade", @ViewBuilder content: @escaping (CGFloat) -> Content,
                @ViewBuilder controls: () -> Controls) {
        self.editor = editor
        self.hasText = hasText
        self.navigationBarSpace = navigationBarSpace
        self.accessibilityPrefix = accessibilityPrefix
        self.content = content
        self.controls = controls()
    }

    public var body: some View {
        TradeEntryContainer(layout: self)
            .ignoresSafeArea(.container, edges: [.top, .bottom])
            .ignoresSafeArea(.keyboard)
    }
}

private struct TradeEntryContainer<Content: View, Controls: View>: UIViewControllerRepresentable {
    let layout: TradeEntryLayout<Content, Controls>

    func makeUIViewController(context: Context) -> TradeEntryViewController<Content, Controls> {
        TradeEntryViewController(layout: layout)
    }

    func updateUIViewController(_ controller: TradeEntryViewController<Content, Controls>, context: Context) {
        controller.update(layout: layout)
    }
}

private struct TradeEntryContent<Content: View>: View {
    let content: Content
    let minimumHeight: CGFloat

    var body: some View {
        VStack(spacing: 16) { content }
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .top)
    }
}

final class TradeEntryViewController<Content: View, Controls: View>: UIViewController {
    let scrollView = UIScrollView()
    let keyboardPanel = UIView()
    let keypad: TradeKeypad
    private var layout: TradeEntryLayout<Content, Controls>
    private let contentController: UIHostingController<TradeEntryContent<Content>>
    private let controlsController: UIHostingController<Controls>
    private var keypadHeight: NSLayoutConstraint!
    private var bottomPadding: NSLayoutConstraint!
    private var metrics: Metrics?

    private struct Metrics: Equatable {
        let keypadHeight: CGFloat
        let bottomPadding: CGFloat
        let contentHeight: CGFloat
        let cardHeight: CGFloat
        var panelHeight: CGFloat { 24 + 52 + 16 + keypadHeight + bottomPadding }
    }

    init(layout: TradeEntryLayout<Content, Controls>) {
        self.layout = layout
        keypad = TradeKeypad(editor: layout.editor, accessibilityPrefix: layout.accessibilityPrefix)
        contentController = UIHostingController(rootView: TradeEntryContent(content: layout.content(200), minimumHeight: 0))
        controlsController = UIHostingController(rootView: layout.controls)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .air.headerBackground
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.delaysContentTouches = false
        scrollView.keyboardDismissMode = .none
        scrollView.accessibilityIdentifier = layout.accessibilityPrefix + ".content"
        if #available(iOS 26, *) {
            scrollView.topEdgeEffect.isHidden = true
            scrollView.bottomEdgeEffect.isHidden = true
        }
        keyboardPanel.backgroundColor = .air.pickerBackground
        keyboardPanel.layer.cornerRadius = 32
        keyboardPanel.layer.cornerCurve = .continuous
        keyboardPanel.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        keyboardPanel.accessibilityIdentifier = layout.accessibilityPrefix + ".keyboard"
        for subview in [scrollView, keyboardPanel] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        embed(contentController, in: scrollView)
        embed(controlsController, in: keyboardPanel)
        keypad.translatesAutoresizingMaskIntoConstraints = false
        keyboardPanel.addSubview(keypad)
        contentController.sizingOptions = .intrinsicContentSize
        let content = contentController.view!
        let controls = controlsController.view!
        let contentWidth = content.widthAnchor.constraint(equalTo: view.safeAreaLayoutGuide.widthAnchor)
        contentWidth.priority = .defaultHigh
        keypadHeight = keypad.heightAnchor.constraint(equalToConstant: 248)
        bottomPadding = keypad.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -36)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.contentLayoutGuide.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            content.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            content.widthAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.widthAnchor),
            content.widthAnchor.constraint(lessThanOrEqualToConstant: 560),
            contentWidth,
            keyboardPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboardPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboardPanel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            controls.topAnchor.constraint(equalTo: keyboardPanel.topAnchor, constant: 24),
            controls.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            controls.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            controls.heightAnchor.constraint(equalToConstant: 52),
            keypad.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 16),
            keypad.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            keypad.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            keypadHeight,
            bottomPadding,
        ])
        keypad.updateDelete(isEnabled: layout.hasText)
    }

    private func embed<T: View>(_ controller: UIHostingController<T>, in container: UIView) {
        addChild(controller)
        controller.view.backgroundColor = .clear
        if #available(iOS 16.4, *) { controller.safeAreaRegions = [] }
        else { controller.disableSafeArea() }
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(controller.view)
        controller.didMove(toParent: self)
    }

    func update(layout: TradeEntryLayout<Content, Controls>) {
        self.layout = layout
        controlsController.rootView = layout.controls
        keypad.updateDelete(isEnabled: layout.hasText)
        updateLayout()
        updateContent()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateLayout()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateLayout()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        view.endEditing(true)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if layout.editor.field?.focusesOnAppearance == true {
            layout.editor.field?.becomeFirstResponder()
        }
    }

    private func updateLayout() {
        guard isViewLoaded, view.bounds.height > 0, keypadHeight != nil else { return }
        let bottom = max(36, view.safeAreaInsets.bottom)
        let preferredContentHeight = 256 + layout.navigationBarSpace + 84
        let keys = min(248, max(176, view.bounds.height - preferredContentHeight - 92 - bottom))
        let availableContent = max(0, view.bounds.height - 92 - keys - bottom)
        let next = Metrics(keypadHeight: keys, bottomPadding: bottom, contentHeight: availableContent,
                           cardHeight: max(136 + layout.navigationBarSpace, availableContent - 84))
        guard next != metrics else { return }
        metrics = next
        keypadHeight.constant = keys
        bottomPadding.constant = -bottom
        scrollView.contentInset.bottom = next.panelHeight
        updateContent()
    }

    private func updateContent() {
        guard let metrics else { return }
        contentController.rootView = TradeEntryContent(content: layout.content(metrics.cardHeight), minimumHeight: metrics.contentHeight)
    }
}
