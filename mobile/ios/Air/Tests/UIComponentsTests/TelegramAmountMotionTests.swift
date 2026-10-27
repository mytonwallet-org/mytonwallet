import CoreText
import Testing
import UIKit
@testable import UIComponents

@MainActor @Suite("Telegram amount typing motion")
struct TelegramAmountMotionTests {
    private func glyphs(_ text: String, size: CGFloat = 72) -> [TelegramAmountGlyph] {
        TelegramAmountGlyph.text(NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: size, weight: .bold), .foregroundColor: UIColor.label
        ]), origin: CGPoint(x: 0, y: 70), group: .integer)
    }

    @Test(arguments: [("0", "27.01"), ("0", "1210.31"), ("27.01", "0"), ("100", "0"), ("27.01", "13.505")])
    func `bulk replacements use one motion and never carry a zero across the amount`(_ before: String, _ after: String) throws {
        let motion = TelegramAmountMotion(liquid: true)
        let source = glyphs(before), target = glyphs(after)
        motion.update(source, width: 350, timing: nil, at: 0)
        motion.update(target, width: 350,
            timing: TelegramAmountMotionTiming(spin: false, up: true, start: 1, replacesValue: true), at: 1)
        #expect(motion.frame(at: 1).map(\.glyph) == source)
        for frame in 1...38 {
            let sprites = motion.frame(at: 1 + Double(frame) / 120)
            #expect(sprites.allSatisfy { $0.morph == nil })
            #expect(sprites.allSatisfy { source.contains($0.glyph) || target.contains($0.glyph) })
            let arriving = sprites.filter { target.contains($0.glyph) }
            if let first = arriving.first {
                #expect(arriving.count == target.count)
                #expect(arriving.allSatisfy { $0.alpha == first.alpha && $0.scale == first.scale })
            }
        }
        #expect(motion.frame(at: 2).map(\.glyph) == target)
    }

    @Test(arguments: [false, true])
    func `interrupting a bulk replacement preserves the visible frame and settles the latest edit`(_ anotherBulkEdit: Bool) throws {
        let motion = TelegramAmountMotion(liquid: true)
        motion.update(glyphs("0"), width: 350, timing: nil, at: 0)
        motion.update(glyphs("27.01"), width: 350,
            timing: TelegramAmountMotionTiming(spin: false, up: true, start: 1, replacesValue: true), at: 1)
        let before = motion.frame(at: 1.1)
        let target = glyphs(anotherBulkEdit ? "0" : "27.012")
        motion.update(target, width: 350,
            timing: TelegramAmountMotionTiming(spin: false, up: true, start: 1.1, replacesValue: anotherBulkEdit), at: 1.1)
        let after = motion.frame(at: 1.1)
        #expect(before.count == after.count)
        func baseline(_ sprite: TelegramAmountSprite) -> CGFloat {
            sprite.glyph.position.y + (sprite.scalesFromBaseline ? 0 : sprite.glyph.font.capHeight / 2 * (sprite.scale - 1))
        }
        for a in before {
            let b = try #require(after.first { $0.glyph.text == a.glyph.text && abs($0.glyph.position.x - a.glyph.position.x) < 0.001 })
            #expect(abs(baseline(a) - baseline(b)) < 0.001)
            #expect(abs(a.alpha - b.alpha) < 0.001)
            #expect(abs(a.scale - b.scale) < 0.001)
            #expect(abs(a.spread - b.spread) < 0.001)
        }
        #expect(motion.frame(at: 2).map(\.glyph) == target)
    }

    @Test func `typing after Max lets the existing digits finish arriving without replaying the replacement`() throws {
        let motion = TelegramAmountMotion(liquid: true)
        motion.update(glyphs("0"), width: 350, timing: nil, at: 0)
        motion.update(glyphs("27.01"), width: 350,
            timing: TelegramAmountMotionTiming(spin: false, up: true, start: 1, replacesValue: true), at: 1)
        var opacity = try #require(motion.frame(at: 1.1).first { $0.glyph.text == "2" }).alpha
        for (index, amount) in ["27.012", "27.0123", "27.01234"].enumerated() {
            let time = 1.1 + Double(index) * 0.07
            motion.update(glyphs(amount), width: 350,
                timing: TelegramAmountMotionTiming(spin: false, up: true, start: time), at: time)
            let digit = try #require(motion.frame(at: time + 0.06).first { $0.glyph.text == "2" })
            #expect(digit.alpha > opacity)
            opacity = digit.alpha
        }
        #expect(motion.frame(at: 2).map(\.glyph) == glyphs("27.01234"))
    }

    @Test(arguments: [false, true])
    func `unchanged digits resize without replacement or rolling`(_ spin: Bool) throws {
        let motion = TelegramAmountMotion(liquid: true)
        motion.update(glyphs("123"), width: 300, timing: nil, at: 0)
        let target = glyphs("123", size: 48)
        motion.update(target, width: 300,
            timing: TelegramAmountMotionTiming(spin: spin, up: true, start: 1), at: 1)
        var previousSize: CGFloat = 72
        for frame in 0...60 {
            let sprites = motion.frame(at: 1 + Double(frame) / 120)
            #expect(sprites.map(\.glyph.text) == ["1", "2", "3"])
            #expect(sprites.allSatisfy { $0.morph == nil && $0.alpha == 1 })
            let first = try #require(sprites.first)
            let size = first.glyph.font.pointSize * first.scale
            #expect(size <= previousSize + 0.001)
            #expect(size >= 48 - 0.001)
            previousSize = size
        }
        #expect(motion.frame(at: 2).map(\.glyph) == target)
    }

    @Test func `typing through a resize preserves the visible size and opacity`() throws {
        let motion = TelegramAmountMotion(liquid: true)
        motion.update(glyphs("123"), width: 300, timing: nil, at: 0)
        motion.update(glyphs("1234", size: 60), width: 300,
            timing: TelegramAmountMotionTiming(spin: false, up: true, start: 1), at: 1)
        let before = try #require(motion.frame(at: 1.06).first)
        let inserted = try #require(motion.frame(at: 1.06).first(where: { $0.glyph.text == "4" }))
        #expect(inserted.glyph.font.pointSize == 60)
        motion.update(glyphs("12345", size: 48), width: 300,
            timing: TelegramAmountMotionTiming(spin: false, up: true, start: 1.06), at: 1.06)
        let after = try #require(motion.frame(at: 1.06).first)
        #expect(abs(before.glyph.font.pointSize * before.scale - after.glyph.font.pointSize * after.scale) < 0.001)
        #expect(abs(before.glyph.position.x - after.glyph.position.x) < 0.001)
        for frame in 0...60 {
            let first = try #require(motion.frame(at: 1.06 + Double(frame) / 120).first)
            #expect(first.glyph.text == "1")
            #expect(first.morph == nil)
            #expect(first.alpha == 1)
        }
    }

    @Test(arguments: [("19", "14"), ("0", "1")])
    func `resizing during a morph preserves both masks across repeated edits`(_ original: String, _ replacement: String) throws {
        let motion = TelegramAmountMotion(liquid: true)
        motion.update(glyphs(original), width: 300, timing: nil, at: 0)
        motion.update(glyphs(replacement), width: 300,
            timing: TelegramAmountMotionTiming(spin: false, up: true, start: 1), at: 1,
            fromPlaceholder: original == "0")
        for (time, size, text) in [(1.04, CGFloat(60), replacement + "3"), (1.06, CGFloat(48), replacement + "32")] {
            let before = try #require(motion.frame(at: time).first(where: { $0.morph != nil }))
            let beforeMorph = try #require(before.morph)
            motion.update(glyphs(text, size: size), width: 300,
                timing: TelegramAmountMotionTiming(spin: false, up: true, start: time), at: time)
            let after = try #require(motion.frame(at: time).first(where: { $0.morph != nil }))
            let afterMorph = try #require(after.morph)
            // The Metal morph renderer uses the two font masks directly, without sprite.scale.
            #expect(after.glyph.font == before.glyph.font)
            #expect(after.glyph.text == before.glyph.text)
            #expect(afterMorph.from.font == beforeMorph.from.font)
            #expect(afterMorph.from.text == beforeMorph.from.text)
            #expect(afterMorph.progress == beforeMorph.progress)
            #expect(after.scale == before.scale)
            #expect(abs(after.alpha - before.alpha) < 0.001)
            #expect(abs(after.glyph.position.x - before.glyph.position.x) < 0.001)
            #expect(abs(after.glyph.position.y - before.glyph.position.y) < 0.001)
        }
        let settled = motion.frame(at: 2)
        #expect(settled.map(\.glyph) == glyphs(replacement + "32", size: 48))
        #expect(settled.allSatisfy { $0.morph == nil && $0.scale == 1 && $0.alpha == 1 })
    }

    @Test(arguments: [("1", "12"), ("12", "123"), ("1.", "1.2")])
    func `appended digits appear in place without shifting settled digits`(_ before: String, _ after: String) throws {
        let motion = TelegramAmountMotion(liquid: true)
        let target = glyphs(after)
        motion.update(glyphs(before), width: 300, timing: nil, at: 0)
        motion.update(target, width: 300,
            timing: TelegramAmountMotionTiming(spin: false, up: true, start: 1), at: 1)
        for frame in 1...60 {
            let sprites = motion.frame(at: 1 + Double(frame) / 120)
            for glyph in target {
                let sprite = try #require(sprites.first(where: { $0.glyph.text == glyph.text }))
                #expect(abs(sprite.glyph.position.x - glyph.position.x) < 0.001)
            }
        }
    }

    @Test func `suffix and caret reflow without horizontal overshoot on insertion and deletion`() throws {
        func amount(_ text: String) -> [TelegramAmountGlyph] {
            let number = glyphs(text)
            let end = number.last.map { $0.position.x + $0.width / 2 } ?? 0
            return number + TelegramAmountGlyph.text(NSAttributedString(string: "GRAM", attributes: [
                .font: UIFont.systemFont(ofSize: 32, weight: .bold), .foregroundColor: UIColor.label
            ]), origin: CGPoint(x: end + 18, y: 70), group: .suffix)
        }
        for (before, after) in [("12", "123"), ("123", "12")] {
            let motion = TelegramAmountMotion(liquid: true)
            let source = amount(before), target = amount(after)
            let oldSuffix = try #require(source.first(where: { $0.text == "G" }))
            let newSuffix = try #require(target.first(where: { $0.text == "G" }))
            let fromCaret = oldSuffix.leadingEdge - 10, toCaret = newSuffix.leadingEdge - 10
            let direction: CGFloat = toCaret > fromCaret ? 1 : -1
            motion.update(source, width: 350, timing: nil, at: 0)
            motion.update(target, width: 350,
                timing: TelegramAmountMotionTiming(spin: false, up: true, start: 1), at: 1)
            var previousSuffix = oldSuffix.position.x, previousCaret = fromCaret
            for frame in 0...60 {
                let time = 1 + Double(frame) / 120
                let suffix = try #require(motion.frame(at: time).first(where: { $0.glyph.text == "G" }))
                let caret = motion.caretPosition(at: time, fromX: fromCaret, toX: toCaret)
                #expect((suffix.glyph.position.x - previousSuffix) * direction >= -0.001)
                #expect((newSuffix.position.x - suffix.glyph.position.x) * direction >= -0.001)
                #expect((caret - previousCaret) * direction >= -0.001)
                #expect((toCaret - caret) * direction >= -0.001)
                #expect(abs(suffix.glyph.leadingEdge - caret - 10) < 0.001)
                previousSuffix = suffix.glyph.position.x
                previousCaret = caret
            }
        }
    }

    @Test func `a keystroke interrupt preserves the visible digit before settling exactly`() throws {
        let motion = TelegramAmountMotion(liquid: true)
        motion.update([], width: 300, timing: nil, at: 0)
        motion.update(glyphs("1"), width: 300,
            timing: TelegramAmountMotionTiming(spin: false, up: true, start: 1), at: 1)
        let before = try #require(motion.frame(at: 1.06).first(where: { $0.glyph.text == "1" }))
        motion.update(glyphs("12"), width: 300,
            timing: TelegramAmountMotionTiming(spin: false, up: true, start: 1.06), at: 1.06)
        let after = try #require(motion.frame(at: 1.06).first(where: { $0.glyph.text == "1" }))
        #expect(motion.frame(at: 1.10).filter { $0.glyph.text == "1" }.count == 1)
        #expect(abs(before.glyph.position.x - after.glyph.position.x) < 0.001)
        #expect(abs(before.alpha - after.alpha) < 0.001)
        #expect(abs(before.scale - after.scale) < 0.001)
        #expect(motion.frame(at: 2).map(\.glyph) == glyphs("12"))
    }

    @Test func `typing lets the placeholder morph finish without accumulating snapshots`() throws {
        let motion = TelegramAmountMotion(liquid: true)
        motion.update(glyphs("0"), width: 300, timing: nil, at: 0)
        motion.update(glyphs("1"), width: 300,
            timing: TelegramAmountMotionTiming(spin: false, up: true, start: 1), at: 1, fromPlaceholder: true)
        #expect(motion.frame(at: 1.06).first?.morph != nil)
        motion.update(glyphs("12"), width: 300,
            timing: TelegramAmountMotionTiming(spin: false, up: true, start: 1.06), at: 1.06)
        let first = motion.frame(at: 1.14).filter { $0.glyph.text == "1" }
        #expect(first.count == 1)
        #expect(try #require(first.first).morph == nil)
    }

    @Test func `replacement morphs and deletion leaves no outgoing glyphs after settling`() throws {
        let motion = TelegramAmountMotion(liquid: true)
        motion.update(glyphs("19"), width: 300, timing: nil, at: 0)
        motion.update(glyphs("14"), width: 300,
            timing: TelegramAmountMotionTiming(spin: false, up: true, start: 1), at: 1)
        let morph = try #require(motion.frame(at: 1.04).compactMap(\.morph).first)
        #expect(morph.from.text == "9")
        #expect(morph.progress > 0 && morph.progress < 1)
        motion.update(glyphs("1"), width: 300,
            timing: TelegramAmountMotionTiming(spin: false, up: true, start: 1.04), at: 1.04)
        #expect(motion.frame(at: 2).map(\.glyph) == glyphs("1"))
        motion.finish()
        #expect(!motion.isAnimating(at: 2))
    }

    @Test func `Metal glyph colors follow the editor appearance instead of the display link context`() throws {
        let text = NSAttributedString(string: "1", attributes: [
            .font: UIFont.systemFont(ofSize: 72), .foregroundColor: UIColor.label
        ])
        func snapshot(_ style: UIUserInterfaceStyle) throws -> TelegramAmountGlyph {
            let controller = UIViewController()
            controller.overrideUserInterfaceStyle = style
            let view = TelegramAmountPresentation(frame: CGRect(x: 0, y: 0, width: 300, height: 86))
            controller.view.addSubview(view)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            window.rootViewController = controller
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            return try #require(view.resolvedGlyphs(text: text, origin: .zero, group: .integer).first)
        }
        let dark = try snapshot(.dark)
        let light = try snapshot(.light)
        var darkWhite: CGFloat = 0, lightWhite: CGFloat = 0, alpha: CGFloat = 0
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            dark.color.getWhite(&darkWhite, alpha: &alpha)
        }
        UITraitCollection(userInterfaceStyle: .dark).performAsCurrent {
            light.color.getWhite(&lightWhite, alpha: &alpha)
        }
        #expect(darkWhite > 0.9)
        #expect(lightWhite < 0.1)
    }
}
