//
//  PhotoCaptureProcessor.swift
//
//
//  Created by nori on 2021/02/05.
//


import AVFoundation
import Photos

class PhotoCaptureProcessor: NSObject {
    
    lazy var context: CIContext = CIContext()
    
    private(set) var requestedPhotoSettings: AVCapturePhotoSettings
    
    private let willCapturePhotoAnimation: () -> Void
    
    private let livePhotoCaptureHandler: (Bool) -> Void
    
    private let completionHandler: (PhotoCaptureProcessor) -> Void
    
    private let photoProcessingHandler: (Bool) -> Void
    
    private let resourceHandler: (CapturedPhoto) -> Void
    
    private var resource: CapturedPhoto = CapturedPhoto()
    
    private var maxPhotoProcessingTime: CMTime?
    
    init(with requestedPhotoSettings: AVCapturePhotoSettings,
         willCapturePhotoAnimation: @escaping () -> Void,
         livePhotoCaptureHandler: @escaping (Bool) -> Void,
         completionHandler: @escaping (PhotoCaptureProcessor) -> Void,
         photoProcessingHandler: @escaping (Bool) -> Void,
         resourceHandler: @escaping (CapturedPhoto) -> Void
    ) {
        self.requestedPhotoSettings = requestedPhotoSettings
        self.willCapturePhotoAnimation = willCapturePhotoAnimation
        self.livePhotoCaptureHandler = livePhotoCaptureHandler
        self.completionHandler = completionHandler
        self.photoProcessingHandler = photoProcessingHandler
        self.resourceHandler = resourceHandler
    }
    
    private func didFinish() {
        if let livePhotoCompanionMoviePath: String = self.resource.livePhotoCompanionMovieURL?.path {
            if FileManager.default.fileExists(atPath: livePhotoCompanionMoviePath) {
                do {
                    try FileManager.default.removeItem(atPath: livePhotoCompanionMoviePath)
                } catch {
                    print("Could not remove file at url: \(livePhotoCompanionMoviePath)")
                }
            }
        }
        completionHandler(self)
    }
    
}

extension PhotoCaptureProcessor: AVCapturePhotoCaptureDelegate {
    /*
     This extension adopts all of the AVCapturePhotoCaptureDelegate protocol methods.
     */
    
    /// - Tag: WillBeginCapture
    func photoOutput(_ output: AVCapturePhotoOutput, willBeginCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        if resolvedSettings.livePhotoMovieDimensions.width > 0 && resolvedSettings.livePhotoMovieDimensions.height > 0 {
            livePhotoCaptureHandler(true)
        }
        maxPhotoProcessingTime = resolvedSettings.photoProcessingTimeRange.start + resolvedSettings.photoProcessingTimeRange.duration
    }
    
    /// - Tag: WillCapturePhoto
    func photoOutput(_ output: AVCapturePhotoOutput, willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        willCapturePhotoAnimation()
        
        guard let maxPhotoProcessingTime = maxPhotoProcessingTime else {
            return
        }
        
        // Show a spinner if processing time exceeds one second.
        let oneSecond = CMTime(seconds: 1, preferredTimescale: 1)
        if maxPhotoProcessingTime > oneSecond {
            photoProcessingHandler(true)
        }
    }
    
    func handleMatteData(_ photo: AVCapturePhoto, ssmType: AVSemanticSegmentationMatte.MatteType) {
        
        // Find the semantic segmentation matte image for the specified type.
        guard var segmentationMatte: AVSemanticSegmentationMatte = photo.semanticSegmentationMatte(for: ssmType) else { return }
        
        // Retrieve the photo orientation and apply it to the matte image.
        if let orientation: UInt32 = photo.metadata[String(kCGImagePropertyOrientation)] as? UInt32,
           let exifOrientation = CGImagePropertyOrientation(rawValue: orientation) {
            // Apply the Exif orientation to the matte image.
            segmentationMatte = segmentationMatte.applyingExifOrientation(exifOrientation)
        }
        
        var imageOption: CIImageOption!
        
        // Switch on the AVSemanticSegmentationMatteType value.
        switch ssmType {
        case .hair:
            imageOption = .auxiliarySemanticSegmentationHairMatte
        case .skin:
            imageOption = .auxiliarySemanticSegmentationSkinMatte
        case .teeth:
            imageOption = .auxiliarySemanticSegmentationTeethMatte
        default:
            print("This semantic segmentation type is not supported!")
            return
        }
        
        guard let perceptualColorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return }
        
