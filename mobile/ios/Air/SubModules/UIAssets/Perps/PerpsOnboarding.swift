import UIComponents
import UIKit
import WalletContext

@MainActor public enum PerpsOnboarding {
    public static let bannerID = "perps-onboarding"

    public static func makeViewController() -> StoriesViewController {
        StoriesViewController(pages: pages(), backgroundView: PerpsStoryBackgroundView())
    }

    static func pages() -> [StoryPage] {
        [
            .init(id: "intro", title: lang("PerpsStoryIntroTitle"), body: lang("PerpsStoryIntroBody"), buttonTitle: lang("PerpsStoryStart")),
            .init(id: "long", title: lang("PerpsStoryLongTitle"), body: lang("PerpsStoryLongBody"), buttonTitle: lang("Next")),
            .init(id: "short", title: lang("PerpsStoryShortTitle"), body: lang("PerpsStoryShortBody"), buttonTitle: lang("Next")),
            .init(id: "leverage", title: lang("PerpsStoryLeverageTitle"), body: lang("PerpsStoryLeverageBody"), buttonTitle: lang("Next")),
            .init(id: "liquidation", title: lang("PerpsStoryLiquidationTitle"), body: lang("PerpsStoryLiquidationBody"), buttonTitle: lang("Next")),
            .init(id: "funding", title: lang("PerpsStoryFundingTitle"), body: lang("PerpsStoryFundingBody"), buttonTitle: lang("Got It")),
        ]
    }
}

private final class PerpsStoryBackgroundView: UIView {
    private let glow = UIImageView(image: .airBundleOptional("PerpsStoryGlow"))

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        glow.contentMode = .scaleAspectFit
        addSubview(glow)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = bounds.width / 402
        glow.frame = CGRect(x: (bounds.width - 515 * scale) / 2, y: 0.5 * scale, width: 515 * scale, height: 629 * scale)
    }
}
