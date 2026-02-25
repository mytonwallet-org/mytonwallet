import Kingfisher
import SwiftUI
import UIComponents
import WalletCore

// MARK: - Dapp Folders Grid

struct ExploreScreenDappFoldersView: View {
    let folders: [ExploreScreenDappFolderVM]
    let onTapDapp: (_ site: ApiSite) -> Void
    let onTapMore: (_ categoryId: Int) -> Void

    private let spacingBetweenRows: Double = 20
    private let spacingBetweenColumns: Double = 16
    
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 160), spacing: spacingBetweenColumns)]
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: spacingBetweenRows) {
            ForEach(folders, id: \.categoryName) { folderVM in
                DappFolderView(vm: folderVM, onTapDapp: onTapDapp, onTapMore: onTapMore)
                    .shadow(style: .light)
            }
        }
    }
}

// MARK: - FolderView

struct DappFolderView: View {
    let vm: ExploreScreenDappFolderVM
    let onTapDapp: (ApiSite) -> Void
    let onTapMore: (_ categoryId: Int) -> Void

    private let cornerRadius: Double = 26
    private let edgesInset: Double = 12
    private let interItemSpacing: Double = 14

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Folder icons

            Grid(horizontalSpacing: interItemSpacing, verticalSpacing: interItemSpacing) {
                switch vm.dapps {
                case let .one(site):
                    dappsRow(site, nil)
                    emptyDappsRow()
                case let .two(site1, site2):
                    dappsRow(site1, site2)
                    emptyDappsRow()
                case let .three(site1, site2, site3):
                    dappsRow(site1, site2)
                    dappsRow(site3, nil)
                case let .four(site1, site2, site3, lastItemVariant):
                    dappsRow(site1, site2)
                    additionalDappsRow(thirdSite: site3, lastItemVariant: lastItemVariant)
                }
            }
            .padding(edgesInset)
            .aspectRatio(1, contentMode: .fit)
            .background { Color.air.folderFill }
            .innerStrokeOverlay(Color.air.groupedItem, cornerRadius: cornerRadius, lineWidth: 1, clipToStroke: true)

            Spacer().frame(height: 6)

            // MARK: Folder name

            Text(vm.categoryName)
                .font(.system(size: 12, weight: .medium))
                .frame(height: 12)
        }
    }

    private func dappsRow(_ site1: ApiSite, _ site2: ApiSite?) -> some View {
        GridRow {
            DappImageView(iconURL: site1.icon, onTap: { onTapDapp(site1) })

            if let site2 {
                DappImageView(iconURL: site2.icon, onTap: { onTapDapp(site2) })
            } else {
                GridCellPlaceholder()
            }
        }
    }

    private func emptyDappsRow() -> some View {
        GridRow { GridCellPlaceholder(); GridCellPlaceholder() }
    }

    private func additionalDappsRow(thirdSite: ApiSite,
                                    lastItemVariant: ExploreScreenDappFolderVM.LastItemVariant) -> some View {
        GridRow {
            DappImageView(iconURL: thirdSite.icon, onTap: { onTapDapp(thirdSite) })

            switch lastItemVariant {
            case let .singleDapp(fourthSite):
                DappImageView(iconURL: fourthSite.icon, onTap: { onTapDapp(fourthSite) })

            case let .moreDapps(moreDapps):
                MoreDappsView(firstIconURL: moreDapps.first.icon,
                              secondIconURL: moreDapps.second.icon,
                              restIconURLs: moreDapps.rest.map { $0.icon },
                              onTap: { onTapMore(vm.categoryId) })
                    .padding(3)
            }
        }
    }
}

// MARK: - More Dapps View

extension DappFolderView {
    private struct DappImageView: View {
        let iconURL: String
        let onTap: () -> Void

        private let cornerRadius: Double = 18

        var body: some View {
            if let url = URL(string: iconURL) {
                KFImage(url).resizable()
                    .loadDiskFileSynchronously(false)
                    .aspectRatio(contentMode: .fill)
                    .onTapWithHighlightInScroll(action: onTap)
                    .clipShape(.rect(cornerRadius: cornerRadius))
            } else {
                GridCellPlaceholder()
            }
        }
    }

    /// Show 4x4 grid of images for 2-4 Dapps
    private struct MoreDappsView: View {
        let firstIconURL: String
        let secondIconURL: String
        let restIconURLs: [String]
        let onTap: () -> Void

        private let interItemSpacing: Double = 6
        @State private var isHighlighted: Bool = false

        var body: some View {
            Grid(horizontalSpacing: interItemSpacing, verticalSpacing: interItemSpacing) {
                GridRow {
                    siteImage(urlString: firstIconURL)
                    siteImage(urlString: secondIconURL)
                }
                GridRow {
                    siteImage(urlString: restIconURLs[at: 0])
                    siteImage(urlString: restIconURLs[at: 1])
                }
            }
            .onTap(isPressedBinding: $isHighlighted, action: onTap)
        }

        @ViewBuilder private func siteImage(urlString: String?) -> some View {
            if let urlString, let url = URL(string: urlString) {
                KFImage(url).resizable()
                    .loadDiskFileSynchronously(false)
                    .aspectRatio(contentMode: .fill)
                    .highlightOverlay(isHighlighted)
                    .clipShape(.rect(cornerRadius: 7))
            } else {
                GridCellPlaceholder()
            }
        }
    }
}
