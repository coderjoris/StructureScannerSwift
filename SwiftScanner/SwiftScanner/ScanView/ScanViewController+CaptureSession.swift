//
//    This file is a Swift port of the Structure SDK sample app "Scanner".
//    Copyright © 2020 Occipital, Inc. All rights reserved.
//    http://structure.io
//
//  ViewController+CaptureSession.swift
//
//  Ported to Swift 5 by Windmolders Joris on 03/06/2020.
//  - Renamed to ScanViewController+CaptureSession.swift

import Foundation
import AVFoundation
import os.log

extension ScanViewController : STCaptureSessionDelegate {
    
    // MARK: Capture Session Setup
    
    // Function modified for SDK 0.9
    func videoDeviceSupportsHighResColor() -> Bool {
    
    // High Resolution Color format is width 2592, height 1936.
    // Most recent devices support this format at 30 FPS.
    // However, older devices may only support this format at a lower framerate.
    // In your Structure Sensor is on firmware 2.0+, it supports depth capture at FPS of 24.
    
    let testVideoDevice = AVCaptureDevice.default(for: AVMediaType(rawValue: convertFromAVMediaType(AVMediaType.video)))
        if testVideoDevice == nil {
            
            assertionFailure()
        }

        let base420f: UInt32 = 875704422  // decimal val of '420f' (full range YCbCr)
        let fourCharCodeStr = base420f as FourCharCode
        for format in (testVideoDevice?.formats)! {
    
            let firstFrameRateRange = format.videoSupportedFrameRateRanges[0]
            
            let formatMinFps = (firstFrameRateRange as AnyObject).minFrameRate
            let formatMaxFps = (firstFrameRateRange as AnyObject).maxFrameRate

            if ( formatMaxFps! < 15 // Max framerate too low.
                || formatMinFps! > 30 // Min framerate too high.
                || (formatMaxFps! == 24 && formatMinFps! > 15)) { // We can neither do the 24 FPS max framerate, nor fall back to 15.
                continue
            }

            let formatDesc  = format.formatDescription
            let fourCharCode = CMFormatDescriptionGetMediaSubType(formatDesc)
    
            let videoFormatDesc = formatDesc
            let formatDims = CMVideoFormatDescriptionGetDimensions(videoFormatDesc)
    
            if ( 2592 != formatDims.width ) {
                continue
            }
    
            if ( 1936 != formatDims.height ) {
                continue
            }
            
            if format.isVideoBinned {
                continue
            }
    
            // we only support full range YCbCr for now
            if fourCharCode != fourCharCodeStr {
                continue
            }

            // All requirements met.
            return true
        }
    
        // No acceptable high-res format was found.
        return false
    }
    
    func setupCaptureSession() {

        // Clear / reset the capture session if it already exists
        if (_captureSession == nil)
        {
            // Create an STCaptureSession instance
            _captureSession = STCaptureSession.new()
        }
        else
        {
            _captureSession?.streamingEnabled = false;
        }

        guard let captureSession = _captureSession else {
            return
        }
        
        var resolution = _dynamicOptions.highResColoring ?
            STCaptureSessionColorResolution.resolution2592x1936 :
            STCaptureSessionColorResolution.resolution640x480;

        if (!self.videoDeviceSupportsHighResColor())
        {
            os_log(.info, log: OSLog.sensor, "Device does not support high resolution color mode!");
            resolution = STCaptureSessionColorResolution.resolution640x480;
        }
        
        let depthStreamPreset = _dynamicOptions.depthStreamPreset
        
        let sensorConfig : [AnyHashable: Any] = [kSTCaptureSessionOptionColorResolutionKey: resolution.rawValue,
                                            kSTCaptureSessionOptionDepthSensorVGAEnabledIfAvailableKey: false,
                                            kSTCaptureSessionOptionColorMaxFPSKey: 30.0 as Float,
                                            kSTCaptureSessionOptionDepthSensorEnabledKey: true,
                                            kSTCaptureSessionOptionUseAppleCoreMotionKey: true,
                                            kSTCaptureSessionOptionDepthStreamPresetKey: depthStreamPreset.rawValue,
                                            kSTCaptureSessionOptionSimulateRealtimePlaybackKey: true]

        
        // Set the lens detector off, and default lens state as "non-WVL" mode
        captureSession.lens = STLens.normal;
        captureSession.lensDetection = STLensDetectorState.off;

        // Set ourself as the delegate to receive sensor data.
        captureSession.delegate = self;
        
        captureSession.startMonitoring(options: sensorConfig)
    }
    
    
    func isStructureConnected() -> Bool {
        
        guard let captureSession = _captureSession else {
            return false
        }
        
        return captureSession.sensorMode.rawValue > STCaptureSessionSensorMode.notConnected.rawValue;
    }

    // MARK: -  STCaptureSession delegate methods
    func captureSession(_ captureSession: STCaptureSession!, colorCameraDidEnter mode: STCaptureSessionColorCameraMode) {
        switch(mode){
        case .permissionDenied, .ready:
            break;
        case .unknown:
            // cannot throw because as in the Obj C example, because the delegate is not marked throwable
            preconditionFailure("The color camera has entered an unknown state.")
        default:
            // cannot throw because as in the Obj C example, because the delegate is not marked throwable
            preconditionFailure("The color camera has entered an unhandled state.")
       }

        self.updateAppStatusMessage()
    }
    
