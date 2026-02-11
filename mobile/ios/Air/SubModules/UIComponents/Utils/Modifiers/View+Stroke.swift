import SwiftUI

extension InsettableShape {
    /// Draws a border fully inside the shape’s bounds without affecting its size.
    public func innerStroke(_ style: some ShapeStyle, lineWidth: Double) -> some View {
        inset(by: lineWidth / 2).stroke(style, lineWidth: lineWidth)
    }

    /// Draws a border fully outside the shape’s bounds without affecting its size.
    public func outerStroke(_ style: some ShapeStyle, lineWidth: Double) -> some View {
        inset(by: -(lineWidth / 2)).stroke(style, lineWidth: lineWidth)
    }
}

extension View {
    /// Adds border fully inside the view’s bounds without affecting its size.
    ///
    /// Four rectangular border use `.border()`.
    /// For symmetrical inner/outer use `.stroke()`.
    public func innerStrokeOverlay(_ style: some ShapeStyle,
                                   cornerRadius: Double,
                                   lineWidth: Double,
                                   clipToStroke shouldClipToStrokeShape: Bool,
                                   isVisible: Bool = true) -> some View {
        // adjustedClipShapeRadius ensures that the clipped corners are slightly more rounded than the stroke's corners,
        // preventing blending of antialiased edges at the rounded corners of stroke and underlying view.
        // This is seen good when color of view is contrast with color of stroke.
        // E.g. for red view & white stroke it looks like white stroke has small glow effect of red color.

        @ViewBuilder var sourceView: some View {
            if shouldClipToStrokeShape {
                let adjustedClipShapeRadius = cornerRadius + (1.0 / 2)
                clipShape(RoundedRectangle(cornerRadius: adjustedClipShapeRadius))
            } else {
                self
            }
        }

        return sourceView.overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .innerStroke(style, lineWidth: lineWidth)
                .isVisible(isVisible, remove: false)
        }
    }

    /// Adds border fully outside the view’s bounds without affecting its size.
    ///
    /// Four rectangular border use `.border()`.
    /// For symmetrical inner/outer use `.stroke()`.
    public func outerStrokeOverlay(_ style: some ShapeStyle,
                                   cornerRadius: Double,
                                   lineWidth: Double,
                                   clipToStroke shouldClipToStrokeShape: Bool,
                                   isVisible: Bool = true) -> some View {
        @ViewBuilder var sourceView: some View {
            // adjustedClipShapeRadius ensures that the clipped corners are slightly more rounded than the stroke's corners,
            // preventing blending of antialiased edges at the rounded corners.
            if shouldClipToStrokeShape {
                clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            } else {
                self
            }
        }

        return sourceView.overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .outerStroke(style, lineWidth: lineWidth)
                .isVisible(isVisible, remove: false)
        }
    }
}
