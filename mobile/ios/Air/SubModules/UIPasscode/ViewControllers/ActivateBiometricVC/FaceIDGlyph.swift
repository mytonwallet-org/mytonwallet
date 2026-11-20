//
//  FaceIDGlyph.swift
//  UIPasscode
//
//  The Face ID header icon, drawn from its PDF (FaceIdHeaderImage) as separate strokes so it can
//  come alive: the face wakes up as the screen appears (its eyes open with a blink) and then looks
//  around now and then, the features shifting with a little parallax like a turning head. While
//  Face ID is asked for, the brackets pulse; on success they close into a circle and the face
//  turns into a check mark.
//

import SwiftUI

struct FaceIDGlyph: View {
    enum Phase {
        case idle
        case scanning
        case success
    }

    var phase: Phase

    // Measured from the PDF, in its 124 pt box.
    private static let side: CGFloat = 124
    private static let green = Color(.sRGB, red: 0.203922, green: 0.780392, blue: 0.349020)
    private static let faceLine: CGFloat = 7.59
    private static let bracketLine: CGFloat = 6.643
    /// How far each feature moves when the face looks fully to a side (x) or up/down (y): the
    /// eyes most, the smile least, so the face reads as turning in depth, not sliding.
    private static let eyesTravel = CGSize(width: 6, height: 4)
    private static let noseTravel = CGSize(width: 4, height: 2.6)
    private static let smileTravel = CGSize(width: 2.6, height: 1.6)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isAwake = false
    @State private var eyesOpen: CGFloat = 0.1
    @State private var smileDrawn: CGFloat = 0.6
    @State private var isBlinking = false
    @State private var look = CGPoint.zero
    @State private var isPulsing = false
    @State private var collapse: CGFloat = 0
    @State private var faceGone = false
    @State private var checkDrawn: CGFloat = 0
    @State private var pump: CGFloat = 1

    var body: some View {
        ZStack {
            TileShape()
                .fill(Self.green)
                .scaleEffect(pump)

            brackets
            face
            checkMark
        }
        .frame(width: Self.side, height: Self.side)
        .onChange(of: phase) { phase in
            switch phase {
            case .idle: stopScanning()
            case .scanning: startScanning()
            case .success: playSuccess()
            }
        }
        .task {
            guard !isAwake else { return }
            await live()
        }
    }

    // MARK: Parts

    private var brackets: some View {
        ZStack {
            ForEach(0..<4) { corner in
                CornerBracket(collapse: collapse)
                    .stroke(.white, style: StrokeStyle(lineWidth: Self.bracketLine, lineCap: .round, lineJoin: .round))
                    .rotationEffect(.degrees(Double(corner) * 90))
            }
        }
        // As one layer, so the closed circle's overlapping caps don't show darker.
        .compositingGroup()
        .opacity(0.5 + 0.5 * collapse)
        .rotationEffect(.degrees(-90 * collapse))
        .scaleEffect(isPulsing ? 0.92 : 1)
        .scaleEffect(pump)
    }

    private var face: some View {
        let stroke = StrokeStyle(lineWidth: Self.faceLine, lineCap: .round, lineJoin: .round)
        let eyeScale = max(eyesOpen * (isBlinking ? 0.1 : 1), 0.001)
        func shift(_ travel: CGSize) -> CGSize {
            CGSize(width: look.x * travel.width, height: look.y * travel.height)
        }
        return ZStack {
            ZStack {
                Eye(x: 43.652)
                    .stroke(.white, style: stroke)
                    .scaleEffect(x: 1, y: eyeScale, anchor: UnitPoint(x: 43.652 / Self.side, y: 48.24 / Self.side))
                Eye(x: 80.348)
                    .stroke(.white, style: stroke)
                    .scaleEffect(x: 1, y: eyeScale, anchor: UnitPoint(x: 80.348 / Self.side, y: 48.24 / Self.side))
            }
            .offset(shift(Self.eyesTravel))
            Nose()
                .stroke(.white, style: stroke)
                .offset(shift(Self.noseTravel))
            Smile()
                // Widens from the middle.
                .trim(from: 0.5 - 0.5 * smileDrawn, to: 0.5 + 0.5 * smileDrawn)
                .stroke(.white, style: stroke)
                .offset(shift(Self.smileTravel))
        }
        .scaleEffect(faceGone ? 0.5 : 1)
        .opacity(faceGone ? 0 : 1)
        .scaleEffect(pump)
    }

