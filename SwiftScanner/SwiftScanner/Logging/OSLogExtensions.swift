//
//  OSLogExtensions.swift
//  SwiftScanner
//
//  Created by Windmolders Joris on 03/06/2020.
//  Copyright © 2020 CoderJoris. All rights reserved.
//

import Foundation
import os.log

extension OSLog {
    private static var subsystem = "com.coderjoris.swiftscanner"

    internal static let application = OSLog(subsystem: subsystem, category: "Application")

    internal static let patientView = OSLog(subsystem: subsystem, category: "Main View")

    internal static let sensor = OSLog(subsystem: subsystem, category: "Sensor")
    
    internal static let meshView = OSLog(subsystem: subsystem, category: "Mesh View")
    
    internal static let scanning = OSLog(subsystem: subsystem, category: "Scanning")

    internal static let rendering = OSLog(subsystem: subsystem, category: "Rendering")
}
