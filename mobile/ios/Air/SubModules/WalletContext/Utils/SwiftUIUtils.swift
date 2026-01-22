//
//  Created by Anton Spivak
//

import Foundation
import SwiftUI

#if DEBUG
public extension ProcessInfo {
    static var isXcodePreview: Bool {
        processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
}
#endif

@MainActor
public func withRegisteredCustomFontsForPreviewsIfNeeded<Content>(
    @ViewBuilder _ content: () -> Content
) -> some View where Content: View {
    #if DEBUG
    if ProcessInfo.isXcodePreview {
        CustomFontsProvider.registerFonts()
    }
    #endif
    return content()
}
