//
//  ColorMapAnchor.swift
//  SwiftScanner
//
//  Created by Windmolders Joris on 03/06/2020.
//  Copyright © 2020 CoderJoris. All rights reserved.
//

import Foundation
import UIKit

internal struct ColorMapAnchor : Equatable {
    static func ==(lhs: ColorMapAnchor, rhs: ColorMapAnchor) -> Bool {
        return lhs.color == rhs.color && lhs.value == rhs.value
    }
    
    let value: CGFloat
    let color: UIColor
}

