//
//  AirWidgetBundle.swift
//  AirWidget
//
//  Created by nikstar on 23.09.2025.
//

import WidgetKit
import SwiftUI

@main
struct AirWidgetBundle: WidgetBundle {
    var body: some Widget {
        TokenWithChartWidget()
        TokenWidget()
        ActionsWidget()
    }
}
