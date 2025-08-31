//
//  MTWCapacitorVC.swift
//  MyTonWallet
//
//  Created by Sina on 10/15/24.
//

import Capacitor

class MTWCapacitorVC: CAPBridgeViewController {
    var onCapacitorLoadCompletion: (() -> Void)? = nil
    override func capacitorDidLoad() {
        onCapacitorLoadCompletion?()
    }
}
