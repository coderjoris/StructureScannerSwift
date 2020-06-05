//
//  ScanViewController.swift
//  SwiftScanner
//
//  Created by Windmolders Joris on 03/06/2020.
//  Copyright © 2020 CoderJoris. All rights reserved.
//

import Foundation
import UIKit
import os.log
import AVFoundation

// See default initialization in: initializeDynamicOptions()
struct DynamicOptions {
    var depthAndColorTrackerIsOn = true
    var improvedTrackingIsOn = true
    var highResColoring = true
    var improvedMapperIsOn = true
    var highResMapping = true
    var depthStreamPreset = STCaptureSessionPreset.bodyScanning
}

// Volume resolution in meters

struct Options {
    // The initial scanning volume size
    // (X is left-right, Y is up-down, Z is forward-back)
    var initVolumeSizeInMeters: GLKVector3 = GLKVector3Make(0.5, 0.5, 0.5)

    // The maximum number of keyframes saved in keyFrameManager
    var maxNumKeyFrames: Int = 48

    // Colorizer quality
    var colorizerQuality: STColorizerQuality = STColorizerQuality.highQuality

    // Take a new keyframe in the rotation difference is higher than 20 degrees.
    var maxKeyFrameRotation: CGFloat = CGFloat(20 * (Double.pi / 180)) // 20 degrees

    // Take a new keyframe if the translation difference is higher than 30 cm.
    var maxKeyFrameTranslation: CGFloat = 0.3 // 30cm

    // Threshold to consider that the rotation motion was small enough for a frame to be accepted
    // as a keyframe. This avoids capturing keyframes with strong motion blur / rolling shutter.
    var maxKeyframeRotationSpeedInDegreesPerSecond: CGFloat = 1

    // Whether we should use depth aligned to the color viewpoint when Structure Sensor was calibrated.
    // This setting may get overwritten to false if no color camera can be used.
    var useHardwareRegisteredDepth: Bool = false

    // Whether to enable an expensive per-frame depth accuracy refinement.
    // Note: this option requires useHardwareRegisteredDepth to be set to false.
    var applyExpensiveCorrectionToDepth: Bool = true

    // Whether the colorizer should try harder to preserve appearance of the first keyframe.
    // Recommended for face scans.
    var prioritizeFirstFrameColor: Bool = true

    // Target number of faces of the final textured mesh.
    var colorizerTargetNumFaces: Int = 50000

    // Focus position for the color camera (between 0 and 1). Must remain fixed one depth streaming
    // has started when using hardware registered depth.
    let lensPosition: CGFloat = 0.75
}

enum ScannerState: Int {

    case cubePlacement = 0    // Defining the volume to scan
    case scanning            // Scanning
    case viewing            // Visualizing the mesh
}

// SLAM-related members.
struct SlamData {

    var initialized = false
    var showingMemoryWarning = false

    var prevFrameTimeStamp: TimeInterval = -1

    var scene: STScene? = nil
    var tracker: STTracker? = nil
    var mapper: STMapper? = nil
    var cameraPoseInitializer: STCameraPoseInitializer? = nil
    var initialDepthCameraPose: GLKMatrix4 = GLKMatrix4Identity
    var keyFrameManager: STKeyFrameManager? = nil
    var scannerState: ScannerState = .cubePlacement

    var volumeSizeInMeters = GLKVector3Make(Float.nan, Float.nan, Float.nan)
}

// Utility struct to manage a gesture-based scale.
struct PinchScaleState {

    var currentScale: CGFloat = 1
    var initialPinchScale: CGFloat = 1
}

func keepInRange(_ value: Float, minValue: Float, maxValue: Float) -> Float {
    if (value.isNaN) {
        return minValue
    }
    if (value > maxValue) {
        return maxValue
    }
    if (value < minValue) {
        return minValue
    }
    return value
}

struct AppStatus {
    let pleaseConnectSensorMessage = NSLocalizedString("PLEASE_CONNECT_STRUCTURE_SENSOR", comment: "")
    let pleaseChargeSensorMessage = NSLocalizedString("PLEASE_CHARGE_STRUCTURE_SENSOR", comment: "")

    let needColorCameraAccessMessage = NSLocalizedString("THIS_APP_REQUIRES_CAMERA_ACCESS_SCAN", comment: "")
    let needCalibratedColorCameraMessage = NSLocalizedString("NEED_CALIBRATED_COLOR_CAMERA", comment: "")

