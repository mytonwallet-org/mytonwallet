//
//  CoverFlow.swift
//  MyTonWalletAir
//
//  Created by nikstar on 01.07.2025.
//

import SwiftUI
import UIKit
import UIComponents
import WalletContext
import WalletCore
import SwiftUIIntrospect

public enum CoverFlowDefaults {
    static let itemSpacing: Double = -60
    static let rotationSensitivity: Double = 2.7
    static let rotationAngle: Double = -15
    static let offsetSensitivity: Double = 1
    static let offsetMultiplier: Double = 4
    static let offsetMultiplier2: Double = -50
}

final class CoverFlowViewModel<Item: Identifiable>: ObservableObject {
    
    @Published var items: [Item]
    @Published var selectedItem: Item.ID
    
    var onTap: () -> ()
    var onLongTap: () -> ()
    
    init(items: [Item], selectedItem: Item.ID, onTap: @escaping () -> Void, onLongTap: @escaping () -> Void) {
        self.items = items
        self.selectedItem = selectedItem
        self.onTap = onTap
        self.onLongTap = onLongTap
    }
}

struct CoverFlow<Item: Identifiable, Content: View>: View {
    
    var isExpanded: Bool
    @ObservedObject var viewModel: CoverFlowViewModel<Item>
    
    @ViewBuilder var content: (Item) -> Content
    
    init(isExpanded: Bool, viewModel: CoverFlowViewModel<Item>, @ViewBuilder content: @escaping (Item) -> Content) {
        self.isExpanded = isExpanded
        self.viewModel = viewModel
        self.content = content
    }
    
    var body: some View {
        HStack {
            //        if #available(iOS 18, *), false {
            if #available(iOS 18, *) {
//                EquatableView(content:
                    CoverFlow_iOS18(isExpanded: false, viewModel: viewModel, content: content)
//                )
            } else {
                GeometryReader { _ in
                    let id = viewModel.selectedItem
                    if let item = viewModel.items.first(id: id) {
                        content(item)
                            .aspectRatio(1, contentMode: .fit)
                            .frame(width: 144, height: 144)
                            .clipShape(.rect(cornerRadius: 12))
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}

@available(iOS 18, *)
struct CoverFlow_iOS18<Item: Identifiable, Content: View>: View, Equatable {
    
    static func == (lhs: CoverFlow_iOS18<Item, Content>, rhs: CoverFlow_iOS18<Item, Content>) -> Bool {
        lhs.viewModel.selectedItem == rhs.viewModel.selectedItem
    }
    
    var isExpanded: Bool
    @ObservedObject var viewModel: CoverFlowViewModel<Item>
    
    @ViewBuilder var content: (Item) -> Content
    
    @State private var size: CGSize = .zero
    
    @State private var scrollPosition: ScrollPosition = ScrollPosition(idType: Item.ID.self)

    @Environment(\.coverFlowItemSize) var coverFlowItemSize
    @AppStorage("cf_itemSpacing") private var itemSpacing: Double = CoverFlowDefaults.itemSpacing
    
    @State private var isScrolling = false
    
    var selectedIdx: Int {
        if let id = scrollPosition.viewID(type: Item.ID.self), let idx = viewModel.items.firstIndex(where: { $0.id == id }) {
            return idx
        }
        return 0
    }
    
    init(isExpanded: Bool, viewModel: CoverFlowViewModel<Item>, @ViewBuilder content: @escaping (Item) -> Content) {
        self.isExpanded = isExpanded
        self.viewModel = viewModel
        self.content = content
    }
    
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: itemSpacing) {
                ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { (idx, item) in
                    let id = item.id
                    let zIndex = -abs(selectedIdx - idx)
                    CoverFlowItem {
                        content(item)
    //                            .overlay { Color.red }
                    }
//                    .overlay {
//                        Text(zIndex.formatted())
//                            .offset(y: -100)
//                    }
                    .gesture(LongPressGesture(minimumDuration: 0.25, maximumDistance: 20)
                        .onEnded { _ in
                            viewModel.onLongTap()
                        })
                    ._onButtonGesture { _ in
                    } perform: {
                        if id == viewModel.selectedItem {
                            viewModel.onTap()
                        } else {
                            withAnimation(.snappy) {
                                scrollPosition.scrollTo(id: id)
                            }
                        }
                    }
                    .zIndex(Double(zIndex))
                    .environment(\.coverFlowIsCurrent, id == viewModel.selectedItem)
                    .geometryGroup()
                }
            }
            .scrollTargetLayout()
            .geometryGroup()
        }
        .scrollTargetBehavior(.viewAligned(limitBehavior: .automatic))
        .contentMargins(.horizontal, isExpanded ? 0 : (size.width - coverFlowItemSize)/2, for: .scrollContent)
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .scrollPosition($scrollPosition)
        .onScrollPhaseChange { _, newPhase in
            isScrolling = newPhase != .idle
        }
        .onAppear {
            scrollPosition.scrollTo(id: viewModel.selectedItem)
        }
        .onChange(of: scrollPosition.viewID(type: Item.ID.self)) { _, newValue in
            if let newValue {
                viewModel.selectedItem = newValue
            }
        }
        .onChange(of: isExpanded) { _, newValue in
            scrollPosition.scrollTo(id: viewModel.selectedItem)
        }
        .preference(key: CoverFlowIsScrollingPreference.self, value: isScrolling)
        .onGeometryChange(for: CGSize.self, of: { $0.size }, action: { self.size = $0 })
        .sensoryFeedback(.selection, trigger: scrollPosition.viewID(type: Item.ID.self))
    }
}

@available(iOS 18, *)
struct CoverFlowItem<Content: View>: View {
    
