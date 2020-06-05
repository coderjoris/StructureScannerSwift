//
//  BatteryStatusMonitor.swift
//  SwiftScanner
//
//  Created by Windmolders Joris on 05/06/2020.
//  Copyright © 2020 CoderJoris. All rights reserved.
//

import Foundation

class BatteryStatusMonitor : NSObject, STCaptureSessionDelegate {
    
    private var _captureSession: STCaptureSession!
    private var _sensorMode: STCaptureSessionSensorMode
    public var _delegate: BatteryStatusListenerDelegate?
    
    public override init() {
        _sensorMode = .unknown
        super.init()
    }
    
    public func start() {
        setupCaptureSession()
        runBatteryStatusTimer()
    }
    
    public func stop() {
        stopBatteryStatusTimer()
        cleanupCaptureSession()        
    }
    
    //MARK: STCaptureSessionDelegate
    public func captureSession(_ captureSession: STCaptureSession!, sensorDidEnter mode: STCaptureSessionSensorMode) {
        _sensorMode = mode
    }
    
    public func captureSession(_ captureSession: STCaptureSession!, colorCameraDidEnter mode: STCaptureSessionColorCameraMode) {
        
    }
    
    //MARK: Capture session management
    private func setupCaptureSession() {

          // Clear / reset the capture session if it already exists
          if (_captureSession == nil)
          {
              // Create an STCaptureSession instance
              _captureSession = STCaptureSession.new()
          }
          else
          {
              _captureSession.streamingEnabled = false;
          }
          
          let resolution = STCaptureSessionColorResolution.resolution640x480;
          let depthStreamPreset = STCaptureSessionPreset.bodyScanning
          
          let sensorConfig : [AnyHashable: Any] = [kSTCaptureSessionOptionColorResolutionKey: resolution.rawValue,
                                              kSTCaptureSessionOptionDepthSensorVGAEnabledIfAvailableKey: false,
                                              kSTCaptureSessionOptionColorMaxFPSKey: 30.0 as Float,
                                              kSTCaptureSessionOptionDepthSensorEnabledKey: true,
                                              kSTCaptureSessionOptionUseAppleCoreMotionKey: true,
                                              kSTCaptureSessionOptionDepthStreamPresetKey: depthStreamPreset.rawValue,
                                              kSTCaptureSessionOptionSimulateRealtimePlaybackKey: true]

          
          // Set the lens detector off, and default lens state as "non-WVL" mode
          _captureSession.lens = STLens.normal;
          _captureSession.lensDetection = STLensDetectorState.off;

          // Set ourself as the delegate to receive sensor data.
          _captureSession.delegate = self;
          
          _captureSession.startMonitoring(options: sensorConfig)
      }
    
    private func cleanupCaptureSession() {
        _captureSession?.delegate = nil
        _captureSession = nil
    }
    
    //Mark: - Battery status timer
    var batteryStatusTimer = Timer()
    var batteryStatusRefreshSeconds: Double = 3.0
    
    private func runBatteryStatusTimer() {
        stopBatteryStatusTimer()
        batteryStatusTimer = Timer.scheduledTimer(timeInterval: batteryStatusRefreshSeconds, target: self,   selector: (#selector(BatteryStatusMonitor.updateBatteryStatus)), userInfo: nil, repeats: true)
    }
    
    private func stopBatteryStatusTimer() {
        batteryStatusTimer.invalidate()
    }
    
    @objc internal func updateBatteryStatus() {
        if _sensorMode == .ready {
            if let batteryPercentage = _captureSession?.sensorBatteryLevel {
                _delegate?.updateBatteryStatus(level: batteryPercentage)
            }
        }
    }
    
    
}
