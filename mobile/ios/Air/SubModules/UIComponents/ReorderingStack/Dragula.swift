//
//  Created by Mustafa Yusuf on 05/06/25.
//
// MIT License
//
// Copyright (c) 2025 Mustafa Yusuf
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//
//


import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// A protocol representing a section that contains drag-and-droppable items.
/// Conforming types must provide an array of `DragulaItem`-conforming items.
///
/// - Example:
/// ```swift
/// struct TaskSection: DragulaSection {
///     let id: UUID
///     let title: String
///     var items: [TaskItem]
/// }
/// ```
public protocol DragulaSection: Identifiable {
    /// The type of item contained in the section.
    associatedtype Item: DragulaItem
    /// The items contained in this section.
    var items: [Item] { get set }
}

/// A protocol for individual drag-and-droppable items.
/// Conforming types can provide an `NSItemProvider` for drag interaction.
///
/// - Example:
/// ```swift
/// struct TaskItem: DragulaItem {
///     let id: UUID
///     let title: String
///
///     func getItemProvider() -> NSItemProvider {
///         NSItemProvider(object: title as NSString)
///     }
/// }
public protocol DragulaItem: Identifiable {
    /// Override to provide a meaningful item provider for drag sessions.
    func getItemProvider() -> NSItemProvider
}

extension DragulaItem {
    /// Default implementation returns an empty item provider.
    public func getItemProvider() -> NSItemProvider {
        .init()
    }
}

/// A reusable SwiftUI view that supports sectioned drag-and-drop reordering of items.
///
/// Each section has a header and a list of draggable items represented by `Card`.
///
/// - Parameters:
///   - Header: A view shown as the section header.
///   - Card: A draggable item view.
///   - DropView: A view to display during drag-over state.
///   - Section: The section type conforming to `DragulaSection`.
///
/// - Example:
/// ```swift
/// DragulaSectionedView(sections: $sections) { section in
///     Text(section.title)
/// } card: { item in
///     Text(item.title)
/// } dropView: { item in
///     Color.gray
/// } dropCompleted: {
/// }
/// ```
public struct DragulaSectionedView<Header: View,
                                         Card: View,
                                         DropView: View,
                                         Section: DragulaSection>: View {
    
    @Binding private var sections: [Section]
    @Binding private var items: [Section.Item]
    @State private var draggedItems: [Section.Item] = []
    
    private let header: (Section) -> Header
    private let card: (Section.Item) -> Card
    private let dropView: ((Section.Item) -> DropView)?
    private let dropCompleted: () -> Void
    
    private let supportedUTTypes: [UTType] = []
    
    /// Creates a sectioned drag-and-drop view.
    /// - Parameters:
    ///   - sections: A binding to an array of sections.
    ///   - header: View builder for each section header.
    ///   - card: View builder for each item.
    ///   - dropView: View builder for the drop-over indicator.
    ///   - dropCompleted: Called when a drop completes.
    public init(
        sections: Binding<[Section]>,
        @ViewBuilder header: @escaping (Section) -> Header,
        @ViewBuilder card: @escaping (Section.Item) -> Card,
        @ViewBuilder dropView: @escaping (Section.Item) -> DropView,
        dropCompleted: @escaping () -> Void
    ) {
        self._sections = sections
        self._items = .constant([])
        self.header = header
        self.card = card
        self.dropView = dropView
        self.dropCompleted = dropCompleted
    }
    
    public init(
        items: Binding<[Section.Item]>,
        @ViewBuilder header: @escaping (Section) -> Header,
        @ViewBuilder card: @escaping (Section.Item) -> Card,
        @ViewBuilder dropView: @escaping (Section.Item) -> DropView,
        dropCompleted: @escaping () -> Void
    ) {
        self._sections = .constant([])
        self._items = items
        self.header = header
        self.card = card
        self.dropView = dropView
        self.dropCompleted = dropCompleted
    }
    
    public var body: some View {
        ForEach(sections) { section in
            #if os(watchOS)
            header(section)
            #else
            header(section)
                .onDrop(
                    of: supportedUTTypes,
                    delegate: DragulaSectionDropDelegate(
                        item: nil,
                        sectionID: section.id,
                        sections: $sections,
                        draggedItems: $draggedItems
                    )
                )
            #endif
            
            ForEach(section.items) { item in
                #if os(watchOS)
                card(item)
                #else
                card(item)
                    .hidden()
                    .overlay {
                        DraggableView(
                            preview: {
                                card(item)
                            }, dropView: {
                                dropView?(item)
                            }, itemProvider: {
                                item.getItemProvider()
                            }, onDragWillBegin: {
                                self.draggedItems.append(item)
                            }, onDragWillEnd: {
                                self.draggedItems = []
                                self.dropCompleted()
                            })
                    }
                    .onDrop(
                        of: supportedUTTypes,
                        delegate: DragulaSectionDropDelegate(
                            item: item,
                            sectionID: section.id,
                            sections: $sections,
                            draggedItems: $draggedItems
                        )
                    )
                #endif
            }
        }
    }
}