    private var checkMark: some View {
        CheckMark()
            .trim(from: 0, to: checkDrawn)
            .stroke(.white, style: StrokeStyle(lineWidth: Self.faceLine, lineCap: .round, lineJoin: .round))
            .opacity(checkDrawn > 0 ? 1 : 0)
            .scaleEffect(pump)
    }

    // MARK: Motion

    private static func seconds(_ s: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000))
    }

    /// Wakes up, then lives: looks around, blinks, comes back to you. Starts as the screen
    /// begins to appear, so the eyes open while it slides in and it arrives already awake.
    private func live() async {
        isAwake = true
        guard !reduceMotion else {
            eyesOpen = 1; smileDrawn = 1
            return
        }
        await Self.seconds(0.08)
        // Eyes open with a little overshoot, the smile follows, then a quick blink: awake.
        withAnimation(.spring(response: 0.34, dampingFraction: 0.55)) { eyesOpen = 1 }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.08)) { smileDrawn = 1 }
        await Self.seconds(0.55)
        await blink()

        // Gazes as (x, y) in -1…1, with how long to hold each; repeats.
        let gazes: [(CGPoint, Double)] = [
            (CGPoint(x: 0, y: 0), 1.6),
            (CGPoint(x: -1, y: 0.1), 1.1),
            (CGPoint(x: 1, y: -0.2), 1.0),
            (CGPoint(x: 0, y: 0), 1.8),
            (CGPoint(x: 0.7, y: -0.8), 0.9),
            (CGPoint(x: -0.8, y: -0.5), 0.9),
            (CGPoint(x: 0, y: 0), 2.0),
        ]
        var index = 0
        while !Task.isCancelled {
            let (gaze, hold) = gazes[index % gazes.count]
            index += 1
            guard phase == .idle else {
                await Self.seconds(0.5)
                continue
            }
            // People often blink as their eyes jump to a new spot.
            if Int.random(in: 0..<3) == 0 { Task { await blink() } }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) { look = gaze }
            await Self.seconds(hold)
            if gaze == .zero, Int.random(in: 0..<2) == 0 {
                await blink()
                if Int.random(in: 0..<3) == 0 {
                    await Self.seconds(0.12)
                    await blink()
                }
                await Self.seconds(0.4)
            }
        }
    }

    private func blink() async {
        withAnimation(.easeIn(duration: 0.07)) { isBlinking = true }
        await Self.seconds(0.08)
        withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) { isBlinking = false }
        await Self.seconds(0.15)
    }

    private func startScanning() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { look = .zero }
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { isPulsing = true }
    }

    private func stopScanning() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { isPulsing = false }
    }

    private func playSuccess() {
        isBlinking = false
        // The brackets close into a circle with a twist, the face gives way to a check mark, and
        // the whole icon pumps once.
        withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) {
            isPulsing = false
            look = .zero
            collapse = 1
        }
        withAnimation(.easeIn(duration: 0.16)) { faceGone = true }
        withAnimation(.easeOut(duration: 0.3).delay(0.18)) { checkDrawn = 1 }
        withAnimation(.spring(response: 0.22, dampingFraction: 0.5)) { pump = 1.08 }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.55).delay(0.14)) { pump = 1 }
    }
}

// MARK: - Shapes (PDF coordinates, y down, 124 pt box)

private func scaled(_ path: Path, in rect: CGRect) -> Path {
    let s = rect.width / 124
    return path.applying(CGAffineTransform(scaleX: s, y: s).translatedBy(x: rect.minX / s, y: rect.minY / s))
}