    let finalizingMeshMessage = NSLocalizedString("FINALIZING_MESH", comment: "")
    let sensorIsWakingUpMessage = NSLocalizedString("SENSOR_IS_WAKING_UP", comment: "")

    // Whether there is currently a message to show.
    var needsDisplayOfStatusMessage = false

    // Flag to disable entirely status message display.
    var statusMessageDisabled = false
}

// Display related members.
struct DisplayData {

    // OpenGL context.
    var context: EAGLContext? = nil

    // Intrinsics to use with the current frame in the undistortion shader
    var intrinsics: STIntrinsics = STIntrinsics()

    // OpenGL Texture reference for y images.
    var lumaTexture: CVOpenGLESTexture? = nil

    // OpenGL Texture reference for color images.
    var chromaTexture: CVOpenGLESTexture? = nil

    // OpenGL Texture cache for the color camera.
    var videoTextureCache: CVOpenGLESTextureCache? = nil

    // Shader to render a GL texture as a simple quad.
    var yCbCrTextureShader: STGLTextureShaderYCbCr? = nil
    var rgbaTextureShader: STGLTextureShaderRGBA? = nil

    var depthAsRgbaTexture: GLuint = 0

    // Renders the volume boundaries as a cube.
    var cubeRenderer: STCubeRenderer? = nil

    // OpenGL viewport.
    var viewport: [GLfloat] = [0, 0, 0, 0]

    // OpenGL projection matrix for the color camera.
    var colorCameraGLProjectionMatrix: GLKMatrix4 = GLKMatrix4Identity

    // OpenGL projection matrix for the depth camera.
    var depthCameraGLProjectionMatrix: GLKMatrix4 = GLKMatrix4Identity

    // Mesh rendering alpha
    var meshRenderingAlpha: Float = 0.8
    
}

