//
//    This file is a Swift port of the Structure SDK sample app "Scanner".
//    Copyright © 2016 Occipital, Inc. All rights reserved.
//    http://structure.io
//
//  ViewController+SLAM.swift
//
//  Ported by Christopher Worley on 8/20/16.
//
//  Ported to Swift 5 by Windmolders Joris on 03/06/2020.
//  - renamed to ScanViewController+SLAM.swift
//  - Adapted to the latest version of the Scanner sample in the SDK
//  - Using STCaptureSession iso STSensorController
//  - Support distance label in the scan view
//


import Foundation
import UIKit
import os.log

func deltaRotationAngleBetweenPosesInDegrees(_ previousPose: GLKMatrix4, newPose: GLKMatrix4) -> Float {
    
    // Transpose is equivalent to inverse since we will only use the rotation part.
    let deltaPose: GLKMatrix4 = GLKMatrix4Multiply(newPose, GLKMatrix4Transpose(previousPose))
    
    // Get the rotation component of the delta pose
    let deltaRotationAsQuaternion = GLKQuaternionMakeWithMatrix4(deltaPose)
    
    // Get the angle of the rotation
    let angleInDegree = GLKQuaternionAngle(deltaRotationAsQuaternion) / Float(Double.pi) * 180
    
    return angleInDegree
}

func computeTrackerMessage(_ hints: STTrackerHints) -> String? {
    
    if hints.trackerIsLost {
        return NSLocalizedString("TRACKING_LOST_PLEASE_REALIGN", comment: "")
    }
    
    if hints.modelOutOfView {
        return NSLocalizedString("PUT_MODEL_BACK_IN_VIEW", comment: "")
    }
    
    if hints.sceneIsTooClose {
        return NSLocalizedString("PLEASE_STEP_BACK", comment: "")
    }

    return nil
}

//MARK: - SLAM

extension ScanViewController {
    
    func setupSLAM() {
        
        if _slamState.initialized {
            return
        }

        // Initialize the scene.
        _slamState.scene = STScene.init(context: _display!.context)
        
        // Initialize the camera pose tracker.
        let trackerOptions: [AnyHashable: Any] = [kSTTrackerTypeKey: _dynamicOptions.depthAndColorTrackerIsOn ? STTrackerType.depthAndColorBased.rawValue : STTrackerType.depthBased.rawValue,
                                                  kSTTrackerTrackAgainstModelKey: true, // tracking against the model is much better for close range scanning.
                                                  kSTTrackerQualityKey: STTrackerQuality.accurate.rawValue,
                                                  kSTTrackerBackgroundProcessingEnabledKey: true,
                                                  kSTTrackerSceneTypeKey: STTrackerSceneType.object.rawValue,
                                                  kSTTrackerLegacyKey: !_dynamicOptions.improvedTrackingIsOn]

        // Initialize the camera pose tracker.
        _slamState.tracker = STTracker.init(scene: _slamState.scene!, options: trackerOptions)
        
        // Default volume size set in options struct
        if _slamState.volumeSizeInMeters.x.isNaN {
            _slamState.volumeSizeInMeters = _options.initVolumeSizeInMeters
        }
        
        // The mapper will be initialized when we start scanning.
        
        // Setup the cube placement initializer.
        _slamState.cameraPoseInitializer = STCameraPoseInitializer.init(volumeSizeInMeters: _slamState.volumeSizeInMeters, options: [kSTCameraPoseInitializerStrategyKey: STCameraPoseInitializerStrategy.tableTopCube.rawValue])
        
        // Set up the cube renderer with the current volume size.
        _display!.cubeRenderer = STCubeRenderer.init(context: _display!.context)
        
        // Set up the initial volume size.
        adjustVolumeSize(volumeSize: _slamState.volumeSizeInMeters)
        
        // Enter cube placement state
        enterCubePlacementState()

        let keyframeManagerOptions: [AnyHashable: Any] = [
            kSTKeyFrameManagerMaxSizeKey : _options.maxNumKeyFrames,
            kSTKeyFrameManagerMaxDeltaTranslationKey : _options.maxKeyFrameTranslation,
            kSTKeyFrameManagerMaxDeltaRotationKey : _options.maxKeyFrameRotation] // 20 degrees.
        
        _slamState.keyFrameManager = STKeyFrameManager.init(options: keyframeManagerOptions)
        
        _depthAsRgbaVisualizer = STDepthToRgba.init(options: [kSTDepthToRgbaStrategyKey: STDepthToRgbaStrategy.gray.rawValue])
        
        _slamState.initialized = true
    }
    
