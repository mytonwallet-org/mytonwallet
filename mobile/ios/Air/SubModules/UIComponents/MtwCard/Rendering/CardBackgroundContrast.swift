import SwiftUI

/// Matches contrastOverlay.ts: sample the unadjusted text area and solve the overlay
/// against mean sRGB at 4.5:1. This runs only when the seed changes, never per frame.
@MainActor
enum CardBackgroundContrast {
    static func opacity(seed: CardBackgroundSeed, library: CardBackgroundLibrary) -> Double {
        guard seed.isStandard else { return 0 }
        let renderer = ImageRenderer(content: CardBackgroundArtwork(seed: seed, library: library).frame(width: 400, height: 232))
        renderer.scale = 1
        guard let image = renderer.cgImage else { return 1 }
        var pixels = [UInt8](repeating: 0, count: 400 * 232 * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: 400, height: 232, bitsPerComponent: 8, bytesPerRow: 400 * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: 400, height: 232))
            return true
        }
        guard rendered else { return 1 }
        var mean = SIMD3<Double>.zero
        for y in 68..<128 {
            for x in 74..<326 {
                let i = (y * 400 + x) * 4
                mean += SIMD3(Double(pixels[i]), Double(pixels[i + 1]), Double(pixels[i + 2]))
            }
        }
        mean /= Double(252 * 60 * 255)
        let dark = seed["Text"] == "Dark"
        let text: SIMD3<Double> = dark ? SIMD3(47, 50, 65) / 255 : SIMD3(repeating: 1)
        let overlay = dark ? 1.0 : 0.0
        let base = mean * 0.84 + SIMD3(repeating: overlay * 0.16)
        let blended = SIMD3<Double>((0..<3).map { index in
            base[index] < 0.5 ? 2 * base[index] * overlay : 1 - 2 * (1 - base[index]) * (1 - overlay)
        })
        func contrast(_ opacity: Double) -> Double {
            let a = luminance(base * (1 - opacity) + blended * opacity)
            let b = luminance(text)
            return (max(a, b) + 0.05) / (min(a, b) + 0.05)
        }
        if contrast(0) >= 4.5 { return 0 }
        if contrast(1) < 4.5 { return 1 }
        var low = 0.0, high = 1.0
        for _ in 0..<24 {
            let mid = (low + high) / 2
            if contrast(mid) >= 4.5 { high = mid } else { low = mid }
        }
        return high
    }

    private static func luminance(_ rgb: SIMD3<Double>) -> Double {
        let linear = (0..<3).map { rgb[$0] <= 0.04045 ? rgb[$0] / 12.92 : pow((rgb[$0] + 0.055) / 1.055, 2.4) }
        return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
    }
}
