import Testing
import UIKit
@testable import UIComponents

@MainActor
struct NavigationHeaderTests {
    @Test
    func `header uses a fallback until its navigation bar joins a window`() {
        let navigationBar = UINavigationBar(frame: CGRect(x: 0, y: 60, width: 320, height: 80))
        let container = UIView(frame: CGRect(x: 20, y: 5, width: 200, height: 60))
        let header = NavigationHeader2(frame: CGRect(x: 10, y: 10, width: 100, height: 20))
        navigationBar.addSubview(container)
        container.addSubview(header)

        #expect(header.window == nil)
        #expect(header.distanceFromNavigationBarBottomToContentCenter == 22)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.addSubview(navigationBar)
        #expect(header.window === window)
        #expect(header.distanceFromNavigationBarBottomToContentCenter == 55)

        navigationBar.removeFromSuperview()
        #expect(header.window == nil)
        #expect(header.distanceFromNavigationBarBottomToContentCenter == 22)
    }
}