class ScanViewController: UIViewController, STBackgroundTaskDelegate, ColorizeDelegate, ScanViewDelegate, UIGestureRecognizerDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    

    @IBOutlet weak var eview: EAGLView!

    @IBOutlet weak var appStatusMessageLabel: UILabel!
    @IBOutlet weak var scanButton: UIButton!
    @IBOutlet weak var resetButton: UIButton!
    @IBOutlet weak var doneButton: UIButton!
    @IBOutlet weak var trackingLostLabel: UILabel!
    @IBOutlet weak var backButton: UIButton!
    @IBOutlet weak var distanceLabel: UILabel!
    @IBOutlet weak var sensorBatteryLowImage: UIImageView!
    @IBOutlet weak var batteryLabel: UILabel!

    // Structure Sensor controller.
    //var _structureStreamConfig: STStreamConfig

    var _slamState = SlamData.init()

    var _options = Options.init()
    
    var _dynamicOptions: DynamicOptions!

    // Manages the app status messages.
    var _appStatus = AppStatus.init()

    var _display: DisplayData? = DisplayData()

    // Most recent gravity vector from IMU.
    var _lastGravity: GLKVector3!

    // Scale of the scanning volume.
    var _volumeScale = PinchScaleState()

    // Mesh viewer controllers.
    var meshViewController: MeshViewController!

    // Structure Sensor controller.
    var _captureSession: STCaptureSession!

    var _naiveColorizeTask: STBackgroundTask? = nil
    var _enhancedColorizeTask: STBackgroundTask? = nil
    var _depthAsRgbaVisualizer: STDepthToRgba? = nil

    var _useColorCamera = true
 
    weak var scanBuffer : ScanBufferDelegate?
    
    var mesh : STMesh? = nil

    deinit {
        if ( EAGLContext.current() == _display!.context) {
            EAGLContext.setCurrent(nil)
        }

        unregisterNotificationHandlers()
        
        os_log(.debug, log:OSLog.scanning, "ViewController deinit called")
    }
    
    func unregisterNotificationHandlers() {
        
        os_log(.debug, log:OSLog.scanning, "unregistering app notification handlers")
        
        NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    func registerNotificationHandlers() {
    
        os_log(.debug, log:OSLog.scanning, "Registering app notification handlers")
        
        // Make sure we get notified when the app becomes active to start/restore the sensor state if necessary.
        NotificationCenter.default.addObserver(self, selector: #selector(ScanViewController.appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.batteryLabel.text = ""
        self.sensorBatteryLowImage.isHidden = true
        self.scanButton.isHidden = true
        self.doneButton.isHidden = true
        self.backButton.isHidden = true

        // Do any additional setup after loading the view.
        _slamState.initialized = false
        _enhancedColorizeTask = nil
        _naiveColorizeTask = nil
        
        distanceLabel.layer.cornerRadius = 20

        os_log(.debug, log:OSLog.scanning, "Setting up GL")

        setupGL()

        os_log(.debug, log:OSLog.scanning, "Setting up User Interface")

        setupUserInterface()

        //os_log(.debug, log:OSLog.scanning, "Setting up Mesh view controller")

        //setupMeshViewController()

        os_log(.debug, log:OSLog.scanning, "Setting up Gestures")

        setupGestures()
        
        os_log(.debug, log:OSLog.scanning, "Setting up Capture Session")

        initializeDynamicOptions() // dynamic options used for setting up capture settings
        setupCaptureSession()

        os_log(.debug, log:OSLog.scanning, "Setting up SLAM")

        setupSLAM()
        
        // Later, we’ll set this true if we have a device-specific calibration
        _useColorCamera = true

        registerNotificationHandlers()
        
        enterCubePlacementState()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // The framebuffer will only be really ready with its final size after the view appears.
        self.eview.setFramebuffer()

        setupGLViewport()

        updateAppStatusMessage()

        // We will connect to the sensor when we receive appDidBecomeActive.
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // in an unwind segue, the view controller is dismissed
        // in a modal segue, the view controller is not dismissed
        if isBeingDismissed {
            cleanup()
        }
    }
    
    @objc func appDidBecomeActive() {

        os_log(.debug, log:OSLog.scanning, "App did become active")

        ConnectToStructureScanner()
        
        // Abort the current scan if we were still scanning before going into background since we
        // are not likely to recover well.
        if _slamState.scannerState == .scanning {
            resetButtonPressed(resetButton)
        }
    }
    
    
    private func ConnectToStructureScanner()
    {
        runBatteryStatusTimer()
        if currentStateNeedsSensor() {
            _captureSession.streamingEnabled = true;
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        respondToMemoryWarning()
    }

    func initializeDynamicOptions() {

        _dynamicOptions = DynamicOptions()
        _dynamicOptions.highResColoring = videoDeviceSupportsHighResColor()
    }

    func setupUserInterface() {
        // Fully transparent message label, initially.
        appStatusMessageLabel.alpha = 0

        // Make sure the label is on top of everything else.
        appStatusMessageLabel.layer.zPosition = 100
    }

    // Make sure the status bar is disabled (iOS 7+)
    override var prefersStatusBarHidden : Bool {
        return true
    }

    func setupGestures()
    {
        // Register pinch gesture for volume scale adjustment.
        let pinchGestureRecognizer = UIPinchGestureRecognizer.init(target: self, action: #selector(self.pinchGesture(_:)))
        pinchGestureRecognizer.delegate = self
        self.view.addGestureRecognizer(pinchGestureRecognizer)
    }

    func presentMeshViewer(_ mesh: STMesh) {
        performSegue(withIdentifier: "ShowMeshSegue", sender: mesh)
    }
    
    func setupMeshViewController(meshViewController: MeshViewController, mesh: STMesh) {

        self.meshViewController = meshViewController
        
        meshViewController.scanView = self
        meshViewController.scanBuffer = self.scanBuffer
        meshViewController.colorizer = self

        meshViewController.setupGL(_display!.context!)
        meshViewController.colorEnabled = _useColorCamera
        meshViewController.mesh = mesh
        meshViewController.setCameraProjectionMatrix(_display!.depthCameraGLProjectionMatrix)

        // Sample a few points to estimate the volume center
        var totalNumVertices: Int32 = 0

        for  i in 0..<mesh.numberOfMeshes() {
            totalNumVertices += mesh.number(ofMeshVertices: Int32(i))
        }

        // The sample step if we need roughly 1000 sample points
        let sampleStep = Int(max(1, totalNumVertices / 1000))
        var sampleCount: Int32 = 0
        var volumeCenter = GLKVector3Make(0, 0, 0)

        for i in 0..<mesh.numberOfMeshes() {
            let numVertices = Int(mesh.number(ofMeshVertices: i))
            let vertex = mesh.meshVertices(Int32(i))

            for j in stride(from: 0, to: numVertices, by: sampleStep) {
                let v = (vertex?[Int(j)])!
                volumeCenter = GLKVector3Add(volumeCenter, v)
                sampleCount += 1
            }
        }
        
        if sampleCount > 0 {
            volumeCenter = GLKVector3DivideScalar(volumeCenter, Float(sampleCount))
        } else {
            volumeCenter = GLKVector3MultiplyScalar(_slamState.volumeSizeInMeters, 0.5)
        }
        
        meshViewController.resetMeshCenter(volumeCenter)
        
        meshViewController.showColorRenderingMode()
    }

    func enterCubePlacementState() {

        // Only show the scan buttons if the sensor is ready
        // To avoid flickering on and off when initially connecting
        if _captureSession.sensorMode == .ready {
            showScanControls()
        }
        
        // Cannot be lost in cube placement mode.
        trackingLostLabel.isHidden = true

        _captureSession.streamingEnabled = true;
        _captureSession.properties = STCaptureSessionPropertiesSetColorCameraAutoExposureISOAndWhiteBalance();

        _slamState.scannerState = .cubePlacement

        updateIdleTimer()
    }

    func enterScanningState() {

        // This can happen if the UI did not get updated quickly enough.
        if !_slamState.cameraPoseInitializer!.lastOutput.hasValidPose.boolValue {
            os_log(.error, log:OSLog.scanning, "Not accepting to enter into scanning state since the initial pose is not valid.")
            return
        }

        os_log(.debug, log:OSLog.scanning, "Enter Scanning state")

        // Show/Hide buttons.
        scanButton.isHidden = true
        resetButton.isHidden = false
        backButton.isHidden = false
        doneButton.isHidden = false
        
        // Prepare the mapper for the new scan.
        setupMapper()

        _slamState.tracker!.initialCameraPose = _slamState.initialDepthCameraPose

        // We will lock exposure during scanning to ensure better coloring.
        _captureSession.properties = STCaptureSessionPropertiesLockAllColorCameraPropertiesToCurrent();

        _slamState.scannerState = .scanning
    }

    // Note: the "enterViewingState" method from the sample app is split into stopScanningState and enterViewingState
    private func stopScanningState() {
        // Cannot be lost in view mode.
        hideTrackingErrorMessage()
        
        _appStatus.statusMessageDisabled = true
        updateAppStatusMessage()
        
        // Hide the Scan/Done/Reset/Autostop button.
        scanButton.isHidden = true
        doneButton.isHidden = true
        resetButton.isHidden = true

        // never hide the back button
        backButton.isHidden = false

        if (_captureSession.occWriter.isWriting)
           {
            let success = _captureSession.occWriter.stopWriting()
               if (!success)
               {
                // Should fail instead - but not using OCC anyway
                   os_log(.error, log:OSLog.scanning, "Could not properly stop OCC writer.")
               }
           }
        
        _captureSession.streamingEnabled = false;
    }
    
    private func enterViewingState() {
        _slamState.mapper!.finalizeTriangleMesh()

        self.mesh = _slamState.scene!.lockAndGetMesh()

        presentMeshViewer(self.mesh!)

        _slamState.scene!.unlockMesh()

        _slamState.scannerState = .viewing

        updateIdleTimer()
    }

    //MARK: -  Structure Sensor Management

    func currentStateNeedsSensor() -> Bool {

        switch _slamState.scannerState {

        // Initialization and scanning need the sensor.
        case .cubePlacement, .scanning:
            return true

        // Other states don't need the sensor.
        default:
            return false
        }
    }

    //MARK: - IMU

    func processDeviceMotion(_ motion: CMDeviceMotion, error: NSError?) {

        if _slamState.scannerState == .cubePlacement {

            // Update our gravity vector, it will be used by the cube placement initializer.
            _lastGravity = GLKVector3Make(Float(motion.gravity.x), Float(motion.gravity.y), Float(motion.gravity.z))
        }

        if _slamState.scannerState == .cubePlacement || _slamState.scannerState == .scanning {
            // The tracker is more robust to fast moves if we feed it with motion data.
            _slamState.tracker?.updateCameraPose(with: motion)
        }
    }

    //MARK: - UI Callbacks
    
    func onSLAMOptionsChanged() {

        // A full reset to force a creation of a new tracker.
        resetSLAM()
        clearSLAM()
        setupSLAM()

        // Restore the volume size cleared by the full reset.
        adjustVolumeSize( volumeSize: _slamState.volumeSizeInMeters)
    }

    func adjustVolumeSize(volumeSize: GLKVector3) {

        // Make sure the volume size remains between 10 centimeters and 3 meters.
        let x = keepInRange(volumeSize.x, minValue: 0.1, maxValue: 3)
        let y = keepInRange(volumeSize.y, minValue: 0.1, maxValue: 3)
        let z = keepInRange(volumeSize.z, minValue: 0.1, maxValue: 3)

        _slamState.volumeSizeInMeters = GLKVector3.init(v: (x, y, z))

        _slamState.cameraPoseInitializer!.volumeSizeInMeters = _slamState.volumeSizeInMeters
        _display!.cubeRenderer!.adjustCubeSize(_slamState.volumeSizeInMeters)
    }
    
    @IBAction func scanButtonPressed(_ sender: UIButton) {
        // Uncomment the following lines to enable OCC writing
        /*
        let success = _captureSession.occWriter.startWriting("[AppDocuments]/Scanner.occ", appendDateAndExtension:false);
        
        if (!success)
        {
            os_log(.error, log:OSLog.scanning, "Could not properly start OCC writer.");
        }*/

        enterScanningState()
    }

    @IBAction func resetButtonPressed(_ sender: UIButton) {
        resetSLAM()
    }

    @IBAction func doneButtonPressed(_ sender: UIButton) {
        stopScanning()
        enterViewingState()
    }
    
    // Manages whether we can let the application sleep.
    func updateIdleTimer() {
        if isStructureConnected() && currentStateNeedsSensor() {
            // Do not let the application sleep if we are currently using the sensor data.
            UIApplication.shared.isIdleTimerDisabled = true
        } else {
            // Let the application sleep if we are only viewing the mesh or if no sensors are connected.
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
    
    func showTrackingMessage(_ message: String) {
        trackingLostLabel.text = message
        trackingLostLabel.isHidden = false
        distanceLabel.isHidden = true
    }

    func hideTrackingErrorMessage() {
        trackingLostLabel.isHidden = true
    }

    func showAppStatusMessage(_ msg: String) {
        if Thread.current.isMainThread {
            self.showAppStatusMessage_OnMainThread(msg)
        }
        else{
            DispatchQueue.main.async {
                self.showAppStatusMessage_OnMainThread(msg)
            }
        }
    }

    private func showAppStatusMessage_OnMainThread(_ msg: String) {
        assert(Thread.current.isMainThread)

        self.hideScanControls()
        
        _appStatus.needsDisplayOfStatusMessage = true
        view.layer.removeAllAnimations()
        
        appStatusMessageLabel.text = msg
        appStatusMessageLabel.isHidden = false
        
        // Progressively show the message label.
        view!.isUserInteractionEnabled = false
        UIView.animate(withDuration: 0.5, animations: {
            self.appStatusMessageLabel.alpha = 1.0
        })
        view!.isUserInteractionEnabled = true
    }

    func hideAppStatusMessage() {
        if Thread.current.isMainThread {
            self.hideAppStatusMessage_OnMainThread()
        }
        else{
            DispatchQueue.main.async {
                self.hideAppStatusMessage_OnMainThread()
            }
        }
    }
    
    func hideAppStatusMessage_OnMainThread() {
        assert(Thread.current.isMainThread)
        
        if !_appStatus.needsDisplayOfStatusMessage {
            return
        }

        _appStatus.needsDisplayOfStatusMessage = false
        view.layer.removeAllAnimations()

        UIView.animate(withDuration: 0.5, animations: {
            self.appStatusMessageLabel.alpha = 0
            }, completion: { _ in
                // If nobody called showAppStatusMessage before the end of the animation, do not hide it.
                if !self._appStatus.needsDisplayOfStatusMessage {

                    // Could be nil if the self is released before the callback happens.
                    if self.view != nil {
                        self.appStatusMessageLabel.isHidden = true
                        self.view.isUserInteractionEnabled = true
                        
                        // Restore the scan controls that were hidden for displaying the message, but only
                        // if the sensor is ready, otherwise other messages may follow and the scan controls
                        // will appear to flicker on and off
                        if (self._captureSession.sensorMode == .ready) && (self._slamState.scannerState == .cubePlacement)
                        {
                            self.showScanControls()
                        }
                    }
                }
        })
    }

    func updateAppStatusMessage() {
        
        // Skip everything if we should not show app status messages (e.g. in viewing state).
        if _appStatus.statusMessageDisabled {
            hideAppStatusMessage()
            return
        }
        
        let userInstructions = _captureSession.userInstructions
        
        let needToConnectSensor = userInstructions.contains(.needToConnectSensor)
        let needToChargeSensor = userInstructions.contains(.needToChargeSensor)
        let needToAuthorizeColorCamera = userInstructions.contains(.needToAuthorizeColorCamera)
        //let needToUpgradeFirmware = userInstructions.contains(.firmwareUpdateRequired)

        // If you don't want to display the overlay message when an approximate calibration
        // is available use `_captureSession.calibrationType >= STCalibrationTypeApproximate`
        //let needToRunCalibrator = userInstructions.contains(.needToRunCalibrator)
        
        if (needToConnectSensor)
        {
            showAppStatusMessage(_appStatus.pleaseConnectSensorMessage)
            return;
        }

        if (_captureSession.sensorMode == .wakingUp)
        {
            showAppStatusMessage(_appStatus.sensorIsWakingUpMessage)
            return;
        }

        if (needToChargeSensor)
        {
            showAppStatusMessage(_appStatus.pleaseChargeSensorMessage)
        }

        // Color camera permission issues.
        if (needToAuthorizeColorCamera)
        {
            showAppStatusMessage(_appStatus.needColorCameraAccessMessage)
            return;
        }
        
        // If we reach this point, no status to show.
        hideAppStatusMessage()
    }
    
    @IBAction func pinchGesture(_ sender: UIPinchGestureRecognizer) {

        if sender.state == .began {
            if _slamState.scannerState == .cubePlacement {
                _volumeScale.initialPinchScale = _volumeScale.currentScale / sender.scale
            }
        } else if sender.state == .changed {

            if _slamState.scannerState == .cubePlacement {

                // In some special conditions the gesture recognizer can send a zero initial scale.
                if !_volumeScale.initialPinchScale.isNaN {

                    _volumeScale.currentScale = sender.scale * _volumeScale.initialPinchScale

                    // Don't let our scale multiplier become absurd
                    _volumeScale.currentScale = CGFloat(keepInRange(Float(_volumeScale.currentScale), minValue: 0.01, maxValue: 1000))

                    let newVolumeSize: GLKVector3 = GLKVector3MultiplyScalar(_options.initVolumeSizeInMeters, Float(_volumeScale.currentScale))

                    adjustVolumeSize( volumeSize: newVolumeSize)
                }
            }
        }
    }
    
    internal func cleanup()
    {
        self.stopBatteryStatusTimer()
        
        _captureSession.streamingEnabled = false

        resetSLAM()
        clearSLAM()
        
        if self.meshViewController != nil {
            self.meshViewController = nil
        }

        _captureSession.delegate = nil
        
        self.mesh = nil
                
        os_log(.debug, log:OSLog.scanning, "ViewController dismissed")
    }
        
    private func stopScanning() {
        stopScanningState()
    }

    private func hideScanControls() {
        self.scanButton.isHidden = true
        self.distanceLabel.isHidden = true
        self.resetButton.isHidden = true
    }

    internal func showScanControls() {
        scanButton.isHidden = false
        doneButton.isHidden = true
        resetButton.isHidden = true
        backButton.isHidden = false
    }
    

    //MARK: - ColorizeDelegate

    internal func stopColorizing() {

        // If we are running colorize work, we should cancel it.
        if _naiveColorizeTask != nil {
            _naiveColorizeTask!.cancel()
            _naiveColorizeTask = nil
        }

        if _enhancedColorizeTask != nil {
            _enhancedColorizeTask!.cancel()
            _enhancedColorizeTask = nil
        }
        
        self.meshViewController.hideMeshViewerMessage()
    }

    func meshViewDidRequestColorizing(_ mesh: STMesh, previewCompletionHandler: @escaping () -> Void, enhancedCompletionHandler: @escaping () -> Void) -> Bool {

        os_log(.debug, log:OSLog.scanning, "meshViewDidRequestColorizing")
        
        if _naiveColorizeTask != nil || _enhancedColorizeTask != nil { // already one running?
            
            os_log(.debug, log:OSLog.scanning, "Already running background task!")
            return false
        }
        
        let handler = DispatchWorkItem { [weak self] in
            previewCompletionHandler()
            self?.meshViewController.mesh = mesh
            self?.performEnhancedColorize(mesh, enhancedCompletionHandler: enhancedCompletionHandler)
        }
        
        let colorizeCompletionHandler : (Error?) -> Void = { [weak self] error in
            if error != nil {
                os_log(.error, log:OSLog.scanning, "Error during colorizing: %{Public}@", error?.localizedDescription ?? "Unknown Error")
            } else {
                DispatchQueue.main.async(execute: handler)
                self?._naiveColorizeTask?.delegate = nil
                self?._naiveColorizeTask = nil
            }
        }

        do
        {
            _naiveColorizeTask = try STColorizer.newColorizeTask(with: mesh,
                                                                  scene: _slamState.scene,
                                                                  keyframes: _slamState.keyFrameManager!.getKeyFrames(),
                                                                  completionHandler: colorizeCompletionHandler,
                                                                  options: [kSTColorizerTypeKey : STColorizerType.perVertex.rawValue,
                                                                            kSTColorizerPrioritizeFirstFrameColorKey: _options.prioritizeFirstFrameColor]
            )

            if _naiveColorizeTask != nil {
                // Release the tracking and mapping resources. It will not be possible to resume a scan after this point
                _slamState.mapper!.reset()
                _slamState.tracker!.reset()
                
                os_log(.debug, log:OSLog.scanning, "Assigning delegate to naive colorizing task")
                _naiveColorizeTask?.delegate = self

                os_log(.debug, log:OSLog.scanning, "Starting naive colorizing task")
                _naiveColorizeTask?.start()

                return true
            }
        }
        catch {
            os_log(.error, log:OSLog.scanning, "Exception while creating colorize task: %{Public}@", error.localizedDescription)
            return false
        }
        
        return true
    }

    func backgroundTask(_ sender: STBackgroundTask!, didUpdateProgress progress: Double) {

        let processingStringFormat = NSLocalizedString("PROCESSING_PCT__0__", comment: "")

        if sender == _naiveColorizeTask {
            DispatchQueue.main.async(execute: {
                self.meshViewController.showMeshViewerMessage(String.init(format: processingStringFormat, Int(progress*20)))
            })
        } else if sender == _enhancedColorizeTask {

            DispatchQueue.main.async(execute: {
            self.meshViewController.showMeshViewerMessage(String.init(format: processingStringFormat, Int(progress*80)+20))
            })
        }
    }
    
    func performEnhancedColorize(_ mesh: STMesh, enhancedCompletionHandler: @escaping () -> Void) {

        let handler = DispatchWorkItem { [weak self] in
            enhancedCompletionHandler()
            self?.meshViewController.mesh = mesh
        }
        
        let colorizeCompletionHandler : (Error?) -> Void = { [weak self] error in
            if error != nil {
                os_log(.error, log:OSLog.scanning, "Error during colorizing: %{Public}@", error!.localizedDescription)
            } else {
                DispatchQueue.main.async(execute: handler)
                
                self?._enhancedColorizeTask?.delegate = nil
                self?._enhancedColorizeTask = nil
            }
        }
        
        _enhancedColorizeTask = try! STColorizer.newColorizeTask(with: mesh, scene: _slamState.scene, keyframes: _slamState.keyFrameManager!.getKeyFrames(), completionHandler: colorizeCompletionHandler, options: [kSTColorizerTypeKey : STColorizerType.textureMapForObject.rawValue, kSTColorizerPrioritizeFirstFrameColorKey: _options.prioritizeFirstFrameColor, kSTColorizerQualityKey: _options.colorizerQuality.rawValue, kSTColorizerTargetNumberOfFacesKey: _options.colorizerTargetNumFaces])

        if _enhancedColorizeTask != nil {

            // We don't need the keyframes anymore now that the final colorizing task was started.
            // Clearing it now gives a chance to early release the keyframe memory when the colorizer
            // stops needing them.
            _slamState.keyFrameManager!.clear()

            os_log(.debug, log:OSLog.scanning, "Starting enhanced colorizing task")
            _enhancedColorizeTask!.delegate = self
            _enhancedColorizeTask!.start()
        }
    }
    
    func respondToMemoryWarning() {
        os_log(.debug, log:OSLog.scanning, "respondToMemoryWarning")
        switch _slamState.scannerState {
        case .viewing:
            // If we are running a colorizing task, abort it
            if _enhancedColorizeTask != nil && !_slamState.showingMemoryWarning {

                _slamState.showingMemoryWarning = true

                // stop the task
                _enhancedColorizeTask!.cancel()
                _enhancedColorizeTask = nil

                // hide progress bar
                self.meshViewController.hideMeshViewerMessage()

                let alertCtrl = UIAlertController(
                    title: NSLocalizedString("MEMORY_LOW", comment: ""),
                    message: NSLocalizedString("COLORIZING_WAS_CANCELED", comment: ""),
                    preferredStyle: .alert)

                let handler : (UIAlertAction) -> Void = {[weak self] _ in
                    self?._slamState.showingMemoryWarning = false
                }
                
                let okAction = UIAlertAction(
                    title: NSLocalizedString("OK", comment: ""),
                    style: .default,
                    handler: handler)

                alertCtrl.addAction(okAction)

                // show the alert in the meshViewController
                self.meshViewController.present(alertCtrl, animated: true, completion: nil)
            }

        case .scanning:

            if !_slamState.showingMemoryWarning {

                _slamState.showingMemoryWarning = true

                let alertCtrl = UIAlertController(
                    title: NSLocalizedString("MEMORY_LOW", comment: ""),
                    message: NSLocalizedString("SCANNING_WILL_BE_STOPPED", comment: ""),
                    preferredStyle: .alert)

                let handler : (UIAlertAction) -> Void = {[weak self] _ in
                    self?._slamState.showingMemoryWarning = false
                    self?.stopScanningState()
                    self?.enterViewingState()
                }

                let okAction = UIAlertAction(
                    title: NSLocalizedString("OK", comment: ""),
                    style: .default,
                    handler: handler)

                alertCtrl.addAction(okAction)

                // show the alert
                present(alertCtrl, animated: true, completion: nil)
            }

        default:
            // not much we can do here
            break
        }
    }

    
    //MARK: - Battery
    var batteryStatusTimer = Timer()
    var batteryStatusRefreshSeconds: Double = 3.0
    
    private func runBatteryStatusTimer() {
        stopBatteryStatusTimer()
        batteryStatusTimer = Timer.scheduledTimer(timeInterval: batteryStatusRefreshSeconds, target: self,   selector: (#selector(ScanViewController.updateBatteryStatus)), userInfo: nil, repeats: true)
    }
    
    private func stopBatteryStatusTimer() {
        batteryStatusTimer.invalidate()
    }
    
    @objc internal func updateBatteryStatus() {

        if let level = _captureSession?.sensorBatteryLevel {
            let pcttext = String(format: "%02d", level)
            self.batteryLabel.text = "Sensor battery: \(pcttext)%"
            self.sensorBatteryLowImage.isHidden = level > 5
        }
        else {
            self.batteryLabel.text = ""
            self.sensorBatteryLowImage.isHidden = true
        }
   }
    
    //MARK: - Distance to Target
    
    internal func showDistanceToTargetAndHeelIndicator(_ distance: Float) {
        if distance != Float.nan {
            let distanceFormatString = NSLocalizedString("__0__CM", comment: "")
            let formattedDistance = String(format: distanceFormatString, distance)
            let formattedDistanceNan = NSLocalizedString("NAN_CM", comment: "")
            if formattedDistance == formattedDistanceNan {
                distanceLabel.text = ""
                distanceLabel.isHidden = true
            }
            else {
                distanceLabel.isHidden = false
                distanceLabel.text = formattedDistance
                distanceLabel.backgroundColor = VisualSettings.sharedInstance.colorMap.get(at: CGFloat(distance))
            }
        }
        else {
            distanceLabel.text = ""
            distanceLabel.isHidden = true
        }
    }
    
    //MARK: Navigation
    @IBAction func unwindToScanView(segue: UIStoryboardSegue) {

        switch segue.identifier ?? "" {
        case "unwindMeshToScanView":
            os_log("unwinding segue unwindMeshToScanView", log: OSLog.meshView, type: .debug)
            
            if self.meshViewController != nil {
                self.meshViewController = nil
            }
            _appStatus.statusMessageDisabled = false
            updateAppStatusMessage()
            _captureSession.streamingEnabled = false
            resetSLAM()

        default:
            return
        }
       }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)
        
        switch segue.identifier ?? "" {
        case "ShowMeshSegue":
            os_log("Preparing for ShowMeshSegue", log: OSLog.meshView, type: .debug)
            
            guard let meshViewController = segue.destination as? MeshViewController else {
                fatalError("Unexpected destination: \(segue.destination)")
            }

            guard let mesh = sender as? STMesh else {
                fatalError("Cannot convert segue sender to mesh")
            }

            setupMeshViewController(meshViewController: meshViewController, mesh: mesh)
                
        default:
            return
        }
        
    }
}


// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertToUIApplicationOpenExternalURLOptionsKeyDictionary(_ input: [String: Any]) -> [UIApplication.OpenExternalURLOptionsKey: Any] {
    return Dictionary(uniqueKeysWithValues: input.map { key, value in (UIApplication.OpenExternalURLOptionsKey(rawValue: key), value)})
}

