# StructureScannerSwift
## Environment
- Structure SDK 0.12
- XCode 11.4
- Swift 5
- iOS 13+

## About
This is a guide for developing an iPad app in Swift for scanning with the Structure sensor.

Please note:
- This is **not a clone** of the Scanner sample app in the SDK
- The app uses `STCaptureSession` instead of the depreceated `STSensorController`
- The app demonstrates how to take **multiple scans** starting from a home screen, by opening and closing the scan view multiple times
- The scans can be saved via the **iOS share function**, e.g. via mail, message, airdrop, iCloud...
- There is no settings UI. These settings are hard coded: `STCaptureSessionPreset = bodyScanning`, mesh viewer uses color rendering mode only.
- A **battery status indicator** is provided separate from the scan view.
- The UI is very basic with just text buttons instead of graphics, which you can easily customize.

## What can you do with this project?
The guide below demonstrates how you can build an app with a **custom user interface**, while just copying over the files needed for capturing scans. All the bindings that you need between the custom UI and the copied code are explained.

## Screenshots
|<img src="https://github.com/coderjoris/StructureScannerSwift/blob/master/SwiftScanner/Screenshots/Screen-1.png" width="400"> |<img src="https://github.com/coderjoris/StructureScannerSwift/blob/master/SwiftScanner/Screenshots/Screen-2.png" width="400">|
|--|--|
|<img src="https://github.com/coderjoris/StructureScannerSwift/blob/master/SwiftScanner/Screenshots/Screen-3.png" width="400"> |<img src="https://github.com/coderjoris/StructureScannerSwift/blob/master/SwiftScanner/Screenshots/Screen-4.png" width="400">|
|--|--|
|<img src="https://github.com/coderjoris/StructureScannerSwift/blob/master/SwiftScanner/Screenshots/Screen-5.png" width="400"> |<img src="https://github.com/coderjoris/StructureScannerSwift/blob/master/SwiftScanner/Screenshots/Screen-6.png" width="400">|


## Project Setup
1. Create a new iOS Single View App with a StoryBoard user interface
2. Create a group 'Frameworks' and drag and drop the 'Structure.Framework' folder from the SDK underneath it in the project navigator
   - Copy items if needed: checked
   - Create Groups
   - Add to App target
3. In Project, tab 'Info', set the iOS deployment target to 13.0 (required for working with scenes)
4. Select the App target, tab 'General'
   - Select target device 'iPad', 'landscape right', 'Requires full screen' (unselect others)
   - Check 'Hide status bar during application lauch' and 'Requires full screen'
   - Under 'Frameworks, Libraries and Embedded Content':
     - Choose 'Embed & Sign' for Structure.Framework
     - Add the following frameworks (do not embed):
     
```
   Accelerate.framework
   ExternalAccessory.framework
   MessageUI.framework
   OpenGLES.framework
```

These seem to work for me. However, keep in mind that according to the SDK documentation, you also have to include these frameworks:

```
    AVFoundation.framework
    CoreImage.framework
    CoreGraphics.framework
    CoreMedia.framework
    CoreMotion.framework
    CoreVideo.framework
    Foundation.framework
    ImageIO.framework
    Metal.framework
    MetalPerformanceShaders.framework
    QuartzCore.framework
    UIKit.framework
    VideoToolbox.framework
    libz.dylib
```

5. Open the Info.plist file
   - Add a line 'Supported external accessory protocols', it has one subrow by default
   - Add two more subrows, and set the values to
   
```
   io.structure.control
   io.structure.depth
   io.structure.infrared
```

6. Add a header file to the code folder, and in the popup windows name it 'Scanner-bridging-header', add to the App target and add the following lines:

```
   #import <Structure/Structure.h>
   #import <OpenGLES/gltypes.h>
   #import <MessageUI/MessageUI.h>
```

7. Select the project, tab 'Build Settings', group 'All'
   - Search for 'Preprocessor Macros' and add the following flag to the Debug and Release: 'HAS_LIBCXX=1'
   - Search for 'Enable Bitcode' and set to false for Debug and Release
   - Search for 'Objective-C Bridging Header' and enter the name of the bridging header.
  
Now you should be able to build and run the project

