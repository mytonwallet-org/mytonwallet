
import UIKit

// UIKit trees contain many unrelated classes. Objective-C conformance checks avoid
// Swift's cold conformance scan for every class during an account/privacy refresh.
@MainActor @objc public protocol WSensitiveDataProtocol {
    func updateSensitiveData()
}
