//
//  LaunchSplashGeometry.swift
//  AirAsFramework
//
//  Shared geometry of the launch ribbon (the app icon logo).
//  CoreGraphics-only on purpose: `Air/scripts/launch_splash/make_launch_splash_assets.sh`
//  compiles this file on macOS to cut the ribbon pieces out of `AppIcon.icon` and to render
//  the launch storyboard images, so the first animated frame matches the launch screen exactly.
//

import CoreGraphics

enum LaunchSplashGeometry {

    /// Pixels per icon unit in the piece images (cut at the icon's native 1024 px).
    static let pieceImagePixelsPerUnit: CGFloat = 2

    /// Where the icon art (512×512 units) sits on screen: icon width = screen width, centered.
    struct Layout {
        /// Points per icon unit.
        var scale: CGFloat
        /// Icon center, in points.
        var center: CGPoint
        var screenSize: CGSize

        init(screenSize: CGSize) {
            self.screenSize = screenSize
            scale = screenSize.width / 512
            center = CGPoint(x: screenSize.width / 2, y: screenSize.height / 2)
        }

        func point(_ unit: CGPoint) -> CGPoint {
            CGPoint(x: center.x + (unit.x - 256) * scale, y: center.y + (unit.y - 256) * scale)
        }
    }

    enum Extension {
        case none
        /// The art's bottom row is stretched down past the screen edge.
        case down
        /// The art's top row is stretched up past the screen edge.
        case up
    }

    struct Piece {
        /// Asset name of the piece image in the app's asset catalog.
        var imageName: String
        /// Where the piece image sits, in icon units (y down).
        var rect: CGRect
        /// Direction the trim travels through this piece (unit vector).
        var direction: CGVector
        /// Extent of the art along `direction`, measured from `rect`'s center, in units.
        var trimStart: CGFloat
        var trimEnd: CGFloat
        var extends: Extension
    }

    private static let up = CGVector(dx: 0, dy: -1)
    private static let diagonal = CGVector(dx: 0.4805, dy: 0.8770)

    /// Ribbon pieces in trim order: left strip, first fold, middle strip, second fold, right strip.
    /// Trim extents are measured from the art by the assets script.
    static let pieces: [Piece] = [
        Piece(imageName: "LaunchRibbonV1", rect: CGRect(x: 110, y: 168, width: 80, height: 332), direction: up, trimStart: -165.8, trimEnd: 158.2, extends: .down),
        Piece(imageName: "LaunchRibbonD1", rect: CGRect(x: 122, y: 170, width: 160, height: 224), direction: diagonal, trimStart: -113.8, trimEnd: 111.6, extends: .none),
        Piece(imageName: "LaunchRibbonV2", rect: CGRect(x: 218, y: 118, width: 80, height: 278), direction: up, trimStart: -128.8, trimEnd: 130.8, extends: .none),
        Piece(imageName: "LaunchRibbonD2", rect: CGRect(x: 230, y: 120, width: 160, height: 224), direction: diagonal, trimStart: -113.4, trimEnd: 112.1, extends: .none),
        Piece(imageName: "LaunchRibbonV3", rect: CGRect(x: 326, y: 12, width: 80, height: 332), direction: up, trimStart: -158.2, trimEnd: 165.8, extends: .up),
    ]

    /// Fold outlines from `AppIcon.icon/Assets/Foreground 3.svg`, in icon units.
    static let foldOutlines: [CGPath] = [
        svgPath("M151.218 180.762C144.118 184.044 140.568 185.685 138.038 187.74C130.152 194.148 126.722 204.563 129.256 214.403C130.069 217.559 131.949 220.989 135.709 227.848L177.75 304.533L212.199 367.371C215.067 372.602 216.595 375.388 218.282 377.406L218.321 377.452C218.426 377.577 218.532 377.699 218.639 377.818C224.345 384.194 233.015 387.05 241.393 385.313C244.091 384.754 246.987 383.415 252.781 380.737C259.882 377.456 263.432 375.815 265.961 373.759C273.847 367.352 277.277 356.937 274.743 347.097C273.93 343.941 272.05 340.511 268.29 333.652L226.25 256.968L191.8 194.129C188.935 188.902 187.407 186.124 185.721 184.106L185.692 184.071C185.582 183.939 185.472 183.806 185.361 183.681C179.654 177.306 170.985 174.45 162.607 176.187C159.909 176.746 157.012 178.085 151.218 180.762Z"),
        svgPath("M259.214 131.266C252.114 134.547 248.564 136.188 246.034 138.244C238.149 144.652 234.718 155.066 237.252 164.906C238.065 168.063 239.945 171.492 243.705 178.351L285.746 255.036L320.195 317.874C323.063 323.105 324.591 325.891 326.278 327.909L326.317 327.956C326.422 328.081 326.528 328.203 326.635 328.322C332.341 334.698 341.011 337.553 349.389 335.817C352.087 335.258 354.984 333.919 360.777 331.241C367.878 327.959 371.428 326.318 373.957 324.263C381.843 317.855 385.274 307.441 382.739 297.601C381.927 294.444 380.046 291.015 376.286 284.156L334.246 207.471L299.796 144.633C296.931 139.405 295.403 136.627 293.717 134.609L293.688 134.574C293.578 134.443 293.468 134.309 293.357 134.185C287.65 127.809 278.981 124.953 270.603 126.69C267.905 127.249 265.008 128.588 259.214 131.266Z"),
    ]