/// A reusable SwiftUI view that supports drag-and-drop reordering of a flat list of items.
///
/// - Parameters:
///   - Card: The draggable item view.
///   - DropView: A view to show during a drag-over state.
///   - Item: The item type conforming to `DragulaItem`.
///
/// - Example:
/// ```swift
/// DragulaView(items: $tasks) { item in
///     Text(item.title)
/// } dropView: { item in
///     Color.secondary
/// } dropCompleted: {
/// }
/// ```
public struct DragulaView<Card: View, DropView: View, Item: DragulaItem>: View {
    
    @State private var draggedItems: [Item] = []
    
    @Binding var items: [Item]
    private let card: (Item) -> Card
    private let dropView: ((Item) -> DropView)?
    private let dropCompleted: () -> Void
    
    private let supportedUTTypes: [UTType] = []
    
    /// Creates a drag-and-drop view for a flat list of items.
    /// - Parameters:
    ///   - items: A binding to an array of items.
    ///   - card: View builder for each item.
    ///   - dropView: View builder for the drop-over indicator.
    ///   - dropCompleted: Called when a drop completes.
    public init(
        items: Binding<[Item]>,
        @ViewBuilder card: @escaping (Item) -> Card,
        @ViewBuilder dropView: @escaping (Item) -> DropView,
        dropCompleted: @escaping () -> Void
    ) {
        self._items = items
        self.card = card
        self.dropView = dropView
        self.dropCompleted = dropCompleted
    }
    
    public var body: some View {
        ForEach(items) { item in
            #if os(watchOS)
            card(item)
            #else
            card(item)
                .hidden()
                .overlay {
                    DraggableView(
                        preview: {
                            card(item)
                        }, dropView: {
                            dropView?(item)
                        }, itemProvider: {
                            item.getItemProvider()
                        }, onDragWillBegin: {
                            self.draggedItems.append(item)
                        }, onDragWillEnd: {
                            self.draggedItems = []
                            self.dropCompleted()
                        })
                }
                .onDrop(
                    of: supportedUTTypes,
                    delegate: DragulaDropDelegate(
                        item: item,
                        items: $items,
                        draggedItems: $draggedItems
                    )
                )
                #endif
        }
    }
}

// MARK: FILEPRIVATE STUFF, NONE OF YOUR BUSINESS

#if !os(watchOS)
fileprivate struct DragulaDropDelegate<Item: DragulaItem>: DropDelegate {
    
    private let generator = UIImpactFeedbackGenerator(style: .rigid)
    
    private let item: Item
    @Binding private var items: [Item]
    @Binding private var draggedItems: [Item]
    
    private let animation: Animation = .spring
    
    init(
        item: Item,
        items: Binding<[Item]>,
        draggedItems: Binding<[Item]>
    ) {
        self.item = item
        self._items = items
        self._draggedItems = draggedItems
    }

    func performDrop(info: DropInfo) -> Bool {
        !draggedItems.isEmpty
    }
    
    private func index(of item: Item) -> Int? {
        items.firstIndex(where: { $0.id == item.id })
    }
    
    func dropEntered(info: DropInfo) {
        guard !draggedItems.isEmpty else {
            return
        }

        // Prevent inserting on top of any dragged item
        guard draggedItems.allSatisfy({ $0.id != item.id }) else {
            return
        }
        
        var didPerformAnyChanges: Bool = false
        
        withAnimation(animation) {
            // Remove dragged items from their original sections
            for dragged in draggedItems {
                if let fromIndex = index(of: dragged),
                   let toIndex = index(of: item) {
                    didPerformAnyChanges = true
                    items.move(
                        fromOffsets: IndexSet(integer: fromIndex),
                        toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
                    )
                }
            }
        }
        
        if didPerformAnyChanges {
            playHaptic()
        }
    }
    
    func playHaptic() {
        generator.prepare()
        generator.impactOccurred()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .cancel)
    }
}

