//
//  BatteryStatusListenerDelegate.swift
//  SwiftScanner
//
//  Created by Windmolders Joris on 05/06/2020.
//  Copyright © 2020 CoderJoris. All rights reserved.
//

import Foundation

protocol BatteryStatusListenerDelegate {
    func updateBatteryStatus(level: Int32)
    func batteryStatusUnknown()
}
