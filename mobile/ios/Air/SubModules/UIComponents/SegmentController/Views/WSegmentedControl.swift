//
//  WSegmentedControl.swift
//  MyTonWalletAir
//
//  Created by nikstar on 15.11.2025.
//

import SwiftUI
import UIKit
import WalletContext
import Perception

public final class WSegmentedControl: HostingView {
    
    public let model: SegmentedControlModel
    
    public init(model: SegmentedControlModel) {
        self.model = model
        super.init {
            SegmentedControl(model: model)
        }
    }
}