// MARK: - Drop Delegate
fileprivate struct DragulaSectionDropDelegate<Section: DragulaSection>: DropDelegate {
    
    private let generator = UIImpactFeedbackGenerator(style: .rigid)
    
    private let item: Section.Item? // when nil it means dropping into a section
    private let sectionID: Section.ID
    @Binding private var sections: [Section]
    @Binding private var draggedItems: [Section.Item]
        
    private let animation: Animation = .spring

    init(
        item: Section.Item?,
        sectionID: Section.ID,
        sections: Binding<[Section]>,
        draggedItems: Binding<[Section.Item]>
    ) {
        self.item = item
        self.sectionID = sectionID
        self._sections = sections
        self._draggedItems = draggedItems
    }

    func performDrop(info: DropInfo) -> Bool {
        !draggedItems.isEmpty
    }
    
    private func sectionIndex(for item: Section.Item) -> Int? {
        sections.firstIndex(where: { section in
            section.items.contains { $0.id == item.id }
        })
    }
    
    private func itemIndex(for item: Section.Item) -> Int? {
        for section in sections {
            if let index = section.items.firstIndex(where: { $0.id == item.id }) {
                return index
            }
        }
        return nil
    }
    
    func dropEntered(info: DropInfo) {
        guard !draggedItems.isEmpty else {
            return
        }

        // Prevent inserting on top of any dragged item
        guard draggedItems.allSatisfy({ $0.id != item?.id }) else {
            return
        }

        let toSectionIndex: Int
        if let item, let index = sectionIndex(for: item) {
            toSectionIndex = index
        } else if let index = sections.firstIndex(where: { $0.id == sectionID }) {
            toSectionIndex = index
        } else {
            return
        }
        
        var didPerformAnyChanges: Bool = false

        withAnimation(animation) {
            // Remove dragged items from their original sections
            for draggedItem in draggedItems {
                if let fromSectionIndex = sectionIndex(for: draggedItem),
                   let fromIndex = itemIndex(for: draggedItem) {
                    let toIndex: Int
                    if let item, let index = itemIndex(for: item) {
                        toIndex = index
                    } else {
                        toIndex = .zero
                    }
                    
                    if fromSectionIndex == toSectionIndex {
                        if fromIndex != toIndex {
                            didPerformAnyChanges = true
                            sections[toSectionIndex].items.move(
                                fromOffsets: IndexSet(integer: fromIndex),
                                toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
                            )
                        }
                    } else {
                        didPerformAnyChanges = true
                        // Insert dragged items starting at calculated drop index
                        sections[fromSectionIndex].items.remove(at: fromIndex)
                        sections[toSectionIndex].items.insert(draggedItem, at: toIndex)
                    }
                }
            }
        }
        
        if didPerformAnyChanges {
            playHaptic()
        }
    }
    
    func playHaptic() {
        generator.prepare()
        generator.impactOccurred()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .cancel)
    }
    
    func validateDrop(info: DropInfo) -> Bool {
        if item == nil {
            // user is dropping it to a section in this case as item wasn't supplied
            // check if item is in same section, if so, do nothing
            let sectionIndices = Set(draggedItems.compactMap { sectionIndex(for: $0) })
            if sectionIndices.count == 1,
               let sectionIndex = sectionIndices.first,
               sections[sectionIndex].id == sectionID {
                return false
            } else {
                return true
            }
        }
        
        return true
    }
}
#endif

/// An environment key to customize the corner radius of the drag preview.
private struct DragPreviewCornerRadiusKey: EnvironmentKey {
    static let defaultValue: CGFloat = 12
}

/// A SwiftUI environment value that controls the corner radius of draggable preview content.
/// You can set this value on any view using `.environment(\.dragPreviewCornerRadius, radius)`
extension EnvironmentValues {
    /// The corner radius applied to drag preview content.
    public var dragPreviewCornerRadius: CGFloat {
        get { self[DragPreviewCornerRadiusKey.self] }
        set { self[DragPreviewCornerRadiusKey.self] = newValue }
    }
}
