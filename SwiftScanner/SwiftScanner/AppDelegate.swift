//
//  AppDelegate.swift
//  SwiftScanner
//
//  Created by Windmolders Joris on 02/06/2020.
//  Copyright © 2020 CoderJoris. All rights reserved.
//

import UIKit
import AVFoundation
import os.log

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {



    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let authStatus = AVCaptureDevice.authorizationStatus(for: AVMediaType.video)
         
         if authStatus != .authorized {
            os_log(.error, log: OSLog.application, "Not authorized to use the camera!")
             AVCaptureDevice.requestAccess(for: AVMediaType.video, completionHandler: { granted in
             })
         }
        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }


}

