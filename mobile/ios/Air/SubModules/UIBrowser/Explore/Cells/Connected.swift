
import Kingfisher
import SwiftUI
import WalletCore
import WalletContext

struct ConnectedDappCell: View {
    
    var dapp: ApiDapp
    
    var isHighlighted: Bool
    
    var body: some View {
        HStack(spacing: 0) {
            KFImage(URL(string: dapp.iconUrl))
                .resizable()
                .loadDiskFileSynchronously(false)
                .aspectRatio(contentMode: .fill)
                .clipShape(.containerRelative)
            Text(dapp.name)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 8)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: true)
        }
        .background {
            Color(WTheme.background)
        }
        .highlightOverlay(isHighlighted)
        .clipShape(.containerRelative)
        .shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: 1.5)
        .containerShape(.rect(cornerRadius: 10))
    }
}

struct ConnectedSettingsCell: View {
    
    var isHighlighted: Bool
    
    var body: some View {
        Image(uiImage: UIImage.airBundle("SettingsIcon"))
            .renderingMode(.template)
            .resizable()
            .foregroundStyle(Color(WTheme.secondaryLabel))
            .aspectRatio(contentMode: .fill)
            .padding(6)
            .background {
                Color(WTheme.background)
            }
            .highlightOverlay(isHighlighted)
            .clipShape(.containerRelative)
            .shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: 1.5)
            .containerShape(.rect(cornerRadius: 10))
    }
}

struct ConnectedDappCellLarge: View {
    
    var dapp: ApiDapp
    
    var isHighlighted: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            KFImage(URL(string: dapp.iconUrl))
                .placeholder {
                    Color.airBundle("FolderFillColor")
                }
                .resizable()
                .loadDiskFileSynchronously(false)
                .aspectRatio(contentMode: .fill)
                .highlightOverlay(isHighlighted)
                .clipShape(.rect(cornerRadius: 14))
                .frame(width: 60, height: 60)
                
            Text(dapp.name)
                .font(.system(size: 12, weight: .medium))
                .padding(.top, 7)
                .padding(.bottom, 8)
                .lineLimit(1)
                .truncationMode(.tail)
                .allowsTightening(true)
                .frame(maxWidth: 68)
        }
        .clipShape(.containerRelative)
        .contentShape(.containerRelative)
        .containerShape(.rect)
    }
}

struct ConnectedSettingsCellLarge: View {
    
    var isHighlighted: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            Image.airBundle("Settings60")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .highlightOverlay(isHighlighted)
                .background {
                    Color.airBundle("FolderFillColor")
                }
                .clipShape(.rect(cornerRadius: 14))
                .frame(width: 60, height: 60)
                
            Text(lang("Settings"))
                .font(.system(size: 12, weight: .medium))
                .padding(.top, 7)
                .padding(.bottom, 8)
                .lineLimit(1)
                .truncationMode(.tail)
                .allowsTightening(true)
                .frame(maxWidth: 68)
        }
        .clipShape(.containerRelative)
        .contentShape(.containerRelative)
        .containerShape(.rect)
    }
}



#if DEBUG
#Preview {
    VStack(spacing: 40) {
        HStack(spacing: 8) {
            ConnectedDappCell(dapp: .sample, isHighlighted: false)
            ConnectedSettingsCell(isHighlighted: false)
        }
        .aspectRatio(contentMode: .fit)
        .frame(height: 36)
        HStack(spacing: 8) {
            ConnectedDappCellLarge(dapp: .sample, isHighlighted: false)
                .border(.red)

            ConnectedSettingsCellLarge(isHighlighted: false)
                .border(.red)
        }
        .aspectRatio(contentMode: .fit)
    }
//    .border(Color.red)
//    .padding(20)
//    .background(.blue)
}
#endif
