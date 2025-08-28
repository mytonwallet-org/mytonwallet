//
//  SkeletonState.swift
//  MyTonWalletAir
//
//  Created by Sina on 12/7/24.
//

public enum SkeletonState {
    case loadedAll
    case loading
    case loadingMore
    public var numberOfRows: Int {
        switch self {
        case .loadedAll:
            0
        case .loading:
            0
        case .loadingMore:
            1
        }
    }
}
