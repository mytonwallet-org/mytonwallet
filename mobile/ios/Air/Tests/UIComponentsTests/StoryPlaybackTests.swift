import Testing
import UIKit
@testable import UIComponents
import WalletResources

@Suite("Story playback")
struct StoryPlaybackTests {
    private func pages(_ durations: [TimeInterval] = [10, 10, 10]) -> [StoryPage] {
        durations.enumerated().map { index, duration in
            StoryPage(id: "\(index)", title: "Title", body: "Body", buttonTitle: "Next", duration: duration)
        }
    }

    @Test func progressStopsForEveryPauseReasonAndResumesAtTheSamePosition() {
        var state = StoryPlaybackState(pages: pages())
        #expect(state.advance(by: 3) == .none)
        #expect(state.elapsed == 0)
        state.setPaused(false, for: .hidden)
        #expect(state.advance(by: 3) == .none)
        #expect(state.progress == 0.3)
        for reason in [StoryPlaybackState.PauseReason.touch, .scrolling, .background, .voiceOver, .dismissal] {
            state.setPaused(true, for: reason)
            #expect(state.advance(by: 100) == .none)
            #expect(state.progress == 0.3)
            state.setPaused(false, for: reason)
        }
        #expect(state.advance(by: 7) == .page)
        #expect(state.index == 1)
        #expect(state.progress == 0)
    }

    @Test func overlappingPauseReasonsDoNotResumeEachOther() {
        var state = StoryPlaybackState(pages: pages())
        state.setPaused(false, for: .hidden)
        state.setPaused(true, for: .touch)
        state.setPaused(true, for: .background)
        state.setPaused(false, for: .touch)
        #expect(state.isPaused)
        #expect(state.advance(by: 20) == .none)
        state.setPaused(false, for: .background)
        #expect(!state.isPaused)
    }

    @Test func navigationRestartsPreviousPagesAndCompletesExactlyOnce() {
        var state = StoryPlaybackState(pages: pages())
        #expect(state.previous() == .page)
        #expect(state.index == 0)
        #expect(state.next() == .page)
        state.setPaused(false, for: .hidden)
        #expect(state.advance(by: 4) == .none)
        #expect(state.previous() == .page)
        #expect(state.index == 0)
        #expect(state.elapsed == 0)
        #expect(state.next() == .page)
        #expect(state.next() == .page)
        #expect(state.next() == .completed)
        #expect(state.isPaused)
        #expect(state.progress == 1)
        #expect(state.next() == .none)
        #expect(state.advance(by: 10) == .none)
    }

    @Test func delayedFramesNeverSkipUnreadPagesAndInvalidDurationsAreSafe() {
        let stories = pages([.nan, -.infinity, 0, -5])
        #expect(stories.allSatisfy { $0.duration == 10 })
        var state = StoryPlaybackState(pages: stories)
        state.setPaused(false, for: .hidden)
        #expect(state.advance(by: .infinity) == .none)
        #expect(state.advance(by: -3) == .none)
        #expect(state.advance(by: 60) == .page)
        #expect(state.index == 1)
        #expect(state.elapsed == 0)
        var empty = StoryPlaybackState(pages: [])
        empty.setPaused(false, for: .hidden)
        #expect(empty.isPaused)
        #expect(empty.next() == .none)
        #expect(empty.previous() == .none)
    }
}

@MainActor @Suite("Story layout", .serialized)
struct StoriesLayoutTests {
    init() { _ = WalletResourcesBundle.bundle.load() }

