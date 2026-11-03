import UIKit
import UIComponents
import WalletContext

/// The line that ends a news post, in the feed and in its discussion alike: "Source • 15:38" in the bubble's trailing
/// corner, where Telegram puts a message's time
final class AgentNewsMetaView: UIStackView {
    /// The space under the line, to the bubble's end or to the discussion strip's separator
    static let bottomInset: CGFloat = 7
    private static let separator = "•\u{00a0}"

    let sourceLabel = UILabel()
    let timeLabel = UILabel()

    /// Makes the source open on a tap. Nil leaves it plain text.
    var onSourceTap: (() -> Void)? {
        didSet { sourceLabel.isUserInteractionEnabled = onSourceTap != nil }
    }

    init() {
        super.init(frame: .zero)
        axis = .horizontal
        alignment = .firstBaseline
        spacing = 4
        for label in [sourceLabel, timeLabel] {
            label.applyTextStyle(.caption, scaling: .dynamic)
            label.textColor = .air.secondaryLabel
            addArrangedSubview(label)
        }
        sourceLabel.lineBreakMode = .byTruncatingTail
        sourceLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        sourceLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        sourceLabel.isHidden = true
        sourceLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openSource)))
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        isAccessibilityElement = false
        accessibilityElementsHidden = true
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(source: String?, time: String) {
        sourceLabel.text = source
        sourceLabel.isHidden = source == nil
        timeLabel.text = source == nil ? time : Self.separator + time
    }

    func reset() {
        sourceLabel.text = nil
        sourceLabel.isHidden = true
        timeLabel.text = nil
        onSourceTap = nil
    }

    @objc private func openSource() {
        onSourceTap?()
    }

    /// The time of a news post in its discussion: the time alone for today's news, otherwise the date as well, as in
    /// "Jul 20, 15:38" or "20 июл, 15:38", with the year for a previous year's
    static func formatDiscussionTime(
        for timestamp: String,
        relativeTo now: Date = .now,
        calendar: Calendar = LocalizationSupport.shared.calendar,
        locale: Locale = LocalizationSupport.shared.locale
    ) -> String {
        let date = AgentV2DateParser.date(timestamp)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        if calendar.isDate(date, inSameDayAs: now) {
            formatter.setLocalizedDateFormatFromTemplate("jmm")
        } else {
            let isThisYear = calendar.isDate(date, equalTo: now, toGranularity: .year)
            formatter.setLocalizedDateFormatFromTemplate(isThisYear ? "MMMdjmm" : "yMMMdjmm")
            // Abbreviated months go without their trailing dot, as Telegram writes dates
            func removeDots(_ symbols: [String]) -> [String] {
                symbols.map { $0.hasSuffix(".") ? String($0.dropLast()) : $0 }
            }
            formatter.shortMonthSymbols = removeDots(formatter.shortMonthSymbols)
            formatter.shortStandaloneMonthSymbols = removeDots(formatter.shortStandaloneMonthSymbols)
        }
        return formatter.string(from: date)
    }
}