/// The green squircle, the PDF's own path (drawn y-up there, flipped here).
private struct TileShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 71.2))
        p.addCurve(to: CGPoint(x: 3.596785, y: 105.981689), control1: CGPoint(x: 0, y: 89.681732), control2: CGPoint(x: 0, y: 98.9226))
        p.addCurve(to: CGPoint(x: 18.018312, y: 120.403214), control1: CGPoint(x: 6.760606, y: 112.191032), control2: CGPoint(x: 11.808965, y: 117.239395))
        p.addCurve(to: CGPoint(x: 52.8, y: 124), control1: CGPoint(x: 25.0774, y: 124), control2: CGPoint(x: 34.318268, y: 124))
        p.addLine(to: CGPoint(x: 71.2, y: 124))
        p.addCurve(to: CGPoint(x: 105.981689, y: 120.403214), control1: CGPoint(x: 89.681732, y: 124), control2: CGPoint(x: 98.9226, y: 124))
        p.addCurve(to: CGPoint(x: 120.403214, y: 105.981689), control1: CGPoint(x: 112.191032, y: 117.239395), control2: CGPoint(x: 117.239395, y: 112.191032))
        p.addCurve(to: CGPoint(x: 124, y: 71.2), control1: CGPoint(x: 124, y: 98.9226), control2: CGPoint(x: 124, y: 89.681732))
        p.addLine(to: CGPoint(x: 124, y: 52.8))
        p.addCurve(to: CGPoint(x: 120.403214, y: 18.018311), control1: CGPoint(x: 124, y: 34.318268), control2: CGPoint(x: 124, y: 25.0774))
        p.addCurve(to: CGPoint(x: 105.981689, y: 3.596786), control1: CGPoint(x: 117.239395, y: 11.808968), control2: CGPoint(x: 112.191032, y: 6.760605))
        p.addCurve(to: CGPoint(x: 71.2, y: 0), control1: CGPoint(x: 98.9226, y: 0), control2: CGPoint(x: 89.681732, y: 0))
        p.addLine(to: CGPoint(x: 52.8, y: 0))
        p.addCurve(to: CGPoint(x: 18.018312, y: 3.596786), control1: CGPoint(x: 34.318268, y: 0), control2: CGPoint(x: 25.0774, y: 0))
        p.addCurve(to: CGPoint(x: 3.596785, y: 18.018311), control1: CGPoint(x: 11.808965, y: 6.760605), control2: CGPoint(x: 6.760606, y: 11.808968))
        p.addCurve(to: CGPoint(x: 0, y: 52.8), control1: CGPoint(x: 0, y: 25.0774), control2: CGPoint(x: 0, y: 34.318268))
        p.closeSubpath()
        // y-up → y-down; symmetric, so only the orientation matters.
        return scaled(p.applying(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 124)), in: rect)
    }
}

/// The top-right corner bracket's centre line; the others are it rotated. `collapse` 1 bends it
/// into a quarter of the success circle, point for point, so the morph has nothing to snap.
private struct CornerBracket: Shape {
    var collapse: CGFloat

    var animatableData: CGFloat {
        get { collapse }
        set { collapse = newValue }
    }