## Logging
Setup unified logging. See [Apple WWDC video](https://developer.apple.com/videos/play/wwdc2016/721/) for more information. In the sample project, an `OSLog` extensions is provided with some predefined logging categories.

## Camera access
1. Add Swift code to check for permission to use the camera in the `AppDelegate`.
2. In Info.plist, add a line `Privacy - Camera Usage Description` and set the value to 'The app needs access to the camera for scanning.'

## Main View
Unlike the scanner app from the SDK, this sample app has a main view that does not allow to scan directly. You can navigate to the scan view via a button. This allows to demonstrate how to close and re-open the scanview.

1. Create a Group `MainView` and move the `ViewController` to it.
2. Rename the file `ViewController` to `MainViewController` and likewise for the class name.
3. Copy the MainViewController code from the sample to your class.
4. Copy the other swift files in the MainView folder to your project.
5. In the main storyboard, under the identity inspector, choose the controller class `MainViewController`.
6. In the storyboard, add the following UI elements:
   - Buttons for 'New Scan', 'Send' and 'Delete Scans'.
   - A Label, 'No scan collected yet'
   - A stack view for displaying the battery status. Set the class to `BatteryStatusUIStackView` in the Identity Inspector.
7. Bind the following items:
   - The text label to `@IBOutlet weak var scanMessageLabel`
   - The stack view to `@IBOutlet weak var batteryStatusControl`
   - The send button to `@IBOutlet weak var sendButton`
   - Send button Touch Up Inside to `@IBAction func sendButtonPressed`
   - The delete scans button to `@IBOutlet weak var deleteScansButton`
   - Delete Scans button Touch Up Inside to `@IBAction func deleteScansButtonPressed`

## Scan View
1. Add a second view controller to the storyboard and create a segue from the 'New Scan' button to the second view. Name the segue 'NewScanSegue' and make the presentation `Full Screen`. In the scene hierarchy, rename the View Controller to 'Scan View Controller'.
2. In the scan view, create the following UI elements:
   - Buttons for 'Scan', 'Reset', 'Done' and 'Back'.
   - Labels for 'App Status Message', 'Tracking Lost', 'Distance', 'Sensor Battery'
   - An image for low sensor battery
   - Add a PinchGestureRecognizer
   - Create an unwind segue from the 'Back' button to the main view. You'll have to create an `@IBAction` in the main view controller first, such as `unwindToMainView` in the sample. Set the unwind segue identifier to 'unwindScanToMainView' 
3. Test the app. You should be able to switch from the main view to the scan view and back, using the buttons.
4. Create a group called 'ScanView' in the project navigator. Copy the swift files under 'ScanView' from the project into it.
5. Select custom classes: in the storyboard,
   - Select the scan view controller and assign the 'ScanViewController' class in the identity inspector
   - Select the top View, rename it to 'Eview' and assign the EAGLView class in the identity inspector.
6. Bind the following items toe the controller class functions and fields:
  - Pinch Gesture Recognizer to `@IBAction func pinchGesture`
  - Eview to `@IBOutlet weak var eview`
  - App Status Message Label to `@IBOutlet weak var appStatusMessageLabel`
  - Tracking Lost Label to `@IBOutlet weak var trackingLostLabel`
  - Scan Button to `@IBOutlet weak var scanButton`
  - Scan Button Touch Up Inside to `@IBAction func scanButtonPressed`
  - Done Button to `@IBOutlet weak var doneButton`
  - Done Button Touch Up Inside to `@IBAction func doneButtonPressed`
  - Reset Button to `@IBOutlet weak var resetButton`
  - Reset Button Touch Up Inside to `@IBAction func resetButtonPressed`
  - Back Button to `@IBOutlet weak var backButton`
  - Distance Label to `@IBOutlet weak var distanceLabel`
  - Sensor Battery Label to `@IBOutlet weak var batteryLabel`
  - Sensor Battery Image to `@IBOutlet weak var sensorBatteryLowImage`
  
## Mesh View
1. Add a third view controller to the storyboard and create a segue from the Scan View Controller (via the ViewController button) to the new view. Name the segue 'ShowMeshSegue' and make the presentation `Full Screen`. In the scene hierarchy, rename the View Controller to 'Mesh View Controller'.
2. In the merh view, create the following UI elements:
   - Buttons for 'Accept', 'Reset' and 'Back'
   - Label for 'Message'
   - Pan Gesture Recognizers 'One Finger Pan' (Min Touches = Max Touches = 1) and 'Two Finger Pan' (Min Touches = Max Touches = 2)
   - Pinch Gesture Recognizer
   - Tap Gesture Recognizer
   - Create an unwind segue from the 'Back' button to the scan view. You'll have to create an `@IBAction` in the scan view controller first, such as `unwindToScanView` in the sample. Set the unwind segue identifier to 'unwindMeshToScanView'.
   - Create an unwind segue from the 'Accept' button to the main view. Set the unwind segue identifier to 'unwindMeshToMainView' 
   
4. Create a group called 'MeshView' in the project navigator. Copy the swift files under 'MeshView' from the project into it.
5. In the storyboard,
   - Select the mesh view controller and assign the 'MeshViewController' class in the identity inspector
   - Select the top View, rename it to 'Eview' and assign the EAGLView class in the identity inspector.
6. Bind the following items to the controller class functions and fields:
  - Eview to `@IBOutlet weak var eview`
  - Message label to `@IBOutlet weak var meshViewerMessageLabel`
  - Reset Button Touch Up Inside to `@IBAction func resetView`
  - One Finger Pan Gesture Recognizer to `@IBAction func oneFingerPanGesture`
  - Two Finger Pan Gesture Recognizer to `@IBAction func twoFingersPanGesture`
  - Pinch Gesture Recognizer to `@IBAction func pinchScaleGesture`
  - Tap Gesture Recognizer to `@IBAction func tapGesture`
  
## App Store
If you want to publish your app to the App Store, then you need to replace the Structure file in the SDK Framework folder with a version for arm64 only (i.e., without x64 support). To create an arm64 version in your local copy of the SDK, run this at the command line in the `Structure.framework` folder:
```
lipo Structure -extract arm64 -output Structure.arm64
```
then copy and rename the `Structure.arm64` file to the Framework folder in your project such that it replaces the Structure file.
