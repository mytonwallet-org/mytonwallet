//
//  Created by Anton Spivak
//

#if DEBUG
import Foundation
import CoreText

@MainActor
final class CustomFontsProvider {
    // MARK: Internal

    static var isRegistered: Bool = false

    @inlinable @inline(__always)
    static func registerFonts() {
        guard !isRegistered else { return }
        isRegistered = true

        registerFont(named: "Nunito-ExtraBold", withExtension: "ttf")
        registerFont(named: "SFCompactDisplayMedium", withExtension: "otf")
        registerFont(named: "SFCompactRoundedBold", withExtension: "otf")
        registerFont(named: "SFCompactRoundedSemibold", withExtension: "otf")
    }

    @usableFromInline
    static func registerFont(named name: String, withExtension ext: String) {
        guard let url = bundle.url(forResource: name, withExtension: ext)
        else { fatalError("Couldn't locate \(name).\(ext) in bundle \(bundle)") }

        var error: Unmanaged<CFError>?
        guard !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        else { return }

        if let error {
            fatalError("Couldn't register font named \(name).\(ext): \(error.takeRetainedValue())")
        } else {
            fatalError("Couldn't register font named \(name).\(ext): Unknown error")
        }
    }

    // MARK: Private

    private static let bundle = Bundle(for: CustomFontsProvider.self)
}

#endif
