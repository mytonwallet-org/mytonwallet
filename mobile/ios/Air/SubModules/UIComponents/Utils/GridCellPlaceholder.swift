import SwiftUI

/// Helps to prevent issues like broken spacing, size or misalignment when using `EmptyView` or `Spacer` in grid-based views.
/// A placeholder view that occupies space in a grid layout without affecting layout or interaction.
public struct GridCellPlaceholder: View {
  public var body: some View {
    Color.clear
      .allowsHitTesting(false)
      .accessibilityHidden(true)
  }
  
  public init() {}
}