    /// Centre line of the PDF bracket (midway between its outer and inner outlines): a short
    /// straight end, five cubic segments around the corner, and the other straight end. In the
    /// PDF's y-up group space, offset by 17.714.
    private static let rest: [CGPoint] = {
        let local: [CGPoint] = [
            CGPoint(x: 65.32, y: 85.25),
            CGPoint(x: 66.19, y: 85.25),
            CGPoint(x: 69.505, y: 85.25), CGPoint(x: 71.99, y: 85.25), CGPoint(x: 73.97, y: 85.09),
            CGPoint(x: 75.965, y: 84.925), CGPoint(x: 77.44, y: 84.6), CGPoint(x: 78.72, y: 83.95),
            CGPoint(x: 80.97, y: 82.8), CGPoint(x: 82.8, y: 80.97), CGPoint(x: 83.95, y: 78.72),
            CGPoint(x: 84.6, y: 77.44), CGPoint(x: 84.925, y: 75.965), CGPoint(x: 85.09, y: 73.97),
            CGPoint(x: 85.25, y: 71.99), CGPoint(x: 85.25, y: 69.505), CGPoint(x: 85.25, y: 66.19),
            CGPoint(x: 85.25, y: 65.32),
        ]
        return local.map { CGPoint(x: 17.714 + $0.x, y: 106.286 - $0.y) }
    }()

    /// The same structure on a quarter circle around the tile's centre, with the bracket's own
    /// reach (radius 40.96): straight ends of zero length, five equal cubic arcs.
    private static let circle: [CGPoint] = {
        let center = CGPoint(x: 62, y: 62), radius: CGFloat = 40.96
        let step = CGFloat.pi / 2 / 5
        let handle = 4 / 3 * tan(step / 4) * radius
        func point(_ a: CGFloat) -> CGPoint { CGPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a)) }
        func tangent(_ a: CGFloat) -> CGPoint { CGPoint(x: -sin(a), y: cos(a)) }
        var points = [point(-.pi / 2), point(-.pi / 2)]
        for i in 0..<5 {
            let a = -CGFloat.pi / 2 + CGFloat(i) * step, b = a + step
            let pa = point(a), pb = point(b), ta = tangent(a), tb = tangent(b)
            points.append(CGPoint(x: pa.x + handle * ta.x, y: pa.y + handle * ta.y))
            points.append(CGPoint(x: pb.x - handle * tb.x, y: pb.y - handle * tb.y))
            points.append(pb)
        }
        points.append(point(0))
        return points
    }()

    func path(in rect: CGRect) -> Path {
        let points = zip(Self.rest, Self.circle).map { a, b in
            CGPoint(x: a.x + (b.x - a.x) * collapse, y: a.y + (b.y - a.y) * collapse)
        }
        var p = Path()
        p.move(to: points[0])
        p.addLine(to: points[1])
        for i in 0..<5 {
            p.addCurve(to: points[4 + 3 * i], control1: points[2 + 3 * i], control2: points[3 + 3 * i])
        }
        p.addLine(to: points[17])
        return scaled(p, in: rect)
    }
}

private struct Eye: Shape {
    var x: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: x, y: 44.538))
        p.addLine(to: CGPoint(x: x, y: 51.943))
        return scaled(p, in: rect)
    }
}

private struct Nose: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 62, y: 44.538))
        p.addLine(to: CGPoint(x: 62, y: 64.477))
        p.addLine(to: CGPoint(x: 56.797, y: 64.477))
        return scaled(p, in: rect)
    }
}

private struct Smile: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 46.97, y: 78.25))
        p.addCurve(to: CGPoint(x: 62, y: 84.24), control1: CGPoint(x: 51.03, y: 82.1), control2: CGPoint(x: 56.41, y: 84.24))
        p.addCurve(to: CGPoint(x: 77.03, y: 78.25), control1: CGPoint(x: 67.59, y: 84.24), control2: CGPoint(x: 72.97, y: 82.1))
        return scaled(p, in: rect)
    }
}

private struct CheckMark: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 45, y: 63))
        p.addLine(to: CGPoint(x: 56.5, y: 74.5))
        p.addLine(to: CGPoint(x: 79.5, y: 50.5))
        return scaled(p, in: rect)
    }
}

#if DEBUG
@available(iOS 18.0, *)
#Preview {
    @Previewable @State var phase = FaceIDGlyph.Phase.idle
    VStack(spacing: 24) {
        FaceIDGlyph(phase: phase)
        Button("Next") {
            phase = phase == .idle ? .scanning : phase == .scanning ? .success : .idle
        }
    }
}
#endif
