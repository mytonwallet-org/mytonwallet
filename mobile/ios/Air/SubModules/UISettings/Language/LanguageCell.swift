
import SwiftUI
import UIComponents
import WalletContext

struct LanguageCell: View {
    
    var language: Language
    var isCurrent: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(language.name)
                    .font17h22()
                Text(language.nativeName)
                    .airFont15h18(weight: .regular)
                    .foregroundStyle(Color.air.secondaryLabel)
            }
            .offset(y: -1)
            .frame(maxWidth: .infinity, alignment: .leading)
            if isCurrent {
                Image.airBundle("AirCheckmark")
                    .foregroundStyle(.tint)
            }
        }
    }
}

extension LanguageCell {
    static func makeRegistration(languages: [Language]) -> UICollectionView.CellRegistration<UICollectionViewListCell, String> {
        UICollectionView.CellRegistration<UICollectionViewListCell, String> { cell, _, langCode in
            let language = languages.first(id: langCode)!
            let isCurrent = LocalizationSupport.shared.langCode == langCode
            cell.configurationUpdateHandler = { cell, state in
                cell.contentConfiguration = UIHostingConfiguration {
                    LanguageCell(language: language, isCurrent: isCurrent)
                }
                .background {
                    CellBackgroundHighlight(isHighlighted: state.isHighlighted)
                }
                .margins(.all, EdgeInsets(top: 9, leading: 20, bottom: 9, trailing: 18))
                .minSize(height: 62)
            }
        }
    }
}
