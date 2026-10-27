import Testing
import UIKit
@testable import UIHome

struct HomeCardCarouselPoseTests {
    @Test func centeredAndDisabledCardsAreFlat() {
        for width: CGFloat in [248, 370, 450] {
            let centered = HomeCardCarouselPose.make(position: 0, width: width, enabled: true)
            #expect(abs(centered.transform.m13) < 0.000001)
            #expect(centered.offset == 0)
            let disabled = HomeCardCarouselPose.make(position: 1, width: width, enabled: false)
            #expect(CATransform3DIsIdentity(disabled.transform))
            #expect(disabled.offset == 0)
        }
    }

    @Test func coverFlowKeepsNeighborsAtTheSelectedEightPointGap() {
        let width: CGFloat = 370
        for position: CGFloat in [-1, 1] {
            let pose = HomeCardCarouselPose.make(position: position, width: width, enabled: true)
            let edge = -position * width / 2
            let t = pose.transform
            let projected = (edge * t.m11 + t.m41) / (edge * t.m14 + t.m44)
            let center = position * (width + 8) + pose.offset
            let gap = abs(center + projected) - width / 2
            #expect(abs(gap - 8) < 0.000001)
        }
    }
}
