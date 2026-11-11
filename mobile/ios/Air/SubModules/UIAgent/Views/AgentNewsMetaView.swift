import UIKit
import UIComponents
import WalletContext

/// The line that ends a news post, in the feed and in its discussion alike: the post's time in the bubble's trailing
/// corner, where Telegram puts a message's time
final class AgentNewsMetaView: UIStackView {
    /// The space under the line, to the bubble's end or to the discussion strip's separator
    static let bottomInset: CGFloat = 7
    /// How far the time ends from the bubble's trailing edge, the same on iOS, Android and the web
    static let trailingInset: CGFloat = 12

    let timeLabel = UILabel()

    init() {
        super.init(frame: .zero)
        axis = .horizontal
        alignment = .firstBaseline
        timeLabel.applyTextStyle(.caption, scaling: .dynamic)
        timeLabel.textColor = .air.secondaryLabel
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        addArrangedSubview(timeLabel)
        isAccessibilityElement = false
        accessibilityElementsHidden = true
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(time: String) {
        timeLabel.text = time
    }

    func reset() {
        timeLabel.text = nil
    }

    /// The time of a news post in its discussion: the time alone for today's news, otherwise the date as well, as in
    /// "Jul 20, 15:38" or "20 июл, 15:38", with the year for a previous year's. The time is on the clock `hourCycle`
    /// names, the device's 12- or 24-hour clock by default, as on the feed's cards.
    static func formatDiscussionTime(
        for timestamp: String,
        relativeTo now: Date = .now,
        calendar: Calendar = LocalizationSupport.shared.calendar,
        locale: Locale = LocalizationSupport.shared.locale,
        hourCycle: Locale.HourCycle = Locale.autoupdatingCurrent.hourCycle
    ) -> String {
        let date = AgentV2DateParser.date(timestamp)
        let template: String
        if calendar.isDate(date, inSameDayAs: now) {
            template = "jmm"
        } else {
            template = calendar.isDate(date, equalTo: now, toGranularity: .year) ? "MMMdjmm" : "yMMMdjmm"
        }
        var components = Locale.Components(locale: locale)
        components.hourCycle = hourCycle
        return AgentThreadDateFormatting.makeDotlessFormatter(
            template: template,
            calendar: calendar,
            locale: Locale(components: components)
        )
        .string(from: date)
    }
}
