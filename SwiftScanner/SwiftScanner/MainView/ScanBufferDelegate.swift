//
//  ScanBufferDelegate.swift
//  SwiftScanner
//
//  Created by Windmolders Joris on 05/06/2020.
//  Copyright © 2020 CoderJoris. All rights reserved.
//

import Foundation

protocol ScanBufferDelegate: class {
    func addScan(_ mesh: STMesh)
}