    var content: () -> Content

    @Environment(\.coverFlowItemSize) var coverFlowItemSize

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }
    
    private typealias D = CoverFlowDefaults
    @AppStorage("cf_itemSpacing") private var itemSpacing: Double = D.itemSpacing
    @AppStorage("cf_rotationSensitivity") private var rotationSensitivity: Double = D.rotationSensitivity
    @AppStorage("cf_rotationAngle") private var rotationAngle: Double = D.rotationAngle
    @AppStorage("cf_offsetSensitivity") private var offsetSensitivity: Double = D.offsetSensitivity
    @AppStorage("cf_offsetMultiplier") private var offsetMultiplier: Double = D.offsetMultiplier
    @AppStorage("cf_offsetMultiplier2") private var offsetMultiplier2: Double = D.offsetMultiplier2
    
//    @State private var distance: CGFloat = 0
//    @State private var distance2: CGFloat = 0
    
    var body: some View {
        content()
//            .overlay {
//                Text(distance.formatted())
//                    .foregroundStyle(.white)
//            }
            .aspectRatio(1, contentMode: .fit)
            .frame(width: coverFlowItemSize, height: coverFlowItemSize)
            .clipShape(.rect(cornerRadius: 12))
            .aspectRatio(contentMode: .fill)
            .frame(width: coverFlowItemSize, height: coverFlowItemSize)
            .visualEffect { [coverFlowItemSize, itemSpacing, offsetMultiplier, offsetMultiplier2, offsetSensitivity, rotationAngle, rotationSensitivity] content, geom in
                let position = geom.frame(in: .scrollView).midX  - (geom.bounds(of: .scrollView)?.width ?? 0.0)/2
                let distance = position/coverFlowItemSize
                let sign: CGFloat = distance > 0 ? 1 : -1
                
                let distance1 = position/(coverFlowItemSize + itemSpacing)
                let distance2 = sign * max(0, abs(distance1) - 1)
                let offset = clamp(distance1 * offsetSensitivity, to: -1...1) * offsetMultiplier + distance2 * offsetMultiplier2
                
                let angle = clamp(distance * rotationSensitivity, to: -1...1) * rotationAngle
                
                return content
                    .rotation3DEffect(
                        .degrees(angle),
                        axis: (0.0, 1.0, 0.0),
                        anchor: distance > 0 ? .trailing : .leading
                    )
                    .offset(x: offset)
            }
//            .onGeometryChange(
//                for: CGFloat.self,
//                of: { geom in
//                    geom.frame(in: .scrollView).midX  - (geom.bounds(of: .scrollView)?.width ?? 0.0)/2
//                },
//                action: { position in
//                    distance = position/(coverFlowItemSize + itemSpacing)
//                })
    }
}

extension EnvironmentValues {
    @Entry var coverFlowItemSize: CGFloat = 144.0
    @Entry var coverFlowIsCurrent: Bool = false
    @Entry var coverFlowDistance: CGFloat = 1
}

enum CoverFlowIsScrollingPreference: PreferenceKey {
    static var defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

#if DEBUG
struct Item: Identifiable {
    var id: Int
    var color: Color
    
    init(_ id: Int, _ color: Color) {
        self.id = id
        self.color = color
    }
}
let items: [Item] = [
    Item(0, .pink),
    Item(1, .green),
    Item(2, .blue),
    Item(3, .orange),
    Item(4, .purple),
    Item(5, .red),
    Item(6, .green),
    Item(7, .blue),
    Item(8, .orange),
    Item(9, .purple),
]

@available(iOS 18, *)
#Preview {
    @Previewable @State var isExpanded = false
    @Previewable @StateObject var viewModel = CoverFlowViewModel(items: items, selectedItem: 0, onTap: {}, onLongTap: {})
    ZStack {
        Color.blue.opacity(0.1)
            .overlay(alignment: .top) {
                Button("Toggle") {
                    withAnimation {
                        isExpanded.toggle()
                    }
                }
            }
        CoverFlow(isExpanded: isExpanded, viewModel: viewModel) { (item: Item) -> Color in
            item.color
        }
    }
}
#endif

