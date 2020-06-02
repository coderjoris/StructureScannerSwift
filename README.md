# StructureScannerSwift
Guide on setting up a Swift project with Structure Scanner.
This guide has been tested with Structure SDK 0.12 and XCode 11.4.

## Project Setup
1. Create a new iOS Single View App with a StoryBoard user interface
2. Create a group 'Frameworks' and drag and drop the 'Structure.Framework' folder from the SDK underneath it in the project navigator
   - Copy items if needed: checked
   - Create Groups
   - Add to App target
3. In Project, tab 'Info', set the iOS deployment target to 10.0
4. Select the App target, tab 'General'
   - Select target device 'iPad' and 'landscape right' (unselect others)
   - Check 'Hide status bar during application lauch' and 'Requires full screen'
   - Under 'Frameworks, Libraries and Embedded Content':
     - Choose 'Embed & Sign' for Structure.Framework
     - Add the following frameworks:
     
```
   ExternalAccessory.framework
   Accelerate.framework
```
   
