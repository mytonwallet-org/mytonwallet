import SwiftUI

struct SectionHeaderView: View {
    let title: String
    let topInset: CGFloat

    init(title: String, topInset: CGFloat = 27) {
        self.title = title
        self.topInset = topInset
    }

    var body: some View {
        Text(title).font(.system(size: 22.5, weight: .bold))
            .kerning(-0.25)
            .frame(height: 24)
            .padding(EdgeInsets(top: topInset, leading: 0, bottom: 14, trailing: 0))
    }
}
