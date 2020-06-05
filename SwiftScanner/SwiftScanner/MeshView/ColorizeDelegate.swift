//
//  ColorizeDelegate.swift
//  SwiftScanner
//
//  Created by Windmolders Joris on 05/06/2020.
//  Copyright © 2020 CoderJoris. All rights reserved.
//

import Foundation

protocol ColorizeDelegate: class {
    func meshViewDidRequestColorizing(_ mesh: STMesh,  previewCompletionHandler: @escaping () -> Void, enhancedCompletionHandler: @escaping () -> Void) -> Bool
    func stopColorizing()
}
