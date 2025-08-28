
import SwiftUI


public extension Text {
    
    init(address: String) {
        let addressToDisplay = String(address.flatMap { char in [char, Character("\u{200B}")] }) // zero-width spaces
        self = Text(addressToDisplay)
    }
}