    func resetSLAM() {

        _slamState.prevFrameTimeStamp = -1.0
        _slamState.mapper?.reset()
        _slamState.tracker?.reset()
        _slamState.scene?.clear()
        _slamState.keyFrameManager?.clear()
        
        enterCubePlacementState()
    }
    
    func clearSLAM() {
        _slamState.initialized = false
        _slamState.scene = nil
        _slamState.tracker = nil
        _slamState.mapper = nil
        _slamState.keyFrameManager = nil
    }
    
    func setupMapper() {
        
        if _slamState.mapper != nil {
            _slamState.mapper = nil // make sure we first remove a previous mapper.
        }
        
        // Here, we set a larger volume bounds size when mapping in high resolution.
        let lowResolutionVolumeBounds: Float = 125
        let highResolutionVolumeBounds: Float = 200
        
        var voxelSizeInMeters: Float = _slamState.volumeSizeInMeters.x /
            (_dynamicOptions.highResMapping ? highResolutionVolumeBounds : lowResolutionVolumeBounds)
        
        // Avoid voxels that are too small - these become too noisy.
        voxelSizeInMeters = keepInRange(voxelSizeInMeters, minValue: 0.003, maxValue: 0.2)
        
        // Compute the volume bounds in voxels, as a multiple of the volume resolution.
        let volumeBounds = GLKVector3.init(v:
            (roundf(_slamState.volumeSizeInMeters.x / voxelSizeInMeters),
                roundf(_slamState.volumeSizeInMeters.y / voxelSizeInMeters),
                roundf(_slamState.volumeSizeInMeters.z / voxelSizeInMeters)
        ))
        
        let volumeSizeText = String.init(format: "[Mapper] volumeSize (m): %f %f %f volumeBounds: %.0f %.0f %.0f (resolution=%f m)",
                              _slamState.volumeSizeInMeters.x, _slamState.volumeSizeInMeters.y, _slamState.volumeSizeInMeters.z,
                              volumeBounds.x, volumeBounds.y, volumeBounds.z,
                              voxelSizeInMeters )
        os_log(.info, log:OSLog.scanning, "volumeSize (m): %{Public}@", volumeSizeText)
        
        let mapperOptions: [AnyHashable: Any] =
            [kSTMapperLegacyKey : !_dynamicOptions.improvedMapperIsOn,
             kSTMapperVolumeResolutionKey : voxelSizeInMeters,
             kSTMapperVolumeBoundsKey: [volumeBounds.x, volumeBounds.y, volumeBounds.z],
             kSTMapperVolumeHasSupportPlaneKey: _slamState.cameraPoseInitializer!.lastOutput.hasSupportPlane.boolValue,
             kSTMapperEnableLiveWireFrameKey: false,
             ]
        
        _slamState.mapper = STMapper.init(scene: _slamState.scene, options: mapperOptions)
    }
    
