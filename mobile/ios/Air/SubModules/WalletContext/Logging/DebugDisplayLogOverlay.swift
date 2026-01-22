import UIKit

#if DEBUG
private final class DebugDisplayLogOverlayViewController: UIViewController {
    let containerView = UIView()
    let textView = UITextView()
    var heightConstraint: NSLayoutConstraint?
    var lines: [String] = []
    let prefix = String(repeating: "\n", count: 5)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        containerView.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        containerView.layer.cornerRadius = 26
        containerView.layer.cornerCurve = .continuous
        containerView.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        containerView.translatesAutoresizingMaskIntoConstraints = false

        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.textColor = .white
        textView.font = UIFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        textView.textContainerInset = UIEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        textView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(containerView)
        containerView.addSubview(textView)

        heightConstraint = containerView.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: view.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            heightConstraint!,

            textView.topAnchor.constraint(equalTo: containerView.topAnchor),
            textView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        heightConstraint?.constant = view.bounds.height / 5
    }

    func setLines(_ newLines: [String]) {
        lines = newLines
        textView.text = prefix + newLines.joined(separator: "\n")
        scrollToBottom()
    }

    func appendLine(_ line: String, maxLines: Int) {
        lines.append(line)
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
        textView.text = prefix + lines.joined(separator: "\n")
        scrollToBottom()
    }

    func scrollToBottom() {
        textView.layoutIfNeeded()
        let y = max(0, textView.contentSize.height - textView.bounds.height + textView.contentInset.bottom)
        textView.setContentOffset(CGPoint(x: 0, y: y), animated: false)
    }
}

private final class DebugDisplayLogOverlay {
    static let shared = DebugDisplayLogOverlay()

    let formatter: DateFormatter
    let maxLines = 500
    var buffer: [String] = []
    var window: UIWindow?
    var viewController: DebugDisplayLogOverlayViewController?
    var isEnabled = false

    init() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.SSS"
        self.formatter = formatter
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            show()
        } else {
            hide()
        }
    }

    func append(_ message: String) {
        let line = "\(formatter.string(from: .now)) \(message)"
        buffer.append(line)
        if buffer.count > maxLines {
            buffer.removeFirst(buffer.count - maxLines)
        }
        guard isEnabled else { return }
        viewController?.appendLine(line, maxLines: maxLines)
    }

    func show() {
        guard !isEnabled else { return }
        isEnabled = true

        let vc = viewController ?? DebugDisplayLogOverlayViewController()
        viewController = vc

        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }

        let window = window ?? UIWindow(windowScene: scene)
        window.rootViewController = vc
        window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.statusBar.rawValue + 1)
        window.backgroundColor = .clear
        window.isUserInteractionEnabled = false
        window.frame = scene.screen.bounds
        window.isHidden = false
        self.window = window

        vc.setLines(buffer)
    }

    func hide() {
        isEnabled = false
        window?.isHidden = true
    }
}

public func setDisplayLogOverlayEnabled(_ enabled: Bool) {
    Task { @MainActor in
        DebugDisplayLogOverlay.shared.setEnabled(enabled)
    }
}

public func displayLog(_ message: String) {
    Task { @MainActor in
        DebugDisplayLogOverlay.shared.append(message)
    }
}
#else
public func setDisplayLogOverlayEnabled(_ enabled: Bool) { }
public func displayLog(_ message: String) { }
#endif
