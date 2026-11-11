import UIComponents
import UIKit
import WalletContext
import WalletCore

private let STORY_IDS = ["intro", "long", "short", "leverage", "liquidation", "funding", "finale"]

@MainActor public enum PerpsOnboarding {
    public static let bannerID = "perps-onboarding"

    public static func makeViewController(onboarding: ApiPerpsOnboarding? = nil) -> StoriesViewController {
        let controller = StoriesViewController(pages: pages(onboarding: onboarding), backgroundView: PerpsStoryBackgroundView())
        controller.preferredContentSize = CGSize(width: 402, height: 874)
        return controller
    }

    static func pages(onboarding: ApiPerpsOnboarding? = nil, cache: PerpsStoryMediaCache = .shared) -> [StoryPage] {
        STORY_IDS.map { id in
            let name = "PerpsStory" + id.capitalized
            let story = onboarding?.stories.first { $0.id == id }
            let still = UIImage.airBundleOptional(name)
            let preview = story.flatMap { cache.cachedFile(for: $0.preview) }.flatMap { UIImage(contentsOfFile: $0.path) }
            let body = id == "finale" ? L10n.perpsstoryfinalebody(appName: APP_NAME) : lang(name + "Body")
            return .init(id: id, title: lang(name + "Title"), body: body,
                         buttonTitle: id == "finale" ? lang("PerpsStoryViewMarkets") : nil,
                         duration: story?.duration ?? 7, image: preview ?? still, reducedMotionImage: still,
                         videoURL: story.map { cache.cachedFile(for: $0.url) ?? $0.url })
        }
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
