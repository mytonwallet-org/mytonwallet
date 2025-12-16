
import UIKit
import SwiftUI
import Foundation

public enum IconConfig: View {
    case system(String)
    case air(String)
    
    public var body: some View {
        switch self {
        case .system(let systemName):
            Image(systemName: systemName)
                .padding(.vertical, -8)
        case .air(let name):
            Image.airBundle(name)
                .padding(.vertical, -8)
        }
    }
}

public enum MenuItem: Identifiable, View {
    
    case button(id: String, title: String, leadingIcon: IconConfig? = nil, trailingIcon: IconConfig? = nil, isDangerous: Bool = false, action: @MainActor () -> Void, dismissOnSelect: Bool = true, reportWidth: Bool = true)
    case customView(id: String, view: () -> AnyView, height: CGFloat, width: CGFloat? = nil)
    case wideSeparator(id: String = UUID().uuidString)
    
    public var id: String {
        switch self {
        case .button(let id, _, _, _, _, _, _, _), .customView(let id, _, _, _), .wideSeparator(let id):
            return id
        }
    }
    
    public var body: some View {
        switch self {
        case let .button(id, title, leadingIcon, trailingIcon, isDangerous, action, dismissOnSelect, _):
            WMenuButton(id: id, title: title, leadingIcon: leadingIcon, trailingIcon: trailingIcon, action: action, dismissOnSelect: dismissOnSelect)
                .foregroundStyle(isDangerous ? .red : .primary)
        case .customView(_, let view, _, _):
            view()
        case .wideSeparator:
            WideSeparator()
        }
    }
    
    var height: CGFloat {
        switch self {
        case .button:
            44
        case .customView(_, _, let height, _):
            height
        case .wideSeparator:
            8
        }
    }
    
    var width: CGFloat? {
        switch self {
        case let .button(_, title, leadingIcon, trailingIcon, _, _, _, reportWidth):
            if reportWidth {
                var width = title.size(withAttributes: [.font: UIFont.systemFont(ofSize: 17)]).width
                width += 40 // padding
                if leadingIcon != nil {
                    width += 64
                }
                if trailingIcon != nil {
                    width += 64
                }
                return width
            }
        case .customView(_, _, _, let width):
            return width
        case .wideSeparator:
            break
        }
        return nil
    }
}

public struct DisplayMenuItem: View, Identifiable {
    
    var menuItem: MenuItem
    var showSeparator: Bool
    
    public var body: some View {
        menuItem
            .overlay(alignment: .bottom) {
                if showSeparator {
                    Rectangle()
                        .fill(Color.air.menuSeparator)
                        .frame(height: 0.333)
                }
            }
    }
    
    public var id: String { menuItem.id }
}

public struct MenuConfig {
    
    var submenuId: String
    var menuItems: [MenuItem]
    
    public init(submenuId: String = "0", menuItems: [MenuItem]) {
        self.submenuId = submenuId
        self.menuItems = menuItems
    }
    
    var displayMenuItems: [DisplayMenuItem] {
        var displayMenuItems: [DisplayMenuItem] = []
        for (menuItem, next) in zip(menuItems, menuItems.dropFirst()) {
            let showSeparator = if case .button = menuItem, case .button = next { true } else { false }
            displayMenuItems.append(DisplayMenuItem(menuItem: menuItem, showSeparator: showSeparator))
        }
        if let menuItem = menuItems.last {
            displayMenuItems.append(DisplayMenuItem(menuItem: menuItem, showSeparator: false))
        }
        return displayMenuItems
    }
    
    var totalHeight: CGFloat {
        menuItems.reduce(into: 0) { $0 += $1.height }
    }
    
    var requestedWidth: CGFloat? {
        menuItems.compactMap(\.width).max()
    }
}


public struct MenuViewFromConfig: View {
    
    public var menuConfig: MenuConfig
    public var width: CGFloat
    
    @Environment(\.containerSize) private var containerSize: CGSize
    
    public init(menuConfig: MenuConfig, width: CGFloat) {
        self.menuConfig = menuConfig
        self.width = width
    }
    
    public var body: some View {
        let fits = menuConfig.totalHeight <= containerSize.height
        let height = min(containerSize.height, menuConfig.totalHeight)
        Group {
            if fits {
                content
                    .preference(key: HasScrollPreference.self, value: false)
            } else {
                ScrollView {
                    content
                }
                .scrollIndicators(.hidden)
                .preference(key: HasScrollPreference.self, value: true)
            }
        }
        .preference(key: SizePreference.self, value: [menuConfig.submenuId: CGSize(width: requestedWidth, height: height)])
    }
    
    @ViewBuilder
    var content: some View {
        LazyVGrid(columns: [.init(.fixed(width))], spacing: 0) {
            ForEach(menuConfig.displayMenuItems) { menuItem in
                menuItem
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: width)
    }
    
    var requestedWidth: CGFloat {
        min(containerSize.width, menuConfig.requestedWidth ?? 200)
    }
}


@available(iOS 18, *)
#Preview {
    @Previewable @State var menuContext = MenuContext()
    
    MenuViewFromConfig(menuConfig: MenuConfig(menuItems: [
        MenuItem.button(id: "0-0", title: "Item 0000", action: {}, reportWidth: true),
        MenuItem.wideSeparator(),
        MenuItem.button(id: "0-1", title: "Item 1", action: {}),
        MenuItem.button(id: "0-2", title: "Item 2", action: {}),
        MenuItem.button(id: "0-3", title: "Item 3", action: {}),
        MenuItem.button(id: "0-4", title: "Item 4", action: {}),
        MenuItem.button(id: "0-5", title: "Item 5", action: {}),
        MenuItem.button(id: "0-6", title: "Item 6", action: {}),
        MenuItem.button(id: "0-7", title: "Item 7", action: {}),
        MenuItem.button(id: "0-8", title: "Item 8", action: {}),
//        MenuItem.button(id: "0-9", title: "Item 9"),
//        MenuItem.wideSeparator(),
//        MenuItem.button(id: "0-10", title: "Item 10"),
    ]), width: 200)
        .environment(\.containerSize, CGSize(width: 300, height: 500))
        .environment(menuContext)
        .padding()
}
