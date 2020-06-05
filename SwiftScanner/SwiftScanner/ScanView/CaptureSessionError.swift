//
//  CaptureSessionError.swift
//  SwiftScanner
//
//  Created by Windmolders Joris on 03/06/2020.
//  Copyright © 2020 CoderJoris. All rights reserved.
//

import Foundation

enum CaptureSessionError: Error {
    case invalidCameraMode(reason: String)
}
