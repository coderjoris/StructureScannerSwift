# StructureScannerSwift
Guide on setting up a Swift project with Structure Scanner.
This guide has been tested with Structure SDK 0.12 and XCode 11.4.

## Project Setup
1. Create a new iOS Single View App with a StoryBoard user interface
2. Create a group 'Frameworks' and drag and drop the 'Structure.Framework' folder from the SDK underneath it in the project navigator
   - Copy items if needed: checked
   - Create Groups
   - Add to App target
3. In Project, tab 'Info', set the iOS deployment target to 13.0 (required for working with scenes)
4. Select the App target, tab 'General'
   - Select target device 'iPad' and 'landscape right' (unselect others)
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
  
Now you should be able to build and run the project

## Logging
Setup unified logging. See [Apple WWDC video](https://developer.apple.com/videos/play/wwdc2016/721/) for more information. In the sample project, an `OSLog` extensions is provided with some predefined logging categories.

## Camera access
1. Add Swift code to check for permission to use the camera in the `AppDelegate`.
2. In Info.plist, add a line `Privacy - Camera Usage Description` and set the value to `The app needs access to the camera for scanning.`

## Main View
The sample app has a main view with a button to open the scan view. This is to demonstrate how to close and re-open the scanview.

1. Rename the file `ViewController` to `MainViewController` and likewise for the class name
2. In the main storyboard, under the identity inspector, choose the controller class `MainViewController`
3. Add a button to the main view, for example 'New Scan'
4. Add a second view controller to the storyboard and create a segue from the button to the second view. Name the segue 'NewScanSegue' and make the presentation `Full Screen`