    @Test func geometryUsesSafeAreasAndLeavesControlsOutsideTheTextScroller() throws {
        let controller = StoriesViewController(pages: [
            .init(id: "intro", title: "Meet perpetual\nfutures", body: "Open positions on rising\nand falling prices.", buttonTitle: "Start"),
            .init(id: "next", title: "Next", body: "Body", buttonTitle: "Next"),
        ])
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        controller.additionalSafeAreaInsets = .init(top: 62, left: 0, bottom: 34, right: 0)
        controller.view.layoutIfNeeded()
        controller.viewDidLayoutSubviews()
        controller.view.layoutIfNeeded()
        let progress = try #require(find("Stories.Progress", in: controller.view))
        let close = try #require(find("Stories.Close", in: controller.view))
        let content = try #require(find("Stories.Content", in: controller.view))
        let next = try #require(find("Stories.Next", in: controller.view))
        let title = try #require(find("Stories.Title", in: controller.view) as? UILabel)
        let safeFrame = controller.view.safeAreaLayoutGuide.layoutFrame
        #expect(progress.frame == CGRect(x: safeFrame.minX + 24, y: safeFrame.minY + 4, width: safeFrame.width - 48, height: 3))
        #expect(close.frame == CGRect(x: safeFrame.maxX - 68, y: safeFrame.minY + 23, width: 44, height: 44))
        #expect(content.frame == CGRect(x: safeFrame.minX + 24, y: safeFrame.maxY - 239, width: safeFrame.width - 48, height: 233))
        #expect(next.bounds.height == 52)
        #expect(next.superview === content)
        #expect(title.accessibilityTraits.contains(.header))
        let paragraph = title.attributedText?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        #expect(paragraph?.alignment == .center)
        #expect(title.accessibilityCustomActions?.count == 2)
        #expect(progress.layer.sublayers?.count == 2)
        #expect(progress.layer.sublayers?.first?.bounds.height == 3)
        if #available(iOS 26, *) {
            for control in [next, close] {
                let button = try #require(control as? UIButton)
                let glass = try #require(button.subviews.first { $0 is UIVisualEffectView } as? UIVisualEffectView)
                let effect = try #require(glass.effect as? UIGlassEffect)
                #expect(effect.isInteractive)
                #expect(glass.cornerConfiguration != nil)
                #expect(glass.bounds.size == button.bounds.size)
                #expect(button.configuration?.background.visualEffect == nil)
            }
        }
    }

    @Test func longCopyCanScrollWhileTheActionRemainsVisible() throws {
        let controller = StoriesViewController(pages: [
            .init(id: "long", title: "A longer title", body: String(repeating: "Story content. ", count: 150), buttonTitle: "Next"),
        ])
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 320, height: 568)
        controller.additionalSafeAreaInsets = .init(top: 20, left: 0, bottom: 0, right: 0)
        controller.view.layoutIfNeeded()
        controller.viewDidLayoutSubviews()
        controller.view.layoutIfNeeded()
        let content = try #require(find("Stories.Content", in: controller.view))
        let scroll = try #require(content.subviews.first { $0 is UIScrollView } as? UIScrollView)
        let next = try #require(find("Stories.Next", in: controller.view))
        let close = try #require(find("Stories.Close", in: controller.view))
        #expect(content.frame.minY >= close.frame.maxY + 24)
        #expect(scroll.contentSize.height > scroll.bounds.height)
        #expect(next.convert(next.bounds, to: controller.view).maxY == controller.view.safeAreaLayoutGuide.layoutFrame.maxY - 6)
        #expect(next.isUserInteractionEnabled)
    }

    @Test func missingMediaPreservesTheBackdropAndReducedMotionPausesPlayback() throws {
        let backdrop = UIView()
        backdrop.backgroundColor = .blue
        let page = StoryPage(id: "static", title: "Static story", body: "Content", buttonTitle: "Next")
        let controller = StoriesViewController(pages: [page], backgroundView: backdrop)
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        controller.view.layoutIfNeeded()
        #expect(backdrop.superview === controller.view)
        #expect(backdrop.frame == controller.view.bounds)
        #expect(controller.view.layer.sublayers?.contains { ($0 as? CAGradientLayer)?.colors?.count == 3 } == true)
        let media = StoryMediaView(page: page)
        media.setPlaying(true, reduceMotion: false)
        #expect(media.isPlaybackRequested)
        media.setPlaying(true, reduceMotion: true)
        #expect(!media.isPlaybackRequested)
        media.setPlaying(false, reduceMotion: false)
        #expect(!media.isPlaybackRequested)
        #expect(media.backgroundColor == nil)
    }

    @Test func readingScrollableCopyPausesThroughDecelerationAndResetsOnNavigation() throws {
        let controller = StoriesViewController(pages: [
            .init(id: "long", title: "Title", body: String(repeating: "Story content. ", count: 150), buttonTitle: "Next"),
            .init(id: "next", title: "Next", body: "Body", buttonTitle: "Done"),
        ])
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 320, height: 568)
        controller.view.layoutIfNeeded()
        let content = try #require(find("Stories.Content", in: controller.view))
        let scroll = try #require(content.subviews.first { $0 is UIScrollView } as? UIScrollView)
        let hold = try #require(controller.view.gestureRecognizers?.first { $0 is UILongPressGestureRecognizer })
        let dismissPan = try #require(controller.view.gestureRecognizers?.first { $0 is UIPanGestureRecognizer })
        #expect(scroll.delegate === controller)
        #expect(!hold.cancelsTouchesInView)
        #expect(controller.gestureRecognizer(hold, shouldRecognizeSimultaneouslyWith: scroll.panGestureRecognizer))
        #expect(controller.gestureRecognizer(hold, shouldRecognizeSimultaneouslyWith: dismissPan))
        #expect(controller.gestureRecognizer(dismissPan, shouldRecognizeSimultaneouslyWith: hold))
        #expect(!controller.gestureRecognizer(dismissPan, shouldRecognizeSimultaneouslyWith: scroll.panGestureRecognizer))

        controller.scrollViewWillBeginDragging(scroll)
        #expect(controller.playback.pauseReasons.contains(.scrolling))
        controller.scrollViewDidEndDragging(scroll, willDecelerate: true)
        #expect(controller.playback.pauseReasons.contains(.scrolling))
        controller.scrollViewDidEndDecelerating(scroll)
        #expect(!controller.playback.pauseReasons.contains(.scrolling))

        controller.scrollViewWillBeginDragging(scroll)
        controller.scrollViewDidEndDragging(scroll, willDecelerate: false)
        #expect(!controller.playback.pauseReasons.contains(.scrolling))
        controller.scrollViewWillBeginDragging(scroll)
        controller.perform(NSSelectorFromString("nextPressed"))
        #expect(controller.playback.index == 1)
        #expect(!controller.playback.pauseReasons.contains(.scrolling))
    }

    @Test func slowDownwardDragsUseDirectionEvenWhenInstantaneousVelocityIsZero() {
        let controller = StoriesViewController(pages: [.init(id: "intro", title: "Title", body: "Body", buttonTitle: "Next")])
        controller.loadViewIfNeeded()
        let pan = StoryTestPan()
        pan.delta = CGPoint(x: 2, y: 15)
        #expect(controller.gestureRecognizerShouldBegin(pan))
        pan.delta = CGPoint(x: 15, y: 2)
        #expect(!controller.gestureRecognizerShouldBegin(pan))
        pan.delta = CGPoint(x: 2, y: -15)
        #expect(!controller.gestureRecognizerShouldBegin(pan))
        pan.delta = .zero
        #expect(!controller.gestureRecognizerShouldBegin(pan))
    }

    @Test(arguments: [false, true]) func horizontalSwipesNavigateInReadingOrder(isRTL: Bool) throws {
        let controller = StoriesViewController(pages: [
            .init(id: "intro", title: "Title", body: "Body", buttonTitle: "Start"),
            .init(id: "next", title: "Next", body: "Body", buttonTitle: "Next"),
        ])
        controller.loadViewIfNeeded()
        controller.view.semanticContentAttribute = isRTL ? .forceRightToLeft : .forceLeftToRight
        let swipes = controller.view.gestureRecognizers?.compactMap { $0 as? UISwipeGestureRecognizer } ?? []
        #expect(swipes.count == 2)
        #expect(swipes.contains { $0.direction == .left })
        #expect(swipes.contains { $0.direction == .right })
        let swipe = StoryTestSwipe()
        swipe.direction = isRTL ? .right : .left
        swipe.testState = .cancelled
        controller.perform(NSSelectorFromString("swiped:"), with: swipe)
        #expect(controller.playback.index == 0)
        swipe.testState = .ended
        controller.perform(NSSelectorFromString("swiped:"), with: swipe)
        #expect(controller.playback.index == 1)
        swipe.direction = isRTL ? .left : .right
        controller.perform(NSSelectorFromString("swiped:"), with: swipe)
        #expect(controller.playback.index == 0)
        #expect(!controller.playback.pauseReasons.contains(.dismissal))
        #expect(controller.view.transform == .identity)

        let content = try #require(find("Stories.Content", in: controller.view))
        let scroll = try #require(content.subviews.first { $0 is UIScrollView } as? UIScrollView)
        let hold = try #require(controller.view.gestureRecognizers?.first { $0 is UILongPressGestureRecognizer })
        let dismissPan = try #require(controller.view.gestureRecognizers?.first { $0 is UIPanGestureRecognizer })
        #expect(controller.gestureRecognizer(swipe, shouldRecognizeSimultaneouslyWith: scroll.panGestureRecognizer))
        #expect(controller.gestureRecognizer(swipe, shouldRecognizeSimultaneouslyWith: hold))
        #expect(!controller.gestureRecognizer(swipe, shouldRecognizeSimultaneouslyWith: dismissPan))
    }

    @Test func actionTitleAnimatesOnlyWhenTheTextChanges() async throws {
        let controller = StoriesViewController(pages: [
            .init(id: "intro", title: "Title", body: "Body", buttonTitle: "Start"),
            .init(id: "long", title: "Long", body: "Body", buttonTitle: "Next"),
            .init(id: "short", title: "Short", body: "Body", buttonTitle: "Next"),
            .init(id: "done", title: "Done", body: "Body", buttonTitle: "Got It"),
        ])
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.layoutIfNeeded()
        let button = try #require(find("Stories.Next", in: controller.view) as? WInteractiveGlassButton)
        #expect(button.glassTitleLabel.layer.animationKeys()?.isEmpty != false)
        try await Task.sleep(for: .milliseconds(30))
        controller.perform(NSSelectorFromString("nextPressed"))
        #expect(button.title(for: .normal) == "Next")
        if TradeMotion.enabled {
            let outgoing = try #require(button.glassContentView.subviews.compactMap { $0 as? UILabel }.first { $0.text == "Start" })
            #expect(!outgoing.isAccessibilityElement)
            for _ in 0..<5 {
                try await Task.sleep(for: .milliseconds(30))
                let oldOpacity = outgoing.layer.presentation()?.opacity ?? Float(outgoing.alpha)
                let newOpacity = button.glassTitleLabel.layer.presentation()?.opacity ?? Float(button.glassTitleLabel.alpha)
                #expect(oldOpacity + newOpacity > 0.8)
            }
        }
        try await Task.sleep(for: .milliseconds(350))
        #expect(button.glassContentView.subviews.compactMap { $0 as? UILabel }.count == 1)
        controller.perform(NSSelectorFromString("nextPressed"))
        #expect(button.glassTitleLabel.layer.animationKeys()?.isEmpty != false)
        #expect(button.glassContentView.subviews.compactMap { $0 as? UILabel }.count == 1)
        controller.perform(NSSelectorFromString("nextPressed"))
        #expect(button.title(for: .normal) == "Got It")
        let swipe = StoryTestSwipe()
        swipe.direction = .right
        controller.perform(NSSelectorFromString("swiped:"), with: swipe)
        #expect(button.title(for: .normal) == "Next")
        #expect(button.accessibilityLabel == "Next")
        #expect(button.glassTitleLabel.alpha == 1)
        #expect(button.glassTitleLabel.transform == .identity)
        let container = UIView(frame: window.bounds)
        window.addSubview(container)
        let restore = controller.liftTransitionAction(into: container)
        #expect(button.glassContentView.subviews.compactMap { $0 as? UILabel }.count == 1)
        #expect(button.glassTitleLabel.layer.animationKeys()?.isEmpty != false)
        restore()
    }

    private func find(_ identifier: String, in view: UIView) -> UIView? {
        if view.accessibilityIdentifier == identifier { return view }
        return view.subviews.lazy.compactMap { find(identifier, in: $0) }.first
    }
}

@MainActor private final class StoryTestPan: UIPanGestureRecognizer {
    var delta = CGPoint.zero
    override func translation(in view: UIView?) -> CGPoint { delta }
    override func velocity(in view: UIView?) -> CGPoint { .zero }
}

@MainActor private final class StoryTestSwipe: UISwipeGestureRecognizer {
    var testState: UIGestureRecognizer.State = .ended
    override var state: UIGestureRecognizer.State {
        get { testState }
        set { testState = newValue }
    }
}
