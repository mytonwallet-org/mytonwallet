
import SwiftUI
import UIKit

extension UIHostingController {
    convenience public init(rootView: Content, ignoreSafeArea: Bool) {
        self.init(rootView: rootView)
        
        if ignoreSafeArea {
            disableSafeArea()
        }
    }
    
    /// see discussion in `HostingView.swift`
    public func disableSafeArea() {
        _disableSafeAreaImpl(view: view)
    }
}
