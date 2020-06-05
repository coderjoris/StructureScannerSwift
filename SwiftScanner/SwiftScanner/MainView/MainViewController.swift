//
//  ViewController.swift
//  SwiftScanner
//
//  Created by Windmolders Joris on 02/06/2020.
//  Copyright © 2020 CoderJoris. All rights reserved.
//

import UIKit
import os.log

class MainViewController: UIViewController, ScanBufferDelegate {

    fileprivate var meshes = [STMesh]()
    fileprivate var files = [String]()

    @IBOutlet weak var scanMessageLabel: UILabel!
    @IBOutlet weak var batteryStatusControl: BatteryStatusUIStackView!
    @IBOutlet weak var sendButton: UIButton!
    @IBOutlet weak var deleteScansButton: UIButton!

    override func viewDidLoad() {
        super.viewDidLoad()

        self.scanMessageLabel.text = NSLocalizedString("NO_SCANS_COLLECTED_YET", comment: "")
        self.sendButton.isHidden = true
        self.deleteScansButton.isHidden = true
        self.batteryStatusControl.start()
    }
    
    init() {
        super.init(nibName: nil, bundle: nil)
        
      NotificationCenter.default.addObserver(self,
          selector: #selector(applicationWillTerminate(notification:)),
          name: UIApplication.willTerminateNotification,
          object: nil)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)

        NotificationCenter.default.addObserver(self,
            selector: #selector(applicationWillTerminate(notification:)),
            name: UIApplication.willTerminateNotification,
            object: nil)
    }
    
    @objc func applicationWillTerminate(notification: Notification) {
      deleteAllFiles()
    }

    deinit {
      NotificationCenter.default.removeObserver(self)
    }
    
    //MARK: Navigation
        
    @IBAction func unwindToMainView(segue: UIStoryboardSegue) {
        self.batteryStatusControl.start()
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)
        
        switch segue.identifier ?? "" {
        case "NewScanSegue":
            os_log("Preparing for NewScanSegue", log: OSLog.application, type: .debug)
            
            guard let scanViewController = segue.destination as? ScanViewController else {
                fatalError("Unexpected destination: \(segue.destination)")
            }

            self.batteryStatusControl.stop()

            scanViewController.scanBuffer = self
                
        default:
            return
        }
    }

    //MARK: ScanBufferDelegate
    func addScan(_ mesh: STMesh)
    {
        self.meshes.append(mesh)
        self.sendButton.isHidden = self.meshes.count < 1
        self.deleteScansButton.isHidden = self.meshes.count < 1
        let messageStringFormat = NSLocalizedString("COLLECTED__0__SCANS", comment: "")
        let message = String.init(format: messageStringFormat, self.meshes.count)
        self.scanMessageLabel.text = message
    }
    
    //MARK: - UI Callbacks
    @IBAction func sendButtonPressed(_ sender: UIButton) {
        
        self.batteryStatusControl.stop()
        
        var fileURLs = [Any]()
        for (index, mesh) in self.meshes.enumerated() {
            let fileName = String.init(format: "SCAN%03d.ZIP", index)
            guard let fileResult = saveMesh(mesh: mesh, fileName: fileName) else {
                os_log(.error, log: OSLog.application, "Error creating file: %{Public}@", fileName)
                continue
            }

            fileURLs.append(fileResult.fileURL)
            self.files.append(fileResult.filePath)
        }
        
        // Make the activityViewContoller which shows the share-view
        let activityViewController = UIActivityViewController(activityItems: fileURLs, applicationActivities: nil)
        
        // Show popover with arrow pointing to the right
        activityViewController.popoverPresentationController?.sourceView = (self.sendButton!)
        activityViewController.popoverPresentationController?.sourceRect = self.sendButton!.bounds
        activityViewController.popoverPresentationController?.permittedArrowDirections = UIPopoverArrowDirection.right

        // Anything you want to exclude
        activityViewController.excludedActivityTypes = [
            UIActivity.ActivityType.postToWeibo,
            UIActivity.ActivityType.print,
            UIActivity.ActivityType.assignToContact,
            UIActivity.ActivityType.saveToCameraRoll,
            UIActivity.ActivityType.addToReadingList,
            UIActivity.ActivityType.postToFlickr,
            UIActivity.ActivityType.postToVimeo,
            UIActivity.ActivityType.postToTencentWeibo,
            UIActivity.ActivityType.postToTwitter,
            UIActivity.ActivityType.openInIBooks,
            UIActivity.ActivityType.postToFacebook,
            UIActivity.ActivityType.markupAsPDF
        ]

        // Show the share-view
        self.present(activityViewController, animated: true, completion: { () in
            self.batteryStatusControl.start()
        })
     }
    
    @IBAction func deleteScansButtonPressed(_ sender: UIButton) {
        self.sendButton.isHidden = true
        
        deleteAllFiles()
        
        self.files.removeAll()
        self.meshes.removeAll()
        self.scanMessageLabel.text = NSLocalizedString("NO_SCANS_COLLECTED_YET", comment: "")
        self.deleteScansButton.isHidden = true
    }
    
    private func deleteAllFiles() {
        for filePath in self.files {
            do {
                if FileManager.default.fileExists(atPath: filePath)
                {
                    try FileManager.default.removeItem(atPath: filePath)
                    os_log(.debug, log: OSLog.application, "Deleted file: %{Public}@", filePath)
                }
            }
            catch {
               os_log(.error, log: OSLog.application, "Error deleting mesh: %{Public}@", error.localizedDescription)
            }
        }
    }
    
    
    private func saveMesh(mesh: STMesh, fileName : String) -> (filePath: String, fileURL: NSURL)? {
        let filePath = getDocumentsDirectory().appendingPathComponent(fileName)
        
        do {
            if FileManager.default.fileExists(atPath: filePath)
            {
                try FileManager.default.removeItem(atPath: filePath)
            }
            
            let options: [AnyHashable: Any] = [ kSTMeshWriteOptionFileFormatKey : STMeshWriteOptionFileFormat.objFileZip.rawValue]
            try mesh.write(toFile: filePath, options: options)
            return (filePath, NSURL(fileURLWithPath: filePath))
        }
        catch {
           os_log(.error, log: OSLog.application, "Error writing mesh: %{Public}@", error.localizedDescription)
        }
        
        return nil
    }
    
    private func getDocumentsDirectory() -> NSString {
           let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
           let documentsDirectory = paths[0]
           return documentsDirectory as NSString
       }
}