    func maybeAddKeyframeWithDepthFrame(_ depthFrame: STDepthFrame, colorFrame: STColorFrame?, depthCameraPoseBeforeTracking: GLKMatrix4) -> String? {
        
        if colorFrame == nil {
            return nil // nothing to do
        }

        // Only consider adding a new keyframe if the accuracy is high enough.
        if _slamState.tracker!.poseAccuracy.rawValue < STTrackerPoseAccuracy.approximate.rawValue {
            return nil
        }
    
        let depthCameraPoseAfterTracking = _slamState.tracker!.lastFrameCameraPose
    
        // Make sure the pose is in color camera coordinates in case we are not using registered depth.
        let iOSColorFromDepthExtrinsics = depthFrame.iOSColorFromDepthExtrinsics;
        let colorCameraPoseAfterTracking =
            GLKMatrix4Multiply(depthCameraPoseAfterTracking(), GLKMatrix4Invert(iOSColorFromDepthExtrinsics(), nil));

        var showHoldDeviceStill = false
    
        // Check if the viewpoint has moved enough to add a new keyframe
        // OR if we don't have a keyframe yet
        if _slamState.keyFrameManager!.wouldBeNewKeyframe(withColorCameraPose: colorCameraPoseAfterTracking) {
    
            let isFirstFrame = _slamState.prevFrameTimeStamp < 0
            var canAddKeyframe = false
    
            if isFirstFrame { // always add the first frame.
                canAddKeyframe = true
            }
            else { // for others, check the speed.
            
                var deltaAngularSpeedInDegreesPerSecond = Float.greatestFiniteMagnitude
                let deltaSeconds = depthFrame.timestamp - _slamState.prevFrameTimeStamp

                // Compute angular speed
                deltaAngularSpeedInDegreesPerSecond = deltaRotationAngleBetweenPosesInDegrees (depthCameraPoseBeforeTracking, newPose: depthCameraPoseAfterTracking()) / Float(deltaSeconds)

                // If the camera moved too much since the last frame, we will likely end up
                // with motion blur and rolling shutter, especially in case of rotation. This
                // checks aims at not grabbing keyframes in that case.
                if CGFloat(deltaAngularSpeedInDegreesPerSecond) < _options.maxKeyframeRotationSpeedInDegreesPerSecond {
                    canAddKeyframe = true
                }
            }
    
            if canAddKeyframe {
            
                _slamState.keyFrameManager!.processKeyFrameCandidate(
                    withColorCameraPose: colorCameraPoseAfterTracking,
                    colorFrame: colorFrame,
                    depthFrame: nil) // Spare the depth frame memory, since we do not need it in keyframes.
            }
            else {
                // Moving too fast. Hint the user to slow down to capture a keyframe
                // without rolling shutter and motion blur.
                showHoldDeviceStill = true
            }
        }
    
        if showHoldDeviceStill {
            return NSLocalizedString("PLEASE_HOLD_STILL", comment: "")
        }
    
        return nil
    }
    
    func updateMeshAlphaForPoseAccuracy(_ poseAccuracy: STTrackerPoseAccuracy) {
    
        switch (poseAccuracy) {
        
        case .high, .approximate:
            _display!.meshRenderingAlpha = 0.8
            
        case .low:
            _display!.meshRenderingAlpha = 0.4
            
        case .veryLow, .notAvailable:
            _display!.meshRenderingAlpha = 0.1;

        default:
            os_log(.error, log:OSLog.scanning, "STTracker unknown pose accuracy.");
        }
    }

