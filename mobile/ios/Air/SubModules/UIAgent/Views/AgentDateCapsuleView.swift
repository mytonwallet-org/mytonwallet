import UIKit
import UIComponents
import WalletContext

/// Telegram's date bubble over a chat's messages (`ChatMessageDateHeader`): the day in 13 pt medium text, 6 pt in from
/// the ends of a 22 pt capsule, with the header's 6 pt above and below it. The News feed heads each day's news with one,
/// and keeps the capsule of the day at its top stuck under its header while that day's news scroll under it.
final class AgentDateCapsuleView: UIView {
    /// Telegram's `chatDateSize`
    nonisolated static let height: CGFloat = 22
    /// The space Telegram's 34 pt date header keeps above and below its capsule
    nonisolated static let verticalSpacing: CGFloat = 6
    /// The least space between the capsule and the column's edges, as the chat's centred lines keep
    static let minimumColumnInset: CGFloat = 40
    /// Telegram's `chatDateInset`
    private static let horizontalInset: CGFloat = 6
    /// The least space between the text and the capsule's top and bottom once a larger text size makes it taller
    private static let minimumVerticalInset: CGFloat = 3
    /// Dates read in the text's own colour on every platform and theme, on Telegram's white fill by day and faint dark
    /// fill by night
    private static let textColor = UIColor.label
    private static let fillColor = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor.black.withAlphaComponent(0.2) : UIColor.white.withAlphaComponent(0.8)
    }
    /// The blur under a capsule that floats over the news, as under Telegram's
    private static let blurRadius: CGFloat = 20

    let label = UILabel()
    private let fillView = UIView()

    var text: String? {
        get { label.text }
        set { label.text = newValue }
    }

    /// `isBlurred` blurs what scrolls under the capsule, for one that stays over the news
    init(isBlurred: Bool = false) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = false
        clipsToBounds = true
        layer.cornerCurve = .continuous
        if isBlurred {
            let blurView = BackgroundBlurView(radius: Self.blurRadius)
            blurView.isUserInteractionEnabled = false
            addFilling(blurView)
        }
        fillView.backgroundColor = Self.fillColor
        fillView.isUserInteractionEnabled = false
        addFilling(fillView)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.applyTextStyle(.footnoteEmphasized, scaling: .dynamic)
        label.textColor = Self.textColor
        label.textAlignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.accessibilityTraits = [.staticText, .header]
        label.accessibilityIdentifier = "agent_date_capsule"
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalInset),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.horizontalInset),
            heightAnchor.constraint(equalToConstant: Self.height).withPriority(.defaultHigh),
            heightAnchor.constraint(greaterThanOrEqualToConstant: Self.height),
            heightAnchor.constraint(greaterThanOrEqualTo: label.heightAnchor, constant: 2 * Self.minimumVerticalInset),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }

    private func addFilling(_ view: UIView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: topAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor),
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }
}