    func captureSession(_ captureSession: STCaptureSession!, sensorDidEnter mode: STCaptureSessionSensorMode) {
        switch(mode){
        case .ready, .wakingUp, .standby, .notConnected, .batteryDepleted:
            break;
        case .unknown:
            // cannot throw because as in the Obj C example, because the delegate is not marked throwable
            preconditionFailure("The color camera has entered an unknown mode.")
        default:
            // cannot throw because as in the Obj C example, because the delegate is not marked throwable
            preconditionFailure("The color camera has entered an unhandled mode.")
        }
        
        self.updateAppStatusMessage()
    }
    
    func captureSession(_ captureSession: STCaptureSession!, sensorChargerStateChanged chargerState: STCaptureSessionSensorChargerState)
    {
        switch (chargerState){
        case []: // .connected corresponds to empty bitplain (NS_OPTIONS)
            break;
        case .disconnected:
                // Do nothing, we only need to handle low-power notifications based on the sensor mode.
                break;
        case .unknown:
                // cannot throw because as in the Obj C example, because the delegate is not marked throwable
                preconditionFailure("The color camera has entered an unknown charger state.")
            default:
                // cannot throw because as in the Obj C example, because the delegate is not marked throwable
                preconditionFailure("The color camera has entered an unhandled charger state.")
        }

        self.updateAppStatusMessage()
    }
    
    func captureSession(_ captureSession: STCaptureSession!, didStart avCaptureSession: AVCaptureSession)
    {
        // Initialize our default video device properties once the AVCaptureSession has been started.
        _captureSession?.properties = STCaptureSessionPropertiesSetColorCameraAutoExposureISOAndWhiteBalance()
    }
    
    func captureSession(_ captureSession: STCaptureSession!, didStop avCaptureSession: AVCaptureSession)
    {
    }
    
    func captureSession(_ captureSession: STCaptureSession!, didOutputSample sample: [AnyHashable : Any]?, type: STCaptureSessionSampleType)
    {
        guard let sample = sample else {
            os_log(.debug, log: OSLog.sensor, "Output sample not available")
            return
        }
        
        switch (type)
        {
        case .sensorDepthFrame:
            if let depthFrame = sample[kSTCaptureSessionSampleEntryDepthFrame] as? STDepthFrame {
                if (_slamState.initialized)
                {
                    processDepthFrame(depthFrame, colorFrame: nil)
                    // Scene rendering is triggered by new frames to avoid rendering the same view several times.
                    renderSceneForDepthFrame(depthFrame, colorFrame: nil)
                }
            }
        case .iosColorFrame:
                // Skipping until a pair is returned.
                break;
        case .synchronizedFrames:
                if let depthFrame = sample[kSTCaptureSessionSampleEntryDepthFrame] as? STDepthFrame,
                    let colorFrame = sample[kSTCaptureSessionSampleEntryIOSColorFrame] as? STColorFrame {
                    if (_slamState.initialized)
                    {
                        processDepthFrame(depthFrame, colorFrame: colorFrame)
                        // Scene rendering is triggered by new frames to avoid rendering the same view several times.
                        renderSceneForDepthFrame(depthFrame, colorFrame: colorFrame)
                    }
            }
        case .deviceMotionData:
            if let deviceMotion = sample[kSTCaptureSessionSampleEntryDeviceMotionData] as? CMDeviceMotion {
                processDeviceMotion(deviceMotion, error: nil)
            }
        case .unknown:
                // cannot throw because as in the Obj C example, because the delegate is not marked throwable
                preconditionFailure("Unknown STCaptureSessionSampleType!")
        default:
            os_log(.debug, log: OSLog.sensor, "Skipping Capture Session sample type: %{Public}@", String(describing: type));
        }
    }
    
    func captureSession(_ captureSession: STCaptureSession, onLensDetectorOutput detectedLensStatus: STDetectedLensStatus)
    {
        switch (detectedLensStatus)
        {
        case .normal:
                // Detected a WVL is not attached to the bracket.
                os_log(.info, log: OSLog.sensor, "Detected that the WVL is off!");
        case .wideVisionLens:
                // Detected a WVL is attached to the bracket.
                os_log(.info, log: OSLog.sensor, "Detected that the WVL is on!");
        case .performingInitialDetection:
                // Triggers immediately when detector is turned on. Can put a message here
                // showing the user that the detector is working and they need to pan the
                // camera for best results
                os_log(.info, log: OSLog.sensor, "Performing initial detection!");
        case .unsure:
                break;
        default:
                // cannot throw because as in the Obj C example, because the delegate is not marked throwable
                preconditionFailure("Unknown STDetectedLensStatus!")
        }
    }
    
    // Helper function inserted by Swift 4.2 migrator.
    private func convertFromAVMediaType(_ input: AVMediaType) -> String {
        return input.rawValue
    }
}