    func processDepthFrame(_ depthFrame: STDepthFrame, colorFrame: STColorFrame?) {

        if _options.applyExpensiveCorrectionToDepth
        {
            assert(!_options.useHardwareRegisteredDepth, "Cannot enable both expensive depth correction and registered depth.")
            let couldApplyCorrection = depthFrame.applyExpensiveCorrection()
            if !couldApplyCorrection {
                os_log(.error, log:OSLog.scanning, "Warning: could not improve depth map accuracy, is your firmware too old?");
            }
        }

        // Upload the new color image for next rendering.
        if let colorFrame = colorFrame {
            uploadGLColorTexture(colorFrame: colorFrame)
        }
        else if !_useColorCamera {
            uploadGLColorTextureFromDepth(depthFrame)
        }
        
        // Update the projection matrices since we updated the frames.
        _display!.depthCameraGLProjectionMatrix = depthFrame.glProjectionMatrix()
        if let colorFrame = colorFrame {
            _display!.colorCameraGLProjectionMatrix = colorFrame.glProjectionMatrix()
        }
        
        // Depth information
        showDistanceToTargetAndHeelIndicator(distanceToTargetInCentimeters(for: depthFrame))
        
        switch _slamState.scannerState {
            
        case .cubePlacement:
            var depthFrameForCubeInitialization: STDepthFrame = depthFrame
            var depthCameraPoseInColorCoordinateFrame = GLKMatrix4Identity;

            // If we are using color images but not using registered depth, then use a registered
            // version to detect the cube, otherwise the cube won't be centered on the color image,
            // but on the depth image, and thus appear shifted.
            if (_useColorCamera && !_options.useHardwareRegisteredDepth)
            {
                depthCameraPoseInColorCoordinateFrame = depthFrame.iOSColorFromDepthExtrinsics()
                depthFrameForCubeInitialization = depthFrame.registered(to:colorFrame)
            }

            // Provide the new depth frame to the cube renderer for ROI highlighting.
            _display!.cubeRenderer!.setDepthFrame(depthFrameForCubeInitialization)
            
            if let cameraPoseInitializer = _slamState.cameraPoseInitializer {
                // Estimate the new scanning volume position.
                if GLKVector3Length(_lastGravity) > 1e-5 {
                    do {
                    
                        try cameraPoseInitializer.updateCameraPose(withGravity: _lastGravity, depthFrame: depthFrameForCubeInitialization)
                        
                        // Since we potentially detected the cube in a registered depth frame, also save the pose
                        // in the original depth sensor coordinate system since this is what we'll use for SLAM
                        // to get the best accuracy.
                        _slamState.initialDepthCameraPose = GLKMatrix4Multiply(cameraPoseInitializer.lastOutput.cameraPose,
                                                                               depthCameraPoseInColorCoordinateFrame);
                    } catch {
                        assertionFailure("Camera pose initializer error.")
                    }
                }

                // Tell the cube renderer whether there is a support plane or not.
                _display!.cubeRenderer!.setCubeHasSupportPlane(cameraPoseInitializer.lastOutput.hasSupportPlane.boolValue)
                
                // Enable the scan button if the pose initializer could estimate a pose.
                self.scanButton.isEnabled = cameraPoseInitializer.lastOutput.hasValidPose.boolValue
            }
            
        case .scanning:
            
            os_log(.debug, log: OSLog.scanning, "Processing Depth Frame")
            
            // First try to estimate the 3D pose of the new frame.
            var trackingMessage: String? = nil
            var keyframeMessage: String? = nil
            
            let depthCameraPoseBeforeTracking: GLKMatrix4 = _slamState.tracker!.lastFrameCameraPose()

            // Integrate it into the current mesh estimate if tracking was successful.
            do {
                try _slamState.tracker!.updateCameraPose(with: depthFrame, colorFrame: colorFrame)
                
                // Update the tracking message.
                trackingMessage = computeTrackerMessage(_slamState.tracker!.trackerHints)
                
                // Set the mesh transparency depending on the current accuracy.
                updateMeshAlphaForPoseAccuracy(_slamState.tracker!.poseAccuracy)
                
                if let tracker = _slamState.tracker {
                    os_log(.debug, log: OSLog.scanning, "Tracker Pose Accuracy is %{Public}@", AccuracyText(_slamState.tracker!.poseAccuracy))
                    
                    // If the tracker accuracy is high, use this frame for mapper update and maybe as a keyframe too.
                    if tracker.poseAccuracy.rawValue >= STTrackerPoseAccuracy.high.rawValue {
                        os_log(.debug, log: OSLog.scanning, "Integrating Depth Frame")
                        _slamState.mapper?.integrateDepthFrame(depthFrame, cameraPose: tracker.lastFrameCameraPose())
                    }
                }
                
                keyframeMessage = maybeAddKeyframeWithDepthFrame(depthFrame, colorFrame: colorFrame, depthCameraPoseBeforeTracking: depthCameraPoseBeforeTracking)
                
                // Tracking messages have higher priority.
                if  let trackingMessage = trackingMessage {
                    showTrackingMessage(trackingMessage)
                }
                else if let keyframeMessage = keyframeMessage {
                    showTrackingMessage(keyframeMessage)
                }
                else {
                    hideTrackingErrorMessage()
                }
                
            } catch let trackingError as NSError {
                os_log(.error, log:OSLog.scanning, "STTracker Error: %{Public}@.", trackingError.localizedDescription)
                
                trackingMessage = trackingError.localizedDescription
            }
            
            _slamState.prevFrameTimeStamp = depthFrame.timestamp
        
            case .viewing:
                break
            // Do nothing, the MeshViewController will take care of this.
        default:
            break
        }
    }
}

private func AccuracyText(_ accuracy :STTrackerPoseAccuracy)->String {
    switch accuracy {
    case .approximate:
        return "Approximate"
    case .high:
        return "High"
    case .low:
        return "Low"
    case .veryLow:
        return "Very Low"
    case .notAvailable:
        return "Not Available"
    default:
        return "Unknown enumeration value"
    }
}

private func distanceToTargetInCentimeters(for depthFrame: STDepthFrame) -> Float {
    let w = depthFrame.width
    let h = depthFrame.height
    let w2 = w/2
    let h2 = h/2
    let depthArray = depthFrame.depthInMillimeters
    return depthArray![Int(w * h2 + w2)] / 10.0
}
