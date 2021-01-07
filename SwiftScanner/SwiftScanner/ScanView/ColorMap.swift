//
//  ColorMap.swift
//  SwiftScanner
//
//  Created by Windmolders Joris on 03/06/2020.
//  Copyright © 2020 CoderJoris. All rights reserved.
//

import Foundation
import UIKit

internal class ColorMap {
    let anchors: [ColorMapAnchor]
    
    init(with anchors: [ColorMapAnchor])
    {
        var workAnchors = anchors;
        workAnchors.sort {
            $0.value < $1.value
        }
        
        self.anchors = workAnchors
    }
    
    public func get(at value: CGFloat) -> UIColor {
        
        if self.anchors.count <= 0 {
            return UIColor(ciColor: CIColor.black)
        }
        
        let first = self.anchors.first {
            $0.value > value
        }

        if first == nil {
            return self.anchors.last!.color
        }
        
        guard let firstIndex = (self.anchors.firstIndex{$0 == first}) else {
            return UIColor(ciColor: CIColor.black)
        }
        
        if firstIndex == 0 {
            return self.anchors.first!.color
        }
        
        let anchor0 = self.anchors[firstIndex - 1]
        let anchor1 = self.anchors[firstIndex]
        let f = (anchor1.value - value) / (anchor1.value - anchor0.value)
        let f1 = 1.0 - f
        let c0 = anchor0.color.components
        let c1 = anchor1.color.components
        let r = f * c0.red + f1 * c1.red
        let g = f * c0.green + f1 * c1.green
        let b = f * c0.blue + f1 * c1.blue
        let a = f * c0.alpha + f1 * c1.alpha

        return UIColor(red: r, green: g, blue: b, alpha: a)
    }
    
}
