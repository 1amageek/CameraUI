//
//  DeviceController.swift
//  
//
//  Created by nori on 2021/02/12.
//

import Foundation
import AVFoundation

extension AVCaptureDevice {
    public struct Controller {
        @Control(state: .default) public var flashMode: AVCaptureDevice.FlashMode = .auto
        @Control(state: .default) public var livePhotoCaptureMode: Camera.LivePhotoCaptureMode = .on
        @Control(state: .default) public var depthDataDeliveryMode: Camera.DepthDataDeliveryMode = .on
        @Control(state: .default) public var semanticSegmentationMatteTypes: [AVSemanticSegmentationMatte.MatteType] = []
        @Control(state: .default) public var portraitEffectsMatteDeliveryMode: Camera.PortraitEffectsMatteDeliveryMode = .on
        @Control(state: .default) public var photoQualityPrioritizationMode: AVCapturePhotoOutput.QualityPrioritization = .balanced
    }
}

