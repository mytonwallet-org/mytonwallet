import SwiftUI

extension View {
    /// Calculates the maximum number of columns that can fit horizontally given a minimum item width and spacing.
    /// It is analog of `GridItem(.adaptive(minimum:))` layout.
    private static func numberOfColumnsFor(itemMinWidth: CGFloat, spacing: CGFloat, availableHorizontalSpace: CGFloat) -> Int {
        guard itemMinWidth >= 1, availableHorizontalSpace >= itemMinWidth else { return 1 }

        let availableHorizontalSpace = availableHorizontalSpace + CGFloat.ulpOfOne

        var numberOfColumns = 1
        var totalWidth: CGFloat = 0

        while totalWidth < availableHorizontalSpace {
            let nextNumberOfColumns = numberOfColumns + 1
            totalWidth = (itemMinWidth * CGFloat(nextNumberOfColumns)) + (spacing * CGFloat(nextNumberOfColumns - 1))
            if totalWidth > availableHorizontalSpace {
                break
            }
            numberOfColumns = nextNumberOfColumns
        }

        return numberOfColumns
    }

    /// Computes an adaptive item width for a horizontal layout. Determines how many items fit within the available horizontal space.
    /// It is analog of `GridItem(.adaptive(minimum:))` layout.
    ///
    /// # Example:
    ///
    /// In example below there will be 1 view  visible in horizontal scroll on iPhone, 2 view on iPad Pro 11 in portrait and 3 in landscape.
    ///
    /// | Device Mode         | Layout                |
    /// |----------------------|---------------------|
    /// | iPhone Portrait       | `[()]`              |
    /// | iPhone Landscape | `[() ()]`       |
    /// | iPad Portrait           | `[() ()]`       |
    /// | iPad Landscape     | `[() () ()]` |
    /// ```Swift
    /// ScrollView(.horizontal, showsIndicators: false) {
    ///     HStack(spacing: interItemHSpacing) {
    ///         ForEach(sites, id: \.url) { site in
    ///             ExampleView(site: site)
    ///             .aspectRatio(2, contentMode: .fill)
    ///             .containerRelativeFrame(.horizontal) { hScrollWidth, _ in
    ///                 Self.adaptiveItemWidthFor(availableHorizontalSpace: hScrollWidth,
    ///                                           itemMinWidth: 320,
    ///                                           spacing: interItemHSpacing)
    ///             }
    ///         }
    ///     }
    /// }
    /// ```
    public static func adaptiveWidthFor(availableHorizontalSpace: CGFloat,
                                        itemMinWidth: CGFloat,
                                        spacing: CGFloat) -> CGFloat {
        let numberOfColumns = numberOfColumnsFor(itemMinWidth: itemMinWidth,
                                                 spacing: spacing,
                                                 availableHorizontalSpace: availableHorizontalSpace)
        let itemWidth = (availableHorizontalSpace - (spacing * CGFloat(numberOfColumns - 1))) / CGFloat(numberOfColumns)
        return itemWidth
    }
}