        // Create a new CIImage from the matte's underlying CVPixelBuffer.
        let ciImage: CIImage = CIImage(cvImageBuffer: segmentationMatte.mattingImage,
                                       options: [imageOption: true,
                                                 .colorSpace: perceptualColorSpace])
        
        // Get the HEIF representation of this image.
        guard let imageData: Data = context.heifRepresentation(of: ciImage,
                                                               format: .RGBA8,
                                                               colorSpace: perceptualColorSpace,
                                                               options: [.depthImage: ciImage]) else { return }
        
        // Add the image data to the SSM data array for writing to the photo library.
        self.resource.semanticSegmentationMatteDataArray.append(imageData)
    }
    
    /// - Tag: DidFinishProcessingPhoto
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        photoProcessingHandler(false)
        
        if let error = error {
            print("Error capturing photo: \(error)")
        } else {
            self.resource.photoData = photo.fileDataRepresentation()
        }
        // A portrait effects matte gets generated only if AVFoundation detects a face.
        if var portraitEffectsMatte = photo.portraitEffectsMatte {
            if let orientation = photo.metadata[ String(kCGImagePropertyOrientation) ] as? UInt32 {
                portraitEffectsMatte = portraitEffectsMatte.applyingExifOrientation(CGImagePropertyOrientation(rawValue: orientation)!)
            }
            let portraitEffectsMattePixelBuffer = portraitEffectsMatte.mattingImage
            let portraitEffectsMatteImage = CIImage( cvImageBuffer: portraitEffectsMattePixelBuffer, options: [ .auxiliaryPortraitEffectsMatte: true ] )
            
            guard let perceptualColorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
                self.resource.portraitEffectsMatteData = nil
                return
            }
            self.resource.portraitEffectsMatteData = context.heifRepresentation(of: portraitEffectsMatteImage,
                                                                                format: .RGBA8,
                                                                                colorSpace: perceptualColorSpace,
                                                                                options: [.portraitEffectsMatteImage: portraitEffectsMatteImage])
        } else {
            self.resource.portraitEffectsMatteData = nil
        }
        
        for semanticSegmentationType in output.enabledSemanticSegmentationMatteTypes {
            handleMatteData(photo, ssmType: semanticSegmentationType)
        }
    }
    
    /// - Tag: DidFinishRecordingLive
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishRecordingLivePhotoMovieForEventualFileAt outputFileURL: URL, resolvedSettings: AVCaptureResolvedPhotoSettings) {
        livePhotoCaptureHandler(false)
    }
    
    /// - Tag: DidFinishProcessingLive
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingLivePhotoToMovieFileAt outputFileURL: URL, duration: CMTime, photoDisplayTime: CMTime, resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if error != nil {
            print("Error processing Live Photo companion movie: \(String(describing: error))")
            return
        }
        self.resource.livePhotoCompanionMovieURL = outputFileURL
    }
    
    /// - Tag: DidFinishCapture
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if let error = error {
            print("Error capturing photo: \(error)")
            didFinish()
            return
        }
        
        guard let _ = self.resource.photoData else {
            print("No photo data resource")
            didFinish()
            return
        }
        
        self.resource.uniformTypeIdentifier = self.requestedPhotoSettings.processedFileType.map { $0.rawValue }
        
        completionHandler(self)
        resourceHandler(self.resource)
    }
}
