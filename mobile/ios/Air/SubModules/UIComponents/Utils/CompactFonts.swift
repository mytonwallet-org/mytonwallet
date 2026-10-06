import CoreText
import os
import SwiftUI
import UIKit

public enum CompactDisplayWeight {
    case medium
}

public enum CompactRoundedWeight {
    case bold
}

public extension UIFont {
    class func compactDisplay(ofSize size: CGFloat, weight: CompactDisplayWeight) -> UIFont {
        switch weight {
        case .medium: CompactSystemFont.display.font(ofSize: size)
        }
    }

    class func compactRounded(ofSize size: CGFloat, weight: CompactRoundedWeight) -> UIFont {
        switch weight {
        case .bold: CompactSystemFont.rounded.font(ofSize: size)
        }
    }
}

public extension Font {
    static func compactDisplay(size: CGFloat, weight: CompactDisplayWeight) -> Font {
        Font(UIFont.compactDisplay(ofSize: size, weight: weight))
    }

    static func compactRounded(size: CGFloat, weight: CompactRoundedWeight) -> Font {
        Font(UIFont.compactRounded(ofSize: size, weight: weight))
    }
}

// Also compiled by the widget targets, without a dependency on UIComponents.
// Stored values are immutable; Core Text descriptors can be shared across threads.
private struct CompactSystemFont: @unchecked Sendable {
    // Match the former static fonts instead of letting optical sizing change with point size.
    static let display = CompactSystemFont(
        file: "SFCompact.ttf", name: ".SFCompact-Medium", opticalSize: 20,
        fallbackWeight: .medium, fallbackDesign: .default
    )
    static let rounded = CompactSystemFont(
        file: "SFCompactRounded.ttf", name: ".SFCompactRounded-Bold", opticalSize: "none",
        fallbackWeight: .bold, fallbackDesign: .rounded
    )

    private let descriptor: CTFontDescriptor?
    private let fallbackWeight: UIFont.Weight
    private let fallbackDesign: UIFontDescriptor.SystemDesign

    private init(file: String, name: String, opticalSize: Any,
                 fallbackWeight: UIFont.Weight, fallbackDesign: UIFontDescriptor.SystemDesign) {
        self.fallbackWeight = fallbackWeight
        self.fallbackDesign = fallbackDesign
        descriptor = Self.loadDescriptor(file: file, name: name, opticalSize: opticalSize)
        if descriptor == nil {
            Logger(subsystem: "org.mytonwallet", category: "CompactFonts")
                .error("System font \(name, privacy: .public) unavailable; using fallback")
        }
    }

    func font(ofSize size: CGFloat) -> UIFont {
        if let descriptor {
            return CTFontCreateWithFontDescriptor(descriptor, size, nil) as UIFont
        }
        let systemFont = UIFont.systemFont(ofSize: size, weight: fallbackWeight)
        let descriptor = systemFont.fontDescriptor.withDesign(fallbackDesign) ?? systemFont.fontDescriptor
        return UIFont(descriptor: descriptor, size: size)
    }

    private static func loadDescriptor(file: String, name: String, opticalSize: Any) -> CTFontDescriptor? {
        var root = ""
        #if targetEnvironment(simulator)
        root = ProcessInfo.processInfo.environment["SIMULATOR_ROOT"] ?? ""
        #endif

        // These OS file locations and face names are undocumented. Keep them isolated here.
        for directory in ["Core", "Watch"] {
            let url = URL(fileURLWithPath: root + "/System/Library/Fonts/\(directory)/\(file)")
            guard FileManager.default.fileExists(atPath: url.path),
                  let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
                  let source = descriptors.first(where: {
                      CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String == name
                  }) else { continue }
            let descriptor = CTFontDescriptorCreateCopyWithAttributes(
                source, [kCTFontOpticalSizeAttribute as String: opticalSize] as CFDictionary
            )
            let font = CTFontCreateWithFontDescriptor(descriptor, 17, nil)
            guard CTFontCopyPostScriptName(font) as String == name else { continue }
            return descriptor
        }
        return nil
    }
}
