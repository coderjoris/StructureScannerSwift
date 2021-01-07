//
//  VisualSettings.swift
//  SwiftScanner
//
//  Created by Windmolders Joris on 03/06/2020.
//  Copyright © 2020 CoderJoris. All rights reserved.
//

import Foundation
import UIKit

internal class VisualSettings {
    
    static let sharedInstance = VisualSettings()
    
    let colorMap : ColorMap
    
    private init() {
        var anchors: [ColorMapAnchor] = [ColorMapAnchor]()
        anchors.append(ColorMapAnchor(value: 35.0, color: UIColor.red))
        anchors.append(ColorMapAnchor(value: 40.0, color: UIColor.yellow))
        anchors.append(ColorMapAnchor(value: 45.0, color: UIColor.green))
        anchors.append(ColorMapAnchor(value: 60.0, color: UIColor.green))
        anchors.append(ColorMapAnchor(value: 65.0, color: UIColor.yellow))
        anchors.append(ColorMapAnchor(value: 70.0, color: UIColor.red))
        
        self.colorMap = ColorMap(with: anchors)
    }
}
