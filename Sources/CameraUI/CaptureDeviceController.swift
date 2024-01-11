//
//  DeviceController.swift
//  
//
//  Created by nori on 2021/02/12.
//

import Foundation
import AVFoundation

extension AVCaptureDevice {
    public enum LivePhotoCaptureMode { case on, off }
    public enum DepthDataDeliveryMode { case on, off }
    public enum PortraitEffectsMatteDeliveryMode { case on, off }
}

extension AVCaptureDevice {
    public struct Controller {
//        @Control(state: .default) public var maxPhotoDimensions: CMVideoDimensions
        @Control(state: .default) public var flashMode: AVCaptureDevice.FlashMode = .auto
        @Control(state: .default) public var livePhotoCaptureMode: AVCaptureDevice.LivePhotoCaptureMode = .on
        @Control(state: .default) public var depthDataDeliveryMode: AVCaptureDevice.DepthDataDeliveryMode = .on
        @Control(state: .default) public var semanticSegmentationMatteTypes: [AVSemanticSegmentationMatte.MatteType] = []
        @Control(state: .default) public var portraitEffectsMatteDeliveryMode: AVCaptureDevice.PortraitEffectsMatteDeliveryMode = .on
        @Control(state: .default) public var photoQualityPrioritizationMode: AVCapturePhotoOutput.QualityPrioritization = .balanced
    }
}

