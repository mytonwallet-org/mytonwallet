import UIKit

/// The Agent's hand-drawn template glyphs
enum AgentGlyph {
    /// Draws round-capped, round-joined lines through the points of each of `strokes`
    static func makeImage(size: CGSize, lineWidth: CGFloat, strokes: [[CGPoint]]) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { _ in
            let path = UIBezierPath()
            for stroke in strokes {
                guard let start = stroke.first else { continue }
                path.move(to: start)
                for point in stroke.dropFirst() {
                    path.addLine(to: point)
                }
            }
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            UIColor.black.setStroke()
            path.stroke()
        }.withRenderingMode(.alwaysTemplate)
    }
}