    /// Moving end of a trimmed strip: the bottom tip of the middle strip (its art alpha),
    /// cut out by the assets script. Its top row is full strip width and gets stretched.
    static let tipImageName = "LaunchRibbonTip"
    /// Tip image rect in icon units; its bottom is the middle strip's lowest point.
    static let tipRect = CGRect(x: 218, y: 306, width: 80, height: 80)

    /// Folds sit behind the strips, like in the icon (Foreground 5 below Foreground 1).
    static let drawOrder = [1, 3, 0, 2, 4]

    /// Background: the icon gradient (Display P3, sampled from the rendered app icon) from the
    /// screen top to the bottom, as an image shared by the launch storyboard and the splash.
    static let backgroundImageName = "LaunchBackgroundGradient"
    static let backgroundTopP3: (r: CGFloat, g: CGFloat, b: CGFloat) = (0.320, 0.700, 0.973)
    static let backgroundBottomP3: (r: CGFloat, g: CGFloat, b: CGFloat) = (0.170, 0.398, 0.940)

    /// The whole logo inside the icon square, for the launch storyboard.
    static let logoImageName = "LaunchLogo"
    /// The left strip's bottom row and the right strip's top row, stretched outside the icon
    /// square to the screen edges by the launch storyboard.
    static let stripExtensionImageName = "LaunchStripExtension"
    static let stripExtensionTopImageName = "LaunchStripExtensionTop"

    /// Piece rect in points, extended past the screen edges.
    static func screenRect(of piece: Piece, layout: Layout) -> CGRect {
        let origin = layout.point(piece.rect.origin)
        var rect = CGRect(x: origin.x, y: origin.y, width: piece.rect.width * layout.scale, height: piece.rect.height * layout.scale)
        let overshoot = piece.rect.width * layout.scale
        switch piece.extends {
        case .none:
            break
        case .down:
            rect.size.height = max(rect.height, layout.screenSize.height + overshoot - rect.minY)
        case .up:
            let top = -overshoot
            if top < rect.minY {
                rect.size.height += rect.minY - top
                rect.origin.y = top
            }
        }
        return rect
    }

    /// Trim line through the piece in points: from where the trim starts to where it ends.
    /// Extended pieces start (or end) at the far edge of their extension.
    static func trimLine(of piece: Piece, screenRect: CGRect, layout: Layout) -> (start: CGPoint, end: CGPoint) {
        let mid = layout.point(CGPoint(x: piece.rect.midX, y: piece.rect.midY))
        let scale = layout.scale
        let d = piece.direction
        var start = CGPoint(x: mid.x + d.dx * piece.trimStart * scale, y: mid.y + d.dy * piece.trimStart * scale)
        var end = CGPoint(x: mid.x + d.dx * piece.trimEnd * scale, y: mid.y + d.dy * piece.trimEnd * scale)
        switch piece.extends {
        case .none:
            break
        case .down:
            start.y = screenRect.maxY
        case .up:
            end.y = screenRect.minY
        }
        return (start, end)
    }

    /// Minimal parser for absolute M/L/C/Z SVG path data.
    static func svgPath(_ d: String) -> CGPath {
        var tokens: [String] = []
        var current = ""
        for character in d {
            if "MLCZ".contains(character) {
                if !current.isEmpty { tokens.append(current); current = "" }
                tokens.append(String(character))
            } else if character == " " || character == "," {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { tokens.append(current) }

        let path = CGMutablePath()
        var index = 0
        var command = ""
        func number() -> CGFloat {
            defer { index += 1 }
            return CGFloat(Double(tokens[index]) ?? 0)
        }
        func point() -> CGPoint { CGPoint(x: number(), y: number()) }
        while index < tokens.count {
            if "MLCZ".contains(tokens[index]) {
                command = tokens[index]
                index += 1
            }
            switch command {
            case "M": path.move(to: point())
            case "L": path.addLine(to: point())
            case "C":
                let c1 = point(), c2 = point()
                path.addCurve(to: point(), control1: c1, control2: c2)
            case "Z": path.closeSubpath(); command = ""
            default: index += 1
            }
        }
        return path
    }
}
